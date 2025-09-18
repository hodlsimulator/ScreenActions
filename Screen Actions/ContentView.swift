//
//  ContentView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  Compose-first home, calm colour, HIG-friendly.
//  • Default iOS 26 tab bar unchanged.
//  • First tab: “Compose” (square.and.pencil), not a wand.
//  • Auto Detect stays on the right; wand at left; label right-aligned inside.
//  • Subtle accent gradient background + tinted “cards”.
//  • Clear is a small × inside the editor. Paste/char labels don’t wrap.
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
    private enum ActionTab: Hashable { case compose, calendar, reminder, contact, csv }
    @State private var selectedTab: ActionTab = .compose

    var body: some View {
        TabView(selection: $selectedTab) {

            // Compose (home)
            mainScreen
                .tabItem { Label("Compose", systemImage: symbolName(["square.and.pencil"])) }
                .tag(ActionTab.compose)

            // Calendar
            mainScreen
                .tabItem { Label("Calendar", systemImage: symbolName(["calendar.badge.plus","calendar"])) }
                .tag(ActionTab.calendar)

            // Reminder
            mainScreen
                .tabItem { Label("Reminder", systemImage: symbolName(["checklist","checkmark.circle"])) }
                .tag(ActionTab.reminder)

            // Contact
            mainScreen
                .tabItem {
                    Label("Contact", systemImage: symbolName([
                        "person.text.rectangle",
                        "person.crop.rectangle.badge.plus",
                        "person.crop.circle.badge.plus"
                    ]))
                }
                .tag(ActionTab.contact)

            // CSV
            mainScreen
                .tabItem { Label("Receipt · CSV", systemImage: symbolName(["tablecells","doc.text.magnifyingglass"])) }
                .tag(ActionTab.csv)
        }

        // Sheets
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showShareOnboarding) { ShareOnboardingView(isPresented: $showShareOnboarding) }
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

        // NOTE: Auto-present removed by design. Users can open the guide from Settings.
        .onChange(of: selectedTab) { _, newValue in
            // Compose doesn’t auto-run; others open their editor.
            switch newValue {
            case .compose: break
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
        guard !trimmed.isEmpty else { status = "Provide text first."; return }

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
        for name in candidates where UIImage(systemName: name) != nil { return name }
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

    // Accent background
    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                center: .topLeading, startRadius: 0, endRadius: 420
            )
        }
        .ignoresSafeArea()
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

                            // Text editor with tinted card styling
                            TextEditor(text: $inputText)
                                .frame(minHeight: 180)
                                .focused($isEditorFocused)
                                .textInputAutocapitalization(.sentences)
                                .autocorrectionDisabled(false)
                                .font(.body)
                                .padding(2) // space for inner border glow
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                                        )
                                        .shadow(color: Color.accentColor.opacity(0.15), radius: 10, y: 6)
                                )
                                .accessibilityLabel("Input text")
                                // Inline clear (×)
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
                            }

                            // Primary action (right): wand left, label right-aligned
                            AutoDetectButton(title: "Auto Detect") {
                                isEditorFocused = false
                                onAutoDetect()
                            }
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .listRowBackground(Color.clear)
                }

                // PREVIEW
                if let decision {
                    Section("Preview") {
                        HStack(spacing: 10) {
                            KindChip(kind: decision.kind)
                            if let range = decision.dateRange {
                                Text(Self.format(range)).foregroundStyle(.secondary)
                            } else if !decision.reason.isEmpty {
                                Text(decision.reason).foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                }

                // STATUS
                Section("Status") {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden) // let our gradient show through
            .background { backgroundView }
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
        let endText = df.string(from: r.end)

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
        if let s = UIPasteboard.general.string { inputText = s }
    }
}

// MARK: - Primary Auto Detect Button (wand left, text right-aligned)
private struct AutoDetectButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Right-aligned label for visual weight balance
                HStack {
                    Spacer(minLength: 0)
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: true, vertical: false)
                        .multilineTextAlignment(.trailing)
                }
                // Wand anchored to the left
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.body)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(minWidth: 150)
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
