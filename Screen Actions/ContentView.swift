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
import UIKit

struct ContentView: View {
    // MARK: - State
    @State private var inputText: String = ""
    @State private var status: String = "Ready"

    // Onboarding + Settings
    @AppStorage(ShareOnboardingKeys.completed) private var hasCompletedShareOnboarding = false
    @State private var showShareOnboarding = false
    @State private var showSettings = false

    // Editors
    @State private var showEvent = false
    @State private var showReminder = false
    @State private var showContact = false
    @State private var showCSV = false

    // Tab routing
    private enum ActionTab: Hashable { case auto, calendar, reminder, contact, csv }
    @State private var selectedTab: ActionTab = .auto

    var body: some View {
        TabView(selection: $selectedTab) {
            // All tabs show the same main screen; selection triggers actions/sheets.
            mainScreen
                .tabItem {
                    Label("Auto", systemImage: symbolName(["wand.and.stars"]))
                }
                .tag(ActionTab.auto)

            mainScreen
                .tabItem {
                    Label("Calendar", systemImage: symbolName(["calendar.badge.plus", "calendar"]))
                }
                .tag(ActionTab.calendar)

            mainScreen
                .tabItem {
                    Label("Reminder", systemImage: symbolName(["checklist", "checkmark.circle"]))
                }
                .tag(ActionTab.reminder)

            mainScreen
                .tabItem {
                    Label("Contact", systemImage: symbolName([
                        "person.text.rectangle",
                        "person.crop.rectangle.badge.plus",
                        "person.crop.circle.badge.plus"
                    ]))
                }
                .tag(ActionTab.contact)

            mainScreen
                .tabItem {
                    Label("Receipt · CSV", systemImage: symbolName(["tablecells", "doc.text.magnifyingglass"]))
                }
                .tag(ActionTab.csv)
        }
        // Present sheets from the container so they work regardless of selected tab.
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showShareOnboarding) {
            ShareOnboardingView(isPresented: $showShareOnboarding)
        }
        .sheet(isPresented: $showEvent) {
            EventEditorView(
                sourceText: inputText,
                onCancel: { showEvent = false },
                onSaved: { message in showEvent = false; status = message }
            )
        }
        .sheet(isPresented: $showReminder) {
            ReminderEditorView(
                sourceText: inputText,
                onCancel: { showReminder = false },
                onSaved: { message in showReminder = false; status = message }
            )
        }
        .sheet(isPresented: $showContact) {
            ContactEditorView(
                sourceText: inputText,
                onCancel: { showContact = false },
                onSaved: { message in showContact = false; status = message }
            )
        }
        .sheet(isPresented: $showCSV) {
            ReceiptCSVPreviewView(
                sourceText: inputText,
                onCancel: { showCSV = false },
                onExported: { message in showCSV = false; status = message }
            )
        }
        .onAppear {
            if !hasCompletedShareOnboarding { showShareOnboarding = true }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            // Selecting a tab runs the action; UI stays on the same main screen.
            switch newValue {
            case .auto:
                autoDetect()
            case .calendar:
                showEvent = true
            case .reminder:
                showReminder = true
            case .contact:
                showContact = true
            case .csv:
                showCSV = true
            }
        }
    }

    // MARK: - Main screen (shared across tabs)
    private var mainScreen: some View {
        MainScreen(
            inputText: $inputText,
            status: $status,
            onTapSettings: { showSettings = true }
        )
    }

    // MARK: - Auto Detect router
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

    // MARK: - SF Symbols fallback helper
    private func symbolName(_ candidates: [String]) -> String {
        for name in candidates {
            if UIImage(systemName: name) != nil { return name }
        }
        return candidates.last ?? "square"
    }
}

// MARK: - MainScreen (Navigation + form)
private struct MainScreen: View {
    @Binding var inputText: String
    @Binding var status: String
    var onTapSettings: () -> Void

    @FocusState private var isEditorFocused: Bool

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onTapSettings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditorFocused = false }
                }
            }
        }
    }
}
