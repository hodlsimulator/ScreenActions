//
//  SAActionPanelView.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//

import SwiftUI
import UIKit
import Foundation

@MainActor
public struct SAActionPanelView: View {
    public let selection: String
    public let pageTitle: String
    public let pageURL: String
    public let imageData: Data?
    public let onDone: (String) -> Void

    @State private var isWorking = false
    @State private var status: String?
    @State private var ok = false
    @State private var smudgeNote: String?

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
                    Button { openAuto() } label: { rowLabel("Auto Detect", "wand.and.stars") }
                        .buttonStyle(.borderedProminent)

                    Button { run { try await createReminder(text: inputText) } }
                        label: { rowLabel("Create Reminder", "checkmark.circle") }
                        .buttonStyle(.bordered)

                    Button { run { try await addToCalendar(text: inputText) } }
                        label: { rowLabel("Add Calendar Event", "calendar.badge.plus") }
                        .buttonStyle(.bordered)

                    Button { run { try await extractContact(text: inputText) } }
                        label: { rowLabel("Extract Contact", "person.crop.circle.badge.plus") }
                        .buttonStyle(.bordered)
                        .contextMenu {
                            if imageData != nil {
                                Button {
                                    run { try await saveContactsFromImage() }
                                } label: { Label("Save From Image (batch)", systemImage: "person.crop.rectangle.stack") }
                            }
                        }

                    Button {
                        run { try await exportReceiptCSV(text: inputText) }
                    } label: { rowLabel("Receipt → CSV", "doc.badge.plus") }
                    .buttonStyle(.bordered)
                    .contextMenu {
                        if imageData != nil {
                            Button {
                                run { try await exportReceiptCSVFromImage() }
                            } label: { Label("Export From Image", systemImage: "scanner") }
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
                if let smudgeNote {
                    Text(smudgeNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Screen Actions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ok ? "Done" : "Cancel") { onDone(status ?? (ok ? "Done" : "Cancelled")) }
                }
            }
            .overlay(alignment: .center) { if isWorking { ProgressView().scaleEffect(1.15) } }
        }
    }

    // MARK: - Helpers

    private var displaySelection: String { selection.isEmpty ? "No selection found." : selection }

    private var inputText: String {
        var t = selection
        if !pageTitle.isEmpty, t.isEmpty { t = pageTitle }
        if !pageURL.isEmpty { t += (t.isEmpty ? "" : "\n") + pageURL }
        return t
    }

    private var isProActive: Bool {
        let d = UserDefaults(suiteName: AppStorageService.appGroupID) ?? .standard
        return d.bool(forKey: "iap.pro.active")
    }

    private func run(_ op: @escaping () async throws -> String) {
        isWorking = true; status = nil; ok = false
        Task { @MainActor in
            do {
                let message = try await op()
                status = message; ok = true
            } catch {
                status = error.localizedDescription; ok = false
            }
            isWorking = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func openAuto() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            status = "Provide text first."; ok = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        let decision = ActionRouter.route(text: text)
        switch decision.kind {
        case .receipt: run { try await exportReceiptCSV(text: text) }
        case .contact: run { try await extractContact(text: text) }
        case .event:   run { try await addToCalendar(text: text) }
        case .reminder:run { try await createReminder(text: text) }
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

    // MARK: - Ops (with quotas where applicable)

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

    private func exportReceiptCSV(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Provide text first." }
        let pro = isProActive
        let gate = QuotaManager.consume(feature: .receiptCSVExport, isPro: pro)
        guard gate.allowed else { throw NSError(domain: "Quota", code: 1, userInfo: [NSLocalizedDescriptionKey: gate.message]) }

        let csv = CSVExporter.makeReceiptCSV(from: trimmed)
        let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
        let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
        UIPasteboard.general.url = url
        return "CSV exported (\(url.lastPathComponent))."
    }

    private func exportReceiptCSVFromImage() async throws -> String {
        guard let data = imageData else { return "No image supplied." }
        let pro = isProActive
        let gate = QuotaManager.consume(feature: .receiptCSVExport, isPro: pro)
        guard gate.allowed else { throw NSError(domain: "Quota", code: 1, userInfo: [NSLocalizedDescriptionKey: gate.message]) }

        if #available(iOS 26, *) {
            var hint: VisionDocumentReader.SmudgeHint?
            let csv = try await VisionDocumentReader.receiptCSV(from: data, smudgeHint: &hint)
            let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
            let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
            UIPasteboard.general.url = url
            smudgeNote = hint?.isLikely == true ? "Tip: Your camera lens looked smudged (\(Int((hint?.confidence ?? 0) * 100))%)." : nil
            return "CSV exported (\(url.lastPathComponent))."
        } else {
            return "Requires iOS 26."
        }
    }

    private func extractContact(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Provide text first." }
        let detected = ContactParser.detect(in: trimmed)
        let has = (detected.givenName?.isEmpty == false) || !detected.emails.isEmpty || !detected.phones.isEmpty || (detected.postalAddress != nil)
        guard has else { return "No contact details found." }
        let id = try await ContactsService.save(contact: detected)
        return "Contact saved (\(id))."
    }

    private func saveContactsFromImage() async throws -> String {
        guard let data = imageData else { return "No image supplied." }
        if #available(iOS 26, *) {
            var hint: VisionDocumentReader.SmudgeHint?
            let list = try await VisionDocumentReader.contacts(from: data, smudgeHint: &hint)

            let pro = isProActive
            var saved = 0
            for c in list {
                let ok = (c.givenName?.isEmpty == false) || (c.familyName?.isEmpty == false) || !c.emails.isEmpty || !c.phones.isEmpty || (c.postalAddress != nil)
                guard ok else { continue }
                let gate = QuotaManager.consume(feature: .createContactFromImage, isPro: pro)
                guard gate.allowed else {
                    smudgeNote = hint?.isLikely == true ? "Tip: Your camera lens looked smudged (\(Int((hint?.confidence ?? 0) * 100))%)." : nil
                    throw NSError(domain: "Quota", code: 1, userInfo: [NSLocalizedDescriptionKey: saved > 0 ? "Saved \(saved). \(gate.message)" : gate.message])
                }
                _ = try await ContactsService.save(contact: c)
                saved += 1
            }
            smudgeNote = hint?.isLikely == true ? "Tip: Your camera lens looked smudged (\(Int((hint?.confidence ?? 0) * 100))%)." : nil
            return saved == 1 ? "Saved 1 contact." : "Saved \(saved) contacts."
        } else {
            return "Requires iOS 26."
        }
    }
}
