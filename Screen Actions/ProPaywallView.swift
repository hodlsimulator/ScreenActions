//
//  ProPaywallView.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//

import SwiftUI
import StoreKit

@MainActor
struct ProPaywallView: View {
    @EnvironmentObject private var pro: ProStore
    @Environment(\.dismiss) private var dismiss

    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "star.circle.fill")
                        Text("Screen Actions Pro")
                            .font(.headline)
                    }
                }

                Section("What you get") {
                    Label("Unlimited CSV exports", systemImage: "tablecells")
                    Label("Unlimited contacts from images", systemImage: "person.crop.rectangle.badge.plus")
                    Label("Unlimited geofenced events", systemImage: "mappin.and.ellipse")
                    Label("“Remember last action” in Safari", systemImage: "checkmark.circle")
                    Label("Early features as they ship", systemImage: "sparkles")
                }

                // Load products on appear; keep graceful fallbacks if nothing returns
                Section("Choose a plan") {
                    // Monthly
                    if let monthly = pro.proMonthly {
                        Button {
                            Task { await act { try await pro.purchaseProMonthly() } }
                        } label: {
                            HStack { Text("Monthly"); Spacer(); Text(monthly.displayPrice).bold() }
                        }
                    } else if pro.isLoadingProducts {
                        Text("Loading monthly price…").foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Monthly unavailable right now").foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") { Task { await pro.loadProducts() } }
                        }
                        .font(.footnote)
                    }

                    // Lifetime
                    if let lifetime = pro.proLifetime {
                        Button {
                            Task { await act { try await pro.purchaseProLifetime() } }
                        } label: {
                            HStack { Text("Lifetime"); Spacer(); Text(lifetime.displayPrice).bold() }
                        }
                    } else if pro.isLoadingProducts {
                        Text("Loading lifetime price…").foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Text("Lifetime unavailable right now").foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") { Task { await pro.loadProducts() } }
                        }
                        .font(.footnote)
                    }

                    Button("Restore Purchases") {
                        Task { await act { try await pro.restorePurchases() } }
                    }

                    if let err = pro.lastLoadError {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }
                .task { await pro.loadProducts() } // idempotent

                if let e = error {
                    Section { Text(e).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Go Pro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func act(_ block: @escaping () async throws -> Void) async {
        do {
            try await block()
            error = nil
            if pro.isPro { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
