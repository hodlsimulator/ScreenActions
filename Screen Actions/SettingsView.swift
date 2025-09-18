//
//  SettingsView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Updated: 18/09/2025 – Simplified onboarding section (no toggle, no reset).
//

import SwiftUI
import CoreLocation
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    // Keep the stored flag (other parts of the app may read it),
    // but we don’t expose toggles or a reset UI here anymore.
    @AppStorage(ShareOnboardingKeys.completed)
    private var hasCompletedShareOnboarding = false

    @State private var showOnboarding = false

    // Location auth plumbing
    private let locationManager = CLLocationManager()
    @State private var authStatus: CLAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Location & Geofencing
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

                // MARK: Share Sheet
                Section("Share Sheet") {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Open Share Sheet Guide", systemImage: "questionmark.circle")
                    }
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

    // MARK: - Location helpers

    private var statusText: String {
        switch authStatus {
        case .notDetermined:        return "Not requested"
        case .restricted:           return "Restricted"
        case .denied:               return "Denied"
        case .authorizedWhenInUse:  return "While Using"
        case .authorizedAlways:     return "Always"
        @unknown default:           return "Unknown"
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
        // iOS requires a When-In-Use prompt first, then an Always prompt.
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
            openAppSettings() // user can flip to “Always” there
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
