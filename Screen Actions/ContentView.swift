//
//  ContentView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  Compose-first home, HIG-friendly.
//  – Re-tapping an already-selected tab opens its editor.
//  – Tab bar hides while the keyboard is visible (prevents jump).
//  – The existing “Auto Detect” button is one-tap even if the keyboard is up:
//    it dismisses the keyboard and then runs detection with the committed text.
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
    private enum ActionTab: Int, Hashable {
        case compose, calendar, reminder, contact, csv
    }
    @State private var selectedTab: ActionTab = .compose

    var body: some View {
        // Custom tab container for reselection callbacks.
        TabBarContainer(
            selection: $selectedTab,
            onSelect: { tab in handleTabTap(tab) },
            inputText: $inputText,
            status: $status,
            onTapSettings: { showSettings = true },
            onAutoDetect: { autoDetect() },
            onScan: { showScanner = true },
            // 👇 ensure handoff is consumed when the UI appears/activates
            onCheckHandoff: { consumeHandoffIfAny() }
        )
        // Sheets
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
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
        // Live camera scanner
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
    }

    private func consumeHandoffIfAny() {
        if let h = Handoff.take() {
            inputText = h.text
            switch h.kind {
            case .event:    showEvent = true
            case .reminder: showReminder = true
            case .contact:  showContact = true
            case .csv:      showCSV = true
            }
        }
    }

    // MARK: - Any tab tap (including reselection)
    private func handleTabTap(_ tab: ActionTab) {
        switch tab {
        case .compose:
            break
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
        for name in candidates where UIImage(systemName: name) != nil {
            return name
        }
        return candidates.last ?? "square"
    }

    // MARK: - MainScreen (Navigation + tidy form)
    private struct MainScreen: View {
        @Binding var inputText: String
        @Binding var status: String
        var onTapSettings: () -> Void
        var onAutoDetect: () -> Void
        var onScan: () -> Void
        // 👇 new callback so MainScreen can trigger the outer handoff reader
        var onCheckHandoff: () -> Void

        @FocusState private var isEditorFocused: Bool
        @Environment(\.scenePhase) private var scenePhase

        // Track pasteboard state so the Paste button is stable and predictable.
        @State private var canPaste: Bool = UIPasteboard.general.hasStrings

        // One-tap Auto Detect while keyboard is up:
        // we wait for focus to drop so text composition is fully committed.
        @State private var pendingAutoDetect = false

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

                            // Secondary actions — responsive layout (unchanged look)
                            ViewThatFits(in: .horizontal) {
                                // 1) One-row layout (if it fits)
                                HStack(spacing: 12) {
                                    charsOut
                                    Spacer(minLength: 12)
                                    pasteButton
                                    scanButton
                                    AutoDetectButton(title: "Auto Detect") {
                                        if isEditorFocused {
                                            pendingAutoDetect = true
                                            isEditorFocused = false   // dismiss keyboard first
                                        } else {
                                            onAutoDetect()
                                        }
                                    }
                                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }

                                // 2) Fallback: two rows
                                VStack(alignment: .trailing, spacing: 8) {
                                    HStack(spacing: 12) {
                                        charsOut
                                        Spacer(minLength: 12)
                                        pasteButton
                                        scanButton
                                    }
                                    AutoDetectButton(title: "Auto Detect") {
                                        if isEditorFocused {
                                            pendingAutoDetect = true
                                            isEditorFocused = false
                                        } else {
                                            onAutoDetect()
                                        }
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
                        Button(action: onTapSettings) {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                    // Minimal keyboard toolbar (no duplicate Auto Detect).
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isEditorFocused = false }
                    }
                }
            }
            // Keep Paste button state fresh
            .onAppear {
                canPaste = UIPasteboard.general.hasStrings
                onCheckHandoff()              // ✅ consume handoff on appear
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    canPaste = UIPasteboard.general.hasStrings
                    onCheckHandoff()          // ✅ consume handoff when active
                }
            }
            .onOpenURL { _ in
                canPaste = UIPasteboard.general.hasStrings
                onCheckHandoff()              // ✅ consume handoff when opened via URL even if app is already frontmost
            }
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
                canPaste = UIPasteboard.general.hasStrings
            }
            .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.removedNotification)) { _ in
                canPaste = UIPasteboard.general.hasStrings
            }
            // Fire pending Auto Detect after focus actually drops so text is committed.
            .onChange(of: isEditorFocused) { _, focused in
                if !focused && pendingAutoDetect {
                    DispatchQueue.main.async {
                        onAutoDetect()
                        pendingAutoDetect = false
                    }
                }
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
                .layoutPriority(0)
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
                        .fixedSize(horizontal: true, vertical: false)
                } icon: {
                    Image(systemName: "doc.on.clipboard")
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .contentShape(Rectangle())
            .layoutPriority(1)
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
                        .fixedSize(horizontal: true, vertical: false)
                } icon: {
                    Image(systemName: "camera.viewfinder")
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 8)
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

    // MARK: - Primary Auto Detect Button (unchanged appearance)
    private struct AutoDetectButton: View {
        let title: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.body)
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .center)
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

    // MARK: - UIKit TabBar wrapper (fires on every selection; hides during keyboard)
    private struct TabBarContainer: UIViewControllerRepresentable {
        @Binding var selection: ActionTab
        var onSelect: (ActionTab) -> Void

        @Binding var inputText: String
        @Binding var status: String
        var onTapSettings: () -> Void
        var onAutoDetect: () -> Void
        var onScan: () -> Void
        // 👇 new: pass through to MainScreen
        var onCheckHandoff: () -> Void

        func makeUIViewController(context: Context) -> UITabBarController {
            let tbc = UITabBarController()
            tbc.delegate = context.coordinator

            // Build five hosts with identical content but different tab items.
            let composeVC  = UIHostingController(rootView: MainScreen(inputText: $inputText, status: $status, onTapSettings: onTapSettings, onAutoDetect: onAutoDetect, onScan: onScan, onCheckHandoff: onCheckHandoff))
            let calendarVC = UIHostingController(rootView: MainScreen(inputText: $inputText, status: $status, onTapSettings: onTapSettings, onAutoDetect: onAutoDetect, onScan: onScan, onCheckHandoff: onCheckHandoff))
            let reminderVC = UIHostingController(rootView: MainScreen(inputText: $inputText, status: $status, onTapSettings: onTapSettings, onAutoDetect: onAutoDetect, onScan: onScan, onCheckHandoff: onCheckHandoff))
            let contactVC  = UIHostingController(rootView: MainScreen(inputText: $inputText, status: $status, onTapSettings: onTapSettings, onAutoDetect: onAutoDetect, onScan: onScan, onCheckHandoff: onCheckHandoff))
            let csvVC      = UIHostingController(rootView: MainScreen(inputText: $inputText, status: $status, onTapSettings: onTapSettings, onAutoDetect: onAutoDetect, onScan: onScan, onCheckHandoff: onCheckHandoff))

            composeVC.tabBarItem  = UITabBarItem(title: "Compose", image: UIImage(systemName: symbolName(["square.and.pencil"])), selectedImage: nil)
            calendarVC.tabBarItem = UITabBarItem(title: "Calendar", image: UIImage(systemName: symbolName(["calendar.badge.plus", "calendar"])), selectedImage: nil)
            reminderVC.tabBarItem = UITabBarItem(title: "Reminder", image: UIImage(systemName: symbolName(["checklist", "checkmark.circle"])), selectedImage: nil)
            contactVC.tabBarItem  = UITabBarItem(title: "Contact",  image: UIImage(systemName: symbolName(["person.text.rectangle", "person.crop.rectangle.badge.plus", "person.crop.circle.badge.plus"])), selectedImage: nil)
            csvVC.tabBarItem      = UITabBarItem(title: "Receipt · CSV", image: UIImage(systemName: symbolName(["tablecells", "doc.text.magnifyingglass"])), selectedImage: nil)

            tbc.viewControllers = [composeVC, calendarVC, reminderVC, contactVC, csvVC]
            tbc.selectedIndex = selection.rawValue

            // Hide/show the tab bar with the keyboard (selector-based on main actor).
            context.coordinator.attach(to: tbc)

            return tbc
        }

        func updateUIViewController(_ tbc: UITabBarController, context: Context) {
            // Keep the selected index in sync with SwiftUI state.
            let target = selection.rawValue
            if tbc.selectedIndex != target {
                tbc.selectedIndex = target
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        // Coordinator runs on the main actor so UI access is safe and compiler-clean.
        @MainActor
        final class Coordinator: NSObject, UITabBarControllerDelegate {
            var parent: TabBarContainer
            weak var tabBarController: UITabBarController?

            init(_ parent: TabBarContainer) { self.parent = parent }

            func attach(to tbc: UITabBarController) {
                self.tabBarController = tbc
                let nc = NotificationCenter.default
                nc.addObserver(self, selector: #selector(kbWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
                nc.addObserver(self, selector: #selector(kbWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
            }

            deinit {
                NotificationCenter.default.removeObserver(self)
            }

            // MARK: Keyboard handlers (main actor)
            @objc private func kbWillShow(_ note: Notification) {
                tabBarController?.tabBar.isHidden = true
            }

            @objc private func kbWillHide(_ note: Notification) {
                tabBarController?.tabBar.isHidden = false
            }

            func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
                guard
                    let idx = tabBarController.viewControllers?.firstIndex(of: viewController),
                    let tab = ActionTab(rawValue: idx)
                else { return }

                // Always fire, even when the user re-taps the already selected tab.
                self.parent.selection = tab
                self.parent.onSelect(tab)
            }
        }

        // Local SF Symbols fallback helper for UIKit items
        private func symbolName(_ candidates: [String]) -> String {
            for name in candidates where UIImage(systemName: name) != nil {
                return name
            }
            return candidates.last ?? "square"
        }
    }
}
