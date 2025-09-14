//
//  AutoDetectIntent.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import AppIntents
import Foundation

struct AutoDetectIntent: AppIntent {
    static var title: LocalizedStringResource { "Auto Detect" }
    static var description: IntentDescription {
        IntentDescription("Looks at your text or image and picks the best action: reminder, calendar event, contact, or receipt → CSV.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text", description: "Paste text to analyse")
    var text: String?

    @Parameter(title: "Image", description: "Image or screenshot to OCR")
    var image: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let sourceText: String
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceText = t
        } else {
            sourceText = try TextExtractor.from(imageFile: image)
        }

        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw $text.needsValueError("Provide text or an image with text.")
        }

        let message = try await AutoDetectIntent.runStandalone(text: sourceText)
        return .result(value: message, dialog: "Done.")
    }
}

extension AutoDetectIntent {
    /// Headless helper for in-app, share extension, and web extension glue.
    @MainActor
    static func runStandalone(text raw: String) async throws -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Provide text first." }

        let decision = ActionRouter.route(text: text)

        switch decision.kind {
        case .receipt:
            let csv = CSVExporter.makeReceiptCSV(from: text)
            let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
            let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
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
                let title = text.components(separatedBy: .newlines).first?
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
            let title = text.components(separatedBy: .newlines).first?
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
