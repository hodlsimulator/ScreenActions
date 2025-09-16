//
//  SettingsView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Updated: 17/09/2025 – Add “Location & Geofencing” section with a Request Location Access button.
//

import SwiftUI
import CoreLocation
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(ShareOnboardingKeys.completed) private var hasCompletedShareOnboarding = false

    @State private var showOnboarding = false
    @State private var showShareSheetHere = false

    private let sampleURL = URL(string: "https://www.apple.com/")!

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

                // MARK: Share Sheet (existing)
                Section("Share Sheet") {
                    Toggle(isOn: Binding(
                        get: { !hasCompletedShareOnboarding },
                        set: { newValue in
                            hasCompletedShareOnboarding = !newValue
                            if newValue { showOnboarding = true }
                        })
                    ) {
                        Text("Show Share Onboarding Again")
                    }

                    Button { showOnboarding = true } label: {
                        Label("Open Share Onboarding", systemImage: "questionmark.circle")
                    }

                    Button { showShareSheetHere = true } label: {
                        Label("Open Share Sheet Here", systemImage: "square.and.arrow.up")
                    }

                    Button { openURL(sampleURL) } label: {
                        Label("Open Safari (apple.com)", systemImage: "safari")
                    }
                }

                // MARK: Reset (existing)
                Section("Reset") {
                    Button(role: .destructive) {
                        hasCompletedShareOnboarding = false
                    } label: {
                        Label("Reset Onboarding Status", systemImage: "arrow.counterclockwise")
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
            .sheet(isPresented: $showShareSheetHere) {
                ActivityView(activityItems: [sampleURL])
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
