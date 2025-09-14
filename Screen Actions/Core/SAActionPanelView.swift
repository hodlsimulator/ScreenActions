//
//  SAActionPanelView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Shared action panel used by the app + extensions.
//  Keeps Auto Detect and direct-run helpers (from A),
//  and adds inline editors & previews (for B).
//

import SwiftUI
import UIKit
import Foundation

public struct SAActionPanelView: View {
    public let selection: String
    public let pageTitle: String
    public let pageURL: String
    public let onDone: (String) -> Void

    // Status / progress
    @State private var isWorking = false
    @State private var status: String?
    @State private var ok = false

    // Inline editors (B)
    @State private var showEvent = false
    @State private var showReminder = false
    @State private var showContact = false
    @State private var showCSV = false

    public init(selection: String, pageTitle: String, pageURL: String, onDone: @escaping (String) -> Void) {
        self.selection = selection
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        self.onDone = onDone
    }

    public var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Selection preview
                Group {
                    Text("Selected Text")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(displaySelection)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .frame(maxHeight: 160)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Page context
                if !pageTitle.isEmpty || !pageURL.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if !pageTitle.isEmpty { Text(pageTitle).font(.subheadline).bold() }
                        if !pageURL.isEmpty {
                            Text(pageURL)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                }

                Divider().padding(.vertical, 2)

                // Actions
                VStack(spacing: 10) {
                    // Primary: Auto Detect (direct-run)
                    Button { runAuto() } label: {
                        rowLabel("Auto Detect", "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)

                    // Manual actions → open editors (B)
                    Button { showReminder = true } label: {
                        rowLabel("Create Reminder", "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    // Optional quick path: direct-run without editing
                    .contextMenu {
                        Button {
                            run { try await createReminder(text: inputText) }
                        } label: {
                            Label("Save Now (no edit)", systemImage: "bolt.fill")
                        }
                    }

                    Button { showEvent = true } label: {
                        rowLabel("Add Calendar Event", "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .contextMenu {
                        Button {
                            run { try await addToCalendar(text: inputText) }
                        } label: {
                            Label("Save Now (no edit)", systemImage: "bolt.fill")
                        }
                    }

                    Button { showContact = true } label: {
                        rowLabel("Extract Contact", "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .contextMenu {
                        Button {
                            run { try await extractContact(text: inputText) }
                        } label: {
                            Label("Save Now (no edit)", systemImage: "bolt.fill")
                        }
                    }

                    Button { showCSV = true } label: {
                        rowLabel("Receipt → CSV", "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .contextMenu {
                        Button {
                            runReceipt()
                        } label: {
                            Label("Export Now (no edit)", systemImage: "bolt.fill")
                        }
                    }
                }

                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(ok ? .green : .red)
                        .padding(.top, 6)
                        .accessibilityLabel("Status")
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Screen Actions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ok ? "Done" : "Cancel") {
                        onDone(status ?? (ok ? "Done" : "Cancelled"))
                    }
                }
            }

            // Inline editors (B)
            .sheet(isPresented: $showEvent) {
                EventEditorView(
                    sourceText: inputText,
                    onCancel: { showEvent = false },
                    onSaved: { message in
                        showEvent = false
                        status = message; ok = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .sheet(isPresented: $showReminder) {
                ReminderEditorView(
                    sourceText: inputText,
                    onCancel: { showReminder = false },
                    onSaved: { message in
                        showReminder = false
                        status = message; ok = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .sheet(isPresented: $showContact) {
                ContactEditorView(
                    sourceText: inputText,
                    onCancel: { showContact = false },
                    onSaved: { message in
                        showContact = false
                        status = message; ok = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .sheet(isPresented: $showCSV) {
                ReceiptCSVPreviewView(
                    sourceText: inputText,
                    onCancel: { showCSV = false },
                    onExported: { message in
                        showCSV = false
                        status = message; ok = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .overlay {
                if isWorking { ProgressView().scaleEffect(1.15) }
            }
        }
    }

    // MARK: - Helpers

    private var displaySelection: String {
        selection.isEmpty ? "No selection found." : selection
    }

    private var inputText: String {
        var t = selection
        if !pageTitle.isEmpty {
            t = t.isEmpty ? pageTitle : t
        }
        if !pageURL.isEmpty {
            t += "\n\(pageURL)"
        }
        return t
    }

    private func run(_ op: @escaping () async throws -> String) {
        isWorking = true; status = nil; ok = false
        Task { @MainActor in
            do {
                let message = try await op()
                status = message
                ok = true
            } catch {
                status = error.localizedDescription
                ok = false
            }
            isWorking = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func runReceipt() {
        run {
            let (msg, url) = try await exportReceiptCSV(text: inputText)
            UIPasteboard.general.url = url
            return "\(msg) (\(url.lastPathComponent))"
        }
    }

    // Auto Detect (direct-run; keeps A’s behaviour)
    private func runAuto() {
        run {
            let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return "Provide text first." }

            let decision = ActionRouter.route(text: text)
            switch decision.kind {
            case .receipt:
                let csv = CSVExporter.makeReceiptCSV(from: text)
                let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
                let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
                UIPasteboard.general.url = url
                return "Auto → Receipt → CSV exported (\(url.lastPathComponent))."

            case .contact:
                let detected = ContactParser.detect(in: text)
                let has = (detected.givenName?.isEmpty == false)
                    || !detected.emails.isEmpty
                    || !detected.phones.isEmpty
                    || (detected.postalAddress != nil)
                guard has else { return "Auto → Contact: No contact details found." }
                let id = try await ContactsService.save(contact: detected)
                return "Auto → Contact saved (\(id))."

            case .event:
                if let range = decision.dateRange ?? DateParser.firstDateRange(in: text) {
                    let title = text
                        .components(separatedBy: .newlines)
                        .first?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Event"
                    let id = try await CalendarService.shared.addEvent(
                        title: title,
                        start: range.start,
                        end: range.end,
                        notes: text
                    )
                    return "Auto → Event created (\(id))."
                } else {
                    fallthrough
                }

            case .reminder:
                let title = text
                    .components(separatedBy: .newlines)
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Todo"
                let due = DateParser.firstDateRange(in: text)?.start
                let id = try await RemindersService.shared.addReminder(
                    title: title,
                    due: due,
                    notes: text
                )
                return "Auto → Reminder created (\(id))."
            }
        }
    }

    @ViewBuilder
    private func rowLabel(_ title: String, _ systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(title)
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Direct-run helpers (kept for parity and context menus)

private func createReminder(text: String) async throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Provide text first." }
    let title = trimmed
        .components(separatedBy: .newlines)
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Todo"
    let due = DateParser.firstDateRange(in: trimmed)?.start
    let id = try await RemindersService.shared.addReminder(title: title, due: due, notes: trimmed)
    return "Reminder created (\(id))."
}

private func addToCalendar(text: String) async throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Provide text first." }
    guard let range = DateParser.firstDateRange(in: trimmed) else { return "No date found." }
    let title = trimmed
        .components(separatedBy: .newlines)
        .first?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Event"
    let id = try await CalendarService.shared.addEvent(title: title, start: range.start, end: range.end, notes: trimmed)
    return "Event created (\(id))."
}

private func extractContact(text: String) async throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Provide text first." }
    let detected = ContactParser.detect(in: trimmed)
    let hasSomething = (detected.givenName?.isEmpty == false)
        || !detected.emails.isEmpty
        || !detected.phones.isEmpty
        || (detected.postalAddress != nil)
    guard hasSomething else { return "No contact details found." }
    let id = try await ContactsService.save(contact: detected)
    return "Contact saved (\(id))."
}

@MainActor
private func exportReceiptCSV(text: String) async throws -> (String, URL) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return ("Provide text first.", AppStorageService.shared.containerURL()) }
    let csv = CSVExporter.makeReceiptCSV(from: trimmed)
    let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
    let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
    return ("CSV exported.", url)
}
