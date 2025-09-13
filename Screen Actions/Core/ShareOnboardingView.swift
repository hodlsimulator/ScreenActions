//
//  ShareOnboardingView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import SwiftUI

/// Persists whether the user finished the “pin to Share sheet” onboarding.
struct ShareOnboardingKeys {
    static let completed = "SAHasCompletedShareOnboarding"
}

struct ShareOnboardingView: View {
    @Binding var isPresented: Bool
    @AppStorage(ShareOnboardingKeys.completed) private var hasCompleted = false
    @State private var showShareSheetHere = false
    @Environment(\.openURL) private var openURL

    private let sampleURL = URL(string: "https://www.apple.com/")!

    var body: some View {
        NavigationStack {
            Form {
                Section("Why pin Screen Actions") {
                    Label("Fast access from any page", systemImage: "speedometer")
                    Label("Works for links, selected text, and images", systemImage: "link")
                    Label("You choose its position", systemImage: "arrow.up.and.down.and.sparkles")
                }

                Section("How to pin it") {
                    stepRow(1, "Open the Share sheet", "Tap \(Image(systemName: "square.and.arrow.up")) in Safari.")
                    stepRow(2, "Go to More", "Swipe the top row of app icons to the end and tap **More**.")
                    stepRow(3, "Tap Edit", "In the top-right, tap **Edit**.")
                    stepRow(4, "Add to Favourites", "Find **Screen Actions**, switch it on, then tap **Add to Favourites**.")
                    stepRow(5, "Drag to the front", "Press-and-hold to drag **Screen Actions** to the front.")
                }

                Section("Try it now") {
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

                    Button {
                        hasCompleted = true
                        isPresented = false
                    } label: {
                        Label("I’ve pinned it", systemImage: "checkmark.circle.fill")
                    }
                }
            }
            .navigationTitle("Pin to Share Sheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { isPresented = false }
                }
            }
            .sheet(isPresented: $showShareSheetHere) {
                ActivityView(activityItems: [sampleURL])
            }
        }
    }

    @ViewBuilder
    private func stepRow(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.15)).frame(width: 28, height: 28)
                Text("\(number)").font(.footnote).bold()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).bold()
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
