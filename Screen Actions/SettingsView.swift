//
//  SettingsView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(ShareOnboardingKeys.completed) private var hasCompletedShareOnboarding = false

    @State private var showOnboarding = false
    @State private var showShareSheetHere = false

    private let sampleURL = URL(string: "https://www.apple.com/")!

    var body: some View {
        NavigationStack {
            Form {
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

                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Open Share Onboarding", systemImage: "questionmark.circle")
                    }

                    Button {
                        showShareSheetHere = true
                    } label: {
                        Label("Open Share Sheet Here", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        openURL(sampleURL)
                    } label: {
                        Label("Open Safari (apple.com)", systemImage: "safari")
                    }
                }

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
            .sheet(isPresented: $showOnboarding) {
                ShareOnboardingView(isPresented: $showOnboarding)
            }
            .sheet(isPresented: $showShareSheetHere) {
                ActivityView(activityItems: [sampleURL])
            }
        }
    }
}
