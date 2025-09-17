//
//  ContentView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  App home with inline editors for the four actions.
//  Auto Detect now opens the matching editor (like the manual buttons).
//

import SwiftUI

struct ContentView: View {
    @State private var inputText: String = ""
    @State private var status: String = "Ready"
    @FocusState private var isEditorFocused: Bool

    // Onboarding + Settings
    @AppStorage(ShareOnboardingKeys.completed) private var hasCompletedShareOnboarding = false
    @State private var showShareOnboarding = false
    @State private var showSettings = false

    // Editors
    @State private var showEvent = false
    @State private var showReminder = false
    @State private var showContact = false
    @State private var showCSV = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Input") {
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("Type or paste any text…")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $inputText)
                            .frame(minHeight: 180)
                            .focused($isEditorFocused)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                            .font(.body)
                            .accessibilityLabel("Input text")
                    }
                }

                Section("Status") {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel("Status")
                }
            }
            .navigationTitle("Screen Actions")
            .toolbar {
                // Trailing gear for Settings
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }

                // Bottom actions
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        autoDetect()
                    } label: {
                        Label("Auto Detect", systemImage: "wand.and.stars")
                    }

                    Button { showEvent = true } label: {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }

                    Button { showReminder = true } label: {
                        Label("Create Reminder", systemImage: "checkmark.circle.badge.plus")
                    }

                    Button { showContact = true } label: {
                        Label("Extract Contact", systemImage: "person.crop.rectangle.badge.plus")
                    }

                    Button { showCSV = true } label: {
                        Label("Receipt → CSV", systemImage: "doc.text.magnifyingglass")
                    }
                }

                // Keyboard toolbar
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditorFocused = false }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showShareOnboarding) { ShareOnboardingView(isPresented: $showShareOnboarding) }

            // Editors
            .sheet(isPresented: $showEvent) {
                EventEditorView(sourceText: inputText, onCancel: { showEvent = false }) { message in
                    showEvent = false
                    status = message
                }
            }
            .sheet(isPresented: $showReminder) {
                ReminderEditorView(sourceText: inputText, onCancel: { showReminder = false }) { message in
                    showReminder = false
                    status = message
                }
            }
            .sheet(isPresented: $showContact) {
                ContactEditorView(sourceText: inputText, onCancel: { showContact = false }) { message in
                    showContact = false
                    status = message
                }
            }
            .sheet(isPresented: $showCSV) {
                ReceiptCSVPreviewView(sourceText: inputText, onCancel: { showCSV = false }) { message in
                    showCSV = false
                    status = message
                }
            }
            .onAppear {
                if !hasCompletedShareOnboarding {
                    showShareOnboarding = true
                }
            }
        }
    }

    // MARK: - Auto Detect → open editor (no direct-save)
    private func autoDetect() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "Provide text first."
            return
        }
        let decision = ActionRouter.route(text: trimmed)
        switch decision.kind {
        case .receipt:  showCSV = true
        case .contact:  showContact = true
        case .event:    showEvent = true
        case .reminder: showReminder = true
        }
    }
}
