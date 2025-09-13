//
//  ShareOnboardingView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import SwiftUI

struct ShareOnboardingKeys {
    static let completed = "SAHasCompletedShareOnboarding"
}

struct ShareOnboardingView: View {
    @Binding var isPresented: Bool
    @AppStorage(ShareOnboardingKeys.completed) private var hasCompleted = false
    @Environment(\.openURL) private var openURL

    @State private var showShareSheetHere = false
    @State private var step1 = OnboardingProgress.step1DidOpenInAppShare
    @State private var step2 = OnboardingProgress.step2DidOpenMoreAndEdit
    @State private var step3 = OnboardingProgress.step3DidAddToFavourites
    @State private var step4 = OnboardingProgress.wasPingedRecently()
    @State private var step5 = OnboardingProgress.step5DidMoveToFront

    private let sampleURL = URL(string: "https://www.apple.com/")!

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Why pin Screen Actions")) {
                    Label("Fast access from any page", systemImage: "speedometer")
                    Label("Works for links, selected text, and images", systemImage: "link")
                    Label("You choose its position", systemImage: "arrow.up.and.down.and.sparkles")
                }

                Section(header: Text("Checklist")) {
                    checklistRow(done: step1, title: "Open the Share sheet here") {
                        showShareSheetHere = true
                    } subtitle: {
                        Text("We’ll open the system share sheet now.")
                    }

                    checklistRow(done: step2, title: "Go to More → Edit (top-right)") {
                        step2.toggle()
                        OnboardingProgress.step2DidOpenMoreAndEdit = step2
                    } subtitle: {
                        Text("In the top row of apps, swipe to the end, tap More, then Edit.")
                    }

                    checklistRow(done: step3, title: "Add “Screen Actions” to Favourites") {
                        step3.toggle()
                        OnboardingProgress.step3DidAddToFavourites = step3
                    } subtitle: {
                        Text("Find Screen Actions, enable it, tap Add to Favourites.")
                    }

                    checklistRow(done: step4, title: "Launch Screen Actions from Safari once") {
                        OnboardingProgress.beginExpectedPingWindow()
                        openURL(sampleURL)
                    } subtitle: {
                        Text("Share any page in Safari and pick Screen Actions. We’ll detect it automatically.")
                    }

                    checklistRow(done: step5, title: "Drag it to the front of the row") {
                        step5.toggle()
                        OnboardingProgress.step5DidMoveToFront = step5
                    } subtitle: {
                        Text("Press-and-hold in Favourites to reorder.")
                    }
                }

                if allDone {
                    Section {
                        Button(action: {
                            hasCompleted = true
                            isPresented = false
                        }) {
                            Label("Finish — All set!", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(SAConditionalButtonStyle(prominent: true))
                    }
                }
            }
            .navigationBarTitle("Pin to Share Sheet", displayMode: .inline)
            .navigationBarItems(leading:
                Button("Close") { isPresented = false }
            )
            .sheet(isPresented: $showShareSheetHere, onDismiss: {
                step1 = true
                OnboardingProgress.step1DidOpenInAppShare = true
            }) {
                ActivityView(activityItems: [sampleURL])
            }
            // iOS 13+ safe wrapper that uses the new two-parameter API on iOS 17+
            .saOnScenePhaseChange { _, newPhase in
                if newPhase == .active {
                    step4 = OnboardingProgress.wasPingedRecently()
                }
            }
        }
    }

    private var allDone: Bool {
        step1 && step2 && step3 && step4 && step5
    }

    @ViewBuilder
    private func checklistRow(
        done: Bool,
        title: String,
        action: @escaping () -> Void,
        subtitle: () -> Text
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                Text(title).fontWeight(.semibold)
                Spacer()
                Button(action: action) {
                    Text(done ? "Done" : "Do it")
                }
                // Single conditional style avoids the ternary type mismatch
                .buttonStyle(SAConditionalButtonStyle(prominent: !done))
            }
            subtitle()
                .foregroundColor(.secondary)
                .font(.footnote)
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 4)
    }
}

// MARK: - iOS 13+ safe scenePhase change wrapper

private struct SAOnChangeScenePhaseModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let handler: (_ old: ScenePhase?, _ new: ScenePhase) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: scenePhase) { oldValue, newValue in
                handler(oldValue, newValue)
            }
        } else {
            content.onChange(of: scenePhase) { newValue in
                handler(nil, newValue)
            }
        }
    }
}

private extension View {
    func saOnScenePhaseChange(_ handler: @escaping (_ old: ScenePhase?, _ new: ScenePhase) -> Void) -> some View {
        modifier(SAOnChangeScenePhaseModifier(handler: handler))
    }
}

// MARK: - Single conditional button style (iOS 13+)

struct SAConditionalButtonStyle: ButtonStyle {
    var prominent: Bool
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(
                Group {
                    if prominent {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1.0))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.accentColor, lineWidth: 1)
                    }
                }
            )
            .foregroundColor(prominent ? .white : Color.accentColor)
            .opacity(configuration.isPressed ? 0.95 : 1.0)
    }
}
