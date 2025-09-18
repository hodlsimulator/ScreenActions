//
//  SAActionPanelView.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//
//  SAActionPanelView.swift — Share Extension
//  Presents the same editor sheets as the app.
//

import SwiftUI
import UIKit
import Foundation

@MainActor
public struct SAActionPanelView: View {
    public let selection: String
    public let pageTitle: String
    public let pageURL: String
    public let imageData: Data? // enables Document Mode
    public let onDone: (String) -> Void

    @State private var isWorking = false
    @State private var status: String? = nil
    @State private var ok = false

    // Editor sheets
    @State private var showEvent = false
    @State private var showReminder = false
    @State private var showContact = false
    @State private var showCSV = false

    @State private var smudgeNote: String? = nil

    public init(
        selection: String,
        pageTitle: String,
        pageURL: String,
        imageData: Data? = nil,
        onDone: @escaping (String) -> Void
    ) {
        self.selection = selection
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        self.imageData = imageData
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

                if imageData != nil {
                    Label("Image detected — Document Mode available.", systemImage: "doc.viewfinder")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider().padding(.vertical, 2)

                // Actions
                VStack(spacing: 10) {
                    Button { openAutoEditor() } label: { rowLabel("Auto Detect", "wand.and.stars") }
                        .buttonStyle(.borderedProminent)

                    Button { showReminder = true } label: { rowLabel("Create Reminder", "checkmark.circle") }
                        .buttonStyle(.bordered)
                        .contextMenu {
                            Button {
                                run { try await createReminder(text: inputText) }
                            } label: { Label("Save Now (no edit)", systemImage: "bolt.fill") }
                        }

                    Button { showEvent = true } label: { rowLabel("Add Calendar Event", "calendar.badge.plus") }
                        .buttonStyle(.bordered)
                        .contextMenu {
                            Button {
                                run { try await addToCalendar(text: inputText) }
                            } label: { Label("Save Now (no edit)", systemImage: "bolt.fill") }
                        }

                    Button { showContact = true } label: { rowLabel("Extract Contact", "person.crop.circle.badge.plus") }
                        .buttonStyle(.bordered)
                        .contextMenu {
                            if imageData != nil {
                                Button {
                                    run {
                                        guard let data = imageData else { return "No image supplied." }
                                        if #available(iOS 26, *) {
                                            var hint: VisionDocumentReader.SmudgeHint?
                                            let list = try await VisionDocumentReader.contacts(from: data, smudgeHint: &hint)
                                            guard !list.isEmpty else { return "No contact details found." }
                                            var saved = 0
                                            for c in list {
                                                let ok = (c.givenName?.isEmpty == false)
                                                    || (c.familyName?.isEmpty == false)
                                                    || !c.emails.isEmpty
                                                    || !c.phones.isEmpty
                                                    || (c.postalAddress != nil)
                                                if ok {
                                                    _ = try await ContactsService.save(contact: c)
                                                    saved += 1
                                                }
                                            }
                                            if let s = hint, s.isLikely {
                                                smudgeNote = "Tip: Your camera lens looked smudged (\(Int(s.confidence * 100))%)."
                                            }
                                            return saved == 1 ? "Saved 1 contact." : "Saved \(saved) contacts."
                                        } else {
                                            return "Requires iOS 26."
                                        }
                                    }
                                } label: { Label("Save From Image (batch)", systemImage: "person.crop.rectangle.stack") }
                            }

                            Button {
                                run { try await extractContact(text: inputText) }
                            } label: { Label("Save Now (no edit)", systemImage: "bolt.fill") }
                        }

                    Button { showCSV = true } label: { rowLabel("Receipt → CSV", "doc.badge.plus") }
                        .buttonStyle(.bordered)
                        .contextMenu {
                            if imageData != nil {
                                Button {
                                    run {
                                        guard let data = imageData else { return "No image supplied." }
                                        if #available(iOS 26, *) {
                                            var hint: VisionDocumentReader.SmudgeHint?
                                            let csv = try await VisionDocumentReader.receiptCSV(from: data, smudgeHint: &hint)
                                            let filename = AppStorageService.shared
                                                .nextExportFilename(prefix: "receipt", ext: "csv")
                                            let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
                                            UIPasteboard.general.url = url
                                            if let s = hint, s.isLikely {
                                                smudgeNote = "Tip: Your camera lens looked smudged (\(Int(s.confidence * 100))%)."
                                            }
                                            return "CSV exported (\(url.lastPathComponent))."
                                        } else {
                                            return "Requires iOS 26."
                                        }
                                    }
                                } label: { Label("Export From Image", systemImage: "scanner") }
                            }

                            Button { runReceipt() } label: { Label("Export Now (no edit)", systemImage: "bolt.fill") }
                        }
                }

                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(ok ? .green : .red)
                        .padding(.top, 6)
                        .accessibilityLabel("Status")
                }

                if let smudgeNote {
                    Text(smudgeNote).font(.footnote).foregroundStyle(.secondary)
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
            // Editor sheets
            .sheet(isPresented: $showEvent) {
                EventEditorView(
                    sourceText: inputText,
                    onCancel: { showEvent = false },
                    onSaved: { m in
                        showEvent = false; status = m; ok = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .sheet(isPresented: $showReminder) {
                ReminderEditorView(
                    sourceText: inputText,
                    onCancel: { showReminder = false },
                    onSaved: { m in
                        showReminder = false; status = m; ok = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .sheet(isPresented: $showContact) {
                ContactEditorView(
                    sourceText: inputText,
                    sourceImageData: imageData,
                    onCancel: { showContact = false },
                    onSaved: { m in
                        showContact = false; status = m; ok = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .sheet(isPresented: $showCSV) {
                ReceiptCSVPreviewView(
                    sourceText: inputText,
                    sourceImageData: imageData,
                    onCancel: { showCSV = false },
                    onExported: { m in
                        showCSV = false; status = m; ok = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                )
            }
            .overlay(alignment: .center) {
                if isWorking { ProgressView().scaleEffect(1.15) }
            }
        }
    }

    // MARK: Helpers

    private var displaySelection: String { selection.isEmpty ? "No selection found." : selection }

    private var inputText: String {
        var t = selection
        if !pageTitle.isEmpty { t = t.isEmpty ? pageTitle : t }
        if !pageURL.isEmpty { t += "\n\(pageURL)" }
        return t
    }

    private func run(_ op: @escaping () async throws -> String) {
        isWorking = true; status = nil; ok = false
        Task { @MainActor in
            do { let message = try await op(); status = message; ok = true }
            catch { status = error.localizedDescription; ok = false }
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

    private func openAutoEditor() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status = "Provide text first."; ok = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        let decision = ActionRouter.route(text: text)
        switch decision.kind {
        case .receipt:  showCSV = true
        case .contact:  showContact = true
        case .event:    showEvent = true
        case .reminder: showReminder = true
        }
    }

    @ViewBuilder
    private func rowLabel(_ title: String, _ systemImage: String) -> some View {
        HStack(spacing: 10) { Image(systemName: systemImage); Text(title); Spacer() }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Direct-run helpers (unchanged)
private func createReminder(text: String) async throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Provide text first." }
    let title = trimmed.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Todo"
    let due = DateParser.firstDateRange(in: trimmed)?.start
    let id = try await RemindersService.shared.addReminder(title: title, due: due, notes: trimmed)
    return "Reminder created (\(id))."
}

private func addToCalendar(text: String) async throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Provide text first." }
    guard let range = DateParser.firstDateRange(in: trimmed) else { return "No date found." }
    let title = trimmed.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Event"
    let id = try await CalendarService.shared.addEvent(title: title, start: range.start, end: range.end, notes: trimmed)
    return "Event created (\(id))."
}

@MainActor
private func exportReceiptCSV(text: String) async throws -> (String, URL) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ("Provide text first.", AppStorageService.shared.containerURL())
    }
    let csv = CSVExporter.makeReceiptCSV(from: trimmed)
    let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
    let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
    return ("CSV exported.", url)
}

private func extractContact(text: String) async throws -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "Provide text first." }
    let detected = ContactParser.detect(in: trimmed)
    let has = (detected.givenName?.isEmpty == false)
        || !detected.emails.isEmpty
        || !detected.phones.isEmpty
        || (detected.postalAddress != nil)
    guard has else { return "No contact details found." }
    let id = try await ContactsService.save(contact: detected)
    return "Contact saved (\(id))."
}
