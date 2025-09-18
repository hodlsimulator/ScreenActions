//
//  ContentView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  Simple, HIG-friendly home.
//  • Default iOS 26 tab bar (unchanged).
//  • First tab renamed to “Actions” (clearer than Home).
//  • Auto Detect: right-aligned, centred text, wand on left.
//  • Clear = small × inside the TextEditor.
//  • Paste + char counter won’t wrap.
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
    private enum ActionTab: Hashable { case actions, calendar, reminder, contact, csv }
    @State private var selectedTab: ActionTab = .actions

    var body: some View {
        TabView(selection: $selectedTab) {
            // Actions (home)
            mainScreen
                .tabItem { Label("Actions", systemImage: symbolName(["wand.and.stars"])) }
                .tag(ActionTab.actions)

            // Calendar
            mainScreen
                .tabItem { Label("Calendar", systemImage: symbolName(["calendar.badge.plus", "calendar"])) }
                .tag(ActionTab.calendar)

            // Reminder
            mainScreen
                .tabItem { Label("Reminder", systemImage: symbolName(["checklist", "checkmark.circle"])) }
                .tag(ActionTab.reminder)

            // Contact
            mainScreen
                .tabItem {
                    Label("Contact",
                          systemImage: symbolName([
                            "person.text.rectangle",
                            "person.crop.rectangle.badge.plus",
                            "person.crop.circle.badge.plus"
                          ]))
                }
                .tag(ActionTab.contact)

            // CSV
            mainScreen
                .tabItem { Label("Receipt · CSV", systemImage: symbolName(["tablecells", "doc.text.magnifyingglass"])) }
                .tag(ActionTab.csv)
        }
        // Sheets
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
        .onChange(of: selectedTab) { _, newValue in
            // Don’t auto-run on Actions; the others open their editor.
            switch newValue {
            case .actions: break
            case .calendar: showEvent = true
            case .reminder: showReminder = true
            case .contact: showContact = true
            case .csv: showCSV = true
            }
        }
    }

    // MARK: - Main screen (shared across tabs)
    private var mainScreen: some View {
        MainScreen(
            inputText: $inputText,
            status: $status,
            onTapSettings: { showSettings = true },
            onAutoDetect: { autoDetect() }
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

// MARK: - MainScreen (Navigation + tidy form)
private struct MainScreen: View {
    @Binding var inputText: String
    @Binding var status: String

    var onTapSettings: () -> Void
    var onAutoDetect: () -> Void

    @FocusState private var isEditorFocused: Bool

    // Live route preview
    private var decision: RouteDecision? {
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return ActionRouter.route(text: t)
    }

    var body: some View {
        NavigationStack {
            Form {
                // INPUT
                Section("Input") {
                    VStack(alignment: .leading, spacing: 12) {
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
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                                )
                                .accessibilityLabel("Input text")
                                // Inline clear (×) at top-right inside the box
                                .overlay(alignment: .topTrailing) {
                                    if !inputText.isEmpty {
                                        Button {
                                            inputText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundStyle(.secondary)
                                                .padding(6)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Clear text")
                                        .accessibilityHint("Clears the input")
                                    }
                                }
                        }

                        // Secondary actions row
                        HStack(spacing: 12) {
                            Text("\(inputText.count) chars")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)

                            Spacer(minLength: 12)

                            if UIPasteboard.general.hasStrings {
                                Button {
                                    pasteFromClipboard()
                                } label: {
                                    Label("Paste", systemImage: "doc.on.clipboard")
                                        .labelStyle(.titleAndIcon)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .contentShape(Rectangle())
                                .layoutPriority(1)
                            }

                            // Primary action (right), text centred with a wand on the left.
                            PrimaryActionButton(title: "Auto Detect", systemImage: "wand.and.stars") {
                                isEditorFocused = false
                                onAutoDetect()
                            }
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .layoutPriority(2)
                        }
                    }
                }

                // PREVIEW
                if let decision {
                    Section("Preview") {
                        HStack(spacing: 10) {
                            KindChip(kind: decision.kind)
                            if let range = decision.dateRange {
                                Text(Self.format(range))
                                    .foregroundStyle(.secondary)
                            } else if !decision.reason.isEmpty {
                                Text(decision.reason)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                }

                // STATUS
                Section("Status") {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel("Status")
                }
            }
            .navigationTitle("Screen Actions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onTapSettings) { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditorFocused = false }
                }
            }
        }
    }

    // Date range → concise, friendly text
    private static func format(_ r: DetectedDateRange) -> String {
        let df = DateFormatter()
        df.locale = .current
        df.doesRelativeDateFormatting = true
        df.dateStyle = .medium
        df.timeStyle = .short

        let startText = df.string(from: r.start)
        let endText   = df.string(from: r.end)

        let comps = DateComponentsFormatter()
        comps.allowedUnits = [.hour, .minute]
        comps.unitsStyle = .short

        let dur = max(0, r.end.timeIntervalSince(r.start))
        if let durText = comps.string(from: dur), !durText.isEmpty {
            return "From \(startText) to \(endText) (\(durText))"
        }
        return "From \(startText) to \(endText)"
    }

    // Paste helper
    private func pasteFromClipboard() {
        if let s = UIPasteboard.general.string {
            inputText = s
        }
    }
}

// MARK: - PrimaryActionButton (centred title + leading icon)
private struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Centred title
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Leading icon (keeps visual balance)
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 148) // ensures room for centred title + icon
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .contentShape(Capsule())
    }
}

// MARK: - KindChip (tasteful, minimal colour)
private struct KindChip: View {
    let kind: ScreenActionKind

    var body: some View {
        let (label, icon, tint): (String, String, Color) = {
            switch kind {
            case .event:    return ("Event", "calendar", .blue)
            case .reminder: return ("Reminder", "checkmark.circle", .green)
            case .contact:  return ("Contact", "person.crop.circle", .orange)
            case .receipt:  return ("Receipt", "tablecells", .purple)
            }
        }()

        return HStack(spacing: 6) {
            Image(systemName: icon)
            Text(label).font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: Capsule())
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
    }
}
