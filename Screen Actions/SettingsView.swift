//
//  SettingsView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Updated: 18/09/2025 — Adds Legal section with EULA & Privacy links.
//

import SwiftUI
import CoreLocation
import UIKit
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var pro: ProStore

    @AppStorage(ShareOnboardingKeys.completed) private var hasCompletedShareOnboarding = false
    @State private var showOnboarding = false
    @State private var tipError: String?

    // Location auth
    private let locationManager = CLLocationManager()
    @State private var authStatus: CLAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Pro / Tip Jar
                Section("Screen Actions Pro") {
                    HStack {
                        Image(systemName: pro.isPro ? "star.circle.fill" : "star.circle")
                            .foregroundStyle(pro.isPro ? .yellow : .secondary)
                        VStack(alignment: .leading) {
                            Text(pro.isPro ? "You’re Pro" : "Unlock Pro")
                                .font(.headline)
                            Text(pro.proDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if pro.isPro == false {
                        NavigationLink("View Plans") {
                            ProPaywallView()
                                .environmentObject(pro)
                        }
                    } else {
                        Button("Restore Purchases") {
                            Task { try? await pro.restorePurchases() }
                        }
                        .disabled(false)
                    }
                }

                Section("Tip Jar") {
                    if let p = pro.tipSmall {
                        Button("Small Tip – \(p.displayPrice)") {
                            Task { await tip { try await pro.purchaseTipSmall() } }
                        }
                    }
                    if let p = pro.tipMedium {
                        Button("Medium Tip – \(p.displayPrice)") {
                            Task { await tip { try await pro.purchaseTipMedium() } }
                        }
                    }
                    if let p = pro.tipLarge {
                        Button("Large Tip – \(p.displayPrice)") {
                            Task { await tip { try await pro.purchaseTipLarge() } }
                        }
                    }
                    if pro.tipSmall == nil && pro.tipMedium == nil && pro.tipLarge == nil {
                        Text("Loading prices…")
                            .foregroundStyle(.secondary)
                    }
                    if let e = tipError {
                        Text(e)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                // MARK: - Location & Geofencing
                Section("Location & Geofencing") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        requestLocationAccess()
                    } label: {
                        Label("Request Location Access", systemImage: "location")
                    }

                    Button {
                        openAppSettings()
                    } label: {
                        Label("Open iOS Settings", systemImage: "gearshape")
                    }
                }

                // MARK: - Share Sheet
                Section("Share Sheet") {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Open Share Sheet Guide", systemImage: "questionmark.circle")
                    }
                }

                // MARK: - Legal
                Section("Legal") {
                    Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Link("Privacy Policy", destination: URL(string: "https://screenactions.com/privacy.html")!)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { refreshAuthStatus() }
            .sheet(isPresented: $showOnboarding) {
                ShareOnboardingView(isPresented: $showOnboarding)
            }
        }
    }

    // MARK: - Tip helper
    private func tip(_ block: @escaping () async throws -> Void) async {
        do {
            try await block()
            tipError = nil
        } catch {
            tipError = error.localizedDescription
        }
    }

    // MARK: - Location helpers
    private var statusText: String {
        switch authStatus {
        case .notDetermined:       return "Not requested"
        case .restricted:          return "Restricted"
        case .denied:              return "Denied"
        case .authorizedWhenInUse: return "While Using"
        case .authorizedAlways:    return "Always"
        @unknown default:          return "Unknown"
        }
    }

    private func refreshAuthStatus() {
        authStatus = locationManager.authorizationStatus
    }

    private func refreshAuthStatusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshAuthStatus()
        }
    }

    private func requestLocationAccess() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.locationManager.requestAlwaysAuthorization()
                self.refreshAuthStatusSoon()
            }
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
            refreshAuthStatusSoon()
        case .authorizedAlways, .restricted, .denied:
            openAppSettings()
        @unknown default:
            openAppSettings()
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
