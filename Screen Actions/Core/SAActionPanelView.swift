//
//  SAActionPanelView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Shared action panel used by the app + extensions.
//  This version removes the AppIntents dependency and calls Core services directly.
//

import SwiftUI
import UIKit
import Foundation

public struct SAActionPanelView: View {
    public let selection: String
    public let pageTitle: String
    public let pageURL: String
    public let onDone: (String) -> Void

    @State private var isWorking = false
    @State private var status: String?
    @State private var ok = false

    public init(selection: String, pageTitle: String, pageURL: String, onDone: @escaping (String) -> Void) {
        self.selection = selection
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        self.onDone = onDone
    }

    public var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
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

                if !pageTitle.isEmpty || !pageURL.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if !pageTitle.isEmpty {
                            Text(pageTitle).font(.subheadline).bold()
                        }
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

                VStack(spacing: 10) {
                    // NEW: Auto Detect (primary)
                    Button { runAuto() } label: {
                        rowLabel("Auto Detect", "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)

                    // Manual actions
                    Button {
                        run { try await createReminder(text: inputText) }
                    } label: {
                        rowLabel("Create Reminder", "checkmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        run { try await addToCalendar(text: inputText) }
                    } label: {
                        rowLabel("Add Calendar Event", "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        run { try await extractContact(text: inputText) }
                    } label: {
                        rowLabel("Extract Contact", "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        runReceipt()
                    } label: {
                        rowLabel("Receipt → CSV", "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
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

    // NEW: Auto Detect, using ActionRouter + Core services (no AppIntents dependency)
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

// MARK: - Actions (Core-service implementations, no AppIntents)

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
