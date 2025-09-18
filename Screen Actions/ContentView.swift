//
//  ContentView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  Compose-first home, calm colour, HIG-friendly.
//  • Default iOS 26 tab bar unchanged.
//  • First tab: “Compose” (square.and.pencil), not a wand.
//  • Auto Detect centred with wand icon; Paste/Scan slightly larger.
//  • Subtle accent gradient background + tinted “cards”.
//  • Clear is a small × inside the editor. Paste/char labels don’t wrap.
//  Users can open the guide from Settings. Auto-present removed by design.
//

import SwiftUI
import UIKit
import Combine

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

    // Live scanner
    @State private var showScanner = false
    @Environment(\.openURL) private var openURL

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
                .tabItem { Label("Calendar", systemImage: symbolName(["calendar.badge.plus", "calendar"])) }
                .tag(ActionTab.calendar)

            // Reminder
            mainScreen
                .tabItem { Label("Reminder", systemImage: symbolName(["checklist", "checkmark.circle"])) }
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
        // Live camera scanner sheet (VisionKit DataScanner)
        .sheet(isPresented: $showScanner) {
            VisualScannerView(
                mode: .barcodesAndText(symbologies: nil),
                recognizesMultipleItems: false,
                onRecognized: { payload in
                    let resolution = VisualScanRouter.resolve(payload)
                    switch resolution {
                    case .openURL(let url):
                        openURL(url)
                    case .saveContact(let dc):
                        Task {
                            do {
                                let id = try await ContactsService.save(contact: dc)
                                status = "Saved contact (\(id))."
                            } catch {
                                status = "Contact save failed: \(error.localizedDescription)"
                            }
                        }
                    case .handoff(let decision, let text):
                        inputText = text
                        switch decision.kind {
                        case .receipt:  showCSV = true
                        case .contact:  showContact = true
                        case .event:    showEvent = true
                        case .reminder: showReminder = true
                        }
                    }
                    showScanner = false
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: selectedTab) { _, newValue in
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
            onAutoDetect: { autoDetect() },
            onScan: { showScanner = true }
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
    var onScan: () -> Void

    @FocusState private var isEditorFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    // Track pasteboard state so the Paste button is stable and predictable.
    @State private var canPaste: Bool = UIPasteboard.general.hasStrings

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
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.accentColor.opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
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
                                .padding(2)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
                                        )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: Color.accentColor.opacity(0.12), radius: 8, y: 4)
                                .accessibilityLabel("Input text")
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

                        // Secondary actions — responsive layout
                        ViewThatFits(in: .horizontal) {
                            // 1) One-row layout (if it truly fits without truncation)
                            HStack(spacing: 12) {
                                charsOut
                                Spacer(minLength: 12)
                                pasteButton
                                scanButton
                                AutoDetectButton(title: "Auto Detect") {
                                    isEditorFocused = false
                                    onAutoDetect()
                                }
                                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            // 2) Fallback: two rows (prevents truncation)
                            VStack(alignment: .trailing, spacing: 8) {
                                HStack(spacing: 12) {
                                    charsOut
                                    Spacer(minLength: 12)
                                    pasteButton
                                    scanButton
                                }
                                AutoDetectButton(title: "Auto Detect") {
                                    isEditorFocused = false
                                    onAutoDetect()
                                }
                                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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
            .formStyle(.grouped)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
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
        // Keep Paste button state fresh
        .onAppear { canPaste = UIPasteboard.general.hasStrings }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                canPaste = UIPasteboard.general.hasStrings
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            canPaste = UIPasteboard.general.hasStrings
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.removedNotification)) { _ in
            canPaste = UIPasteboard.general.hasStrings
        }
    }

    // Subviews used in the responsive row
    private var charsOut: some View {
        Text("\(inputText.count) chars")
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .layoutPriority(0) // lowest priority to give space to buttons
    }

    private var pasteButton: some View {
        Button {
            if let s = UIPasteboard.general.string, !s.isEmpty {
                inputText = s
            } else {
                status = "Nothing to paste."
            }
        } label: {
            Label {
                Text("Paste")
                    .fixedSize(horizontal: true, vertical: false) // never truncate
            } icon: {
                Image(systemName: "doc.on.clipboard")
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8) // slightly larger
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .contentShape(Rectangle())
        .layoutPriority(1) // keep visible before charsOut
        .disabled(!canPaste)
        .opacity(canPaste ? 1.0 : 0.55)
    }

    private var scanButton: some View {
        Button {
            isEditorFocused = false
            onScan()
        } label: {
            Label {
                Text("Scan")
                    .fixedSize(horizontal: true, vertical: false) // never truncate
            } icon: {
                Image(systemName: "camera.viewfinder")
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8) // slightly larger
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .contentShape(Rectangle())
        .layoutPriority(1)
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
}

// MARK: - Primary Auto Detect Button (centred text + wand)
private struct AutoDetectButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            // Icon + text centred together within the button
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.body)
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false) // never truncate
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .center) // centre content inside pill
            .contentShape(Capsule())
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .contentShape(Capsule())
        .accessibilityLabel(title)
    }
}

// MARK: - KindChip (tasteful, minimal colour)
private struct KindChip: View {
    let kind: ScreenActionKind
    var body: some View {
        let (label, icon, tint): (String, String, Color) = {
            switch kind {
            case .event:    return ("Event",    "calendar",                 .blue)
            case .reminder: return ("Reminder", "checkmark.circle",         .green)
            case .contact:  return ("Contact",  "person.crop.circle",       .orange)
            case .receipt:  return ("Receipt",  "tablecells",               .purple)
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
