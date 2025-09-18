//
//  ProStore.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//

import Foundation
import StoreKit
import Combine

@MainActor
final class ProStore: ObservableObject {
    // Mirror to App Group so extensions can read Pro status
    private let groupID = AppStorageService.appGroupID
    private var groupDefaults: UserDefaults {
        UserDefaults(suiteName: groupID) ?? .standard
    }

    @Published private(set) var isPro: Bool = false
    @Published private(set) var proDescription: String = "Not Pro"
    @Published private(set) var productsByID: [String: Product] = [:]

    // Convenience accessors
    var proMonthly: Product?  { productsByID[SAProducts.proMonthly] }
    var proLifetime: Product? { productsByID[SAProducts.proLifetime] }
    var tipSmall: Product?    { productsByID[SAProducts.tipSmall] }
    var tipMedium: Product?   { productsByID[SAProducts.tipMedium] }
    var tipLarge: Product?    { productsByID[SAProducts.tipLarge] }

    private var updatesTask: Task<Void,Never>?

    // Call once at app start
    func bootstrap() async {
        await loadProducts()
        await refreshEntitlement()
        startListeningForTransactions()
    }

    deinit { updatesTask?.cancel() }

    // MARK: - StoreKit plumbing

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Array(SAProducts.all))
            var map: [String: Product] = [:]
            for p in products { map[p.id] = p }
            self.productsByID = map
        } catch {
            self.productsByID = [:]
        }
    }

    func purchaseProMonthly() async throws {
        try await purchase(product: try require(proMonthly))
        await refreshEntitlement()
    }

    func purchaseProLifetime() async throws {
        try await purchase(product: try require(proLifetime))
        await refreshEntitlement()
    }

    func purchaseTipSmall() async throws { try await purchase(product: try require(tipSmall)) }
    func purchaseTipMedium() async throws { try await purchase(product: try require(tipMedium)) }
    func purchaseTipLarge() async throws { try await purchase(product: try require(tipLarge)) }

    private func purchase(product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlement()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let err):
            // err is non-optional; just throw it.
            throw err
        case .verified(let safe):
            return safe
        }
    }

    private func startListeningForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                if case .verified(let tx) = update {
                    await tx.finish()
                    await self.refreshEntitlement()
                }
            }
        }
    }

    // MARK: - Entitlement

    func refreshEntitlement() async {
        var active = false
        var desc = "Not Pro"
        var subExpiry: Date?

        for await ent in Transaction.currentEntitlements {
            guard case .verified(let tx) = ent else { continue }
            guard SAProducts.proSet.contains(tx.productID) else { continue }

            if tx.productID == SAProducts.proLifetime {
                active = true
                desc = "Pro (Lifetime)"
            } else {
                if let exp = tx.expirationDate, exp > Date() {
                    active = true
                    subExpiry = exp
                    let df = DateFormatter()
                    df.dateStyle = .medium
                    df.timeStyle = .none
                    df.locale = .current
                    desc = "Pro (Monthly) · renews by \(df.string(from: exp))"
                }
            }
        }

        self.isPro = active
        self.proDescription = desc

        // Mirror into App Group so the Safari Web Extension can read it.
        groupDefaults.set(active, forKey: "iap.pro.active")
        if let e = subExpiry { groupDefaults.set(e.timeIntervalSince1970, forKey: "iap.pro.exp") }
        else { groupDefaults.removeObject(forKey: "iap.pro.exp") }
        groupDefaults.synchronize()
    }

    // MARK: - Helpers

    private func require<T>(_ v: T?) throws -> T {
        if let v { return v }
        throw NSError(domain: "IAP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Product unavailable. Please try again shortly."])
    }
}
