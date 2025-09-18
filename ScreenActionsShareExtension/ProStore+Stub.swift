//
//  ProStore+Stub.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//
//  ProStore+Stub.swift — Share Extension stub
//  Mirrors Pro entitlement from App Group; blocks purchases in the extension.
//

import Foundation
import Combine
import StoreKit

@MainActor
final class ProStore: ObservableObject {
    private let groupID = AppStorageService.appGroupID
    private var groupDefaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    // Public surface expected by the UI
    @Published private(set) var isPro: Bool = false
    @Published private(set) var proDescription: String = "Not Pro"

    // Present but empty — so ProPaywallView compiles and shows friendly messaging.
    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var missingProductIDs: Set<String> = []
    @Published private(set) var lastLoadError: String?

    // Convenience props expected by ProPaywallView
    var proMonthly: Product? { nil }
    var proLifetime: Product? { nil }
    var tipSmall: Product? { nil }
    var tipMedium: Product? { nil }
    var tipLarge: Product? { nil }

    init() {
        // Pick up mirrored entitlement written by the main app.
        let active = groupDefaults.bool(forKey: "iap.pro.active")
        self.isPro = active
        self.proDescription = active ? "Pro (mirrored)" : "Not Pro"
    }

    func bootstrap() async { await refreshEntitlement() }

    func loadProducts() async {
        // Don’t use StoreKit from an extension; just surface a friendly message.
        isLoadingProducts = false
        lastLoadError = "Purchases aren’t available in the Share Extension. Open the app to buy Pro."
        productsByID = [:]
        missingProductIDs = []
    }

    func refreshEntitlement() async {
        let active = groupDefaults.bool(forKey: "iap.pro.active")
        self.isPro = active
        self.proDescription = active ? "Pro (mirrored)" : "Not Pro"
    }

    // No purchases inside the extension
    func purchaseProMonthly() async throws { throw notAvailable() }
    func purchaseProLifetime() async throws { throw notAvailable() }
    func purchaseTipSmall() async throws { throw notAvailable() }
    func purchaseTipMedium() async throws { throw notAvailable() }
    func purchaseTipLarge() async throws { throw notAvailable() }
    func restorePurchases() async throws { throw notAvailable() }

    private func notAvailable() -> NSError {
        NSError(
            domain: "IAP",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey:
                "Purchases aren’t available in the Share Extension. Open the app to manage Pro."]
        )
    }
}
