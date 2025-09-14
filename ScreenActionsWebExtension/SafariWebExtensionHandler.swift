//
//  SafariWebExtensionHandler.swift
//  ScreenActionsWebExtension
//
//  Created by . . on 9/13/25.
//

import Foundation
import SafariServices
import Contacts
import EventKit

@MainActor
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let userInfo = item.userInfo,
            let body = userInfo[SFExtensionMessageKey] as? [String: Any]
        else {
            reply(context, ["ok": false, "message": "Bad message."])
            return
        }

        let action = (body["action"] as? String) ?? ""
        let payload = (body["payload"] as? [String: Any]) ?? [:]
        let selection = (payload["selection"] as? String) ?? ""
        let title = (payload["title"] as? String) ?? ""
        let urlString = (payload["url"] as? String) ?? ""
        let text = composeInput(selection: selection, title: title, url: urlString)

        Task { @MainActor in
            do {
                let result: [String: Any]
                switch action {
                case "autoDetect":
                    result = try await handleAutoDetect(text: text, title: title, selection: selection)
                case "createReminder":
                    result = try await handleCreateReminder(text: text, title: title, selection: selection)
                case "addEvent":
                    result = try await handleAddEvent(text: text, title: title, selection: selection)
                case "extractContact":
                    result = try await handleExtractContact(text: text)
                case "receiptCSV":
                    result = try handleReceiptCSV(text: text)
                default:
                    result = ["ok": false, "message": "Unknown action."]
                }
                reply(context, result)
            } catch {
                reply(context, ["ok": false, "message": error.localizedDescription])
            }
        }
    }

    // MARK: - Helpers
    private func reply(_ context: NSExtensionContext, _ payload: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func composeInput(selection: String, title: String, url: String) -> String {
        var t = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty, !title.isEmpty { t = title }
        if !url.isEmpty { t += (t.isEmpty ? "" : "\n") + url }
        return t
    }

    // MARK: - Actions (reuse your Core services)
    private func handleAutoDetect(text: String, title: String, selection: String) async throws -> [String: Any] {
        let decision = ActionRouter.route(text: text)
        switch decision.kind {
        case .receipt:
            let csv = CSVExporter.makeReceiptCSV(from: text)
            let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
            let fileURL = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
            return ["ok": true, "message": "Auto → CSV exported.", "fileURL": fileURL.absoluteString]
        case .contact:
            let detected = ContactParser.detect(in: text)
            let id = try await ContactsService.save(contact: detected)
            return ["ok": true, "message": "Auto → Contact saved (\(id))."]
        case .event:
            guard let range = decision.dateRange ?? DateParser.firstDateRange(in: text) else {
                return try await handleCreateReminder(text: text, title: title, selection: selection)
            }
            let preferredTitle = selection.components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? (title.isEmpty ? "Event" : title)
            let id = try await CalendarService.shared.addEvent(
                title: preferredTitle,
                start: range.start,
                end: range.end,
                notes: text
            )
            return ["ok": true, "message": "Auto → Event created (\(id))."]
        case .reminder:
            return try await handleCreateReminder(text: text, title: title, selection: selection)
        }
    }

    private func handleCreateReminder(text: String, title: String, selection: String) async throws -> [String: Any] {
        let preferredTitle = selection.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? (title.isEmpty ? "Reminder" : title)
        let due = DateParser.firstDateRange(in: text)?.start
        let id = try await RemindersService.shared.addReminder(
            title: preferredTitle,
            due: due,
            notes: text
        )
        return ["ok": true, "message": "Reminder created (\(id))."]
    }

    private func handleAddEvent(text: String, title: String, selection: String) async throws -> [String: Any] {
        guard let range = DateParser.firstDateRange(in: text) else {
            throw NSError(domain: "ScreenActions", code: 2, userInfo: [NSLocalizedDescriptionKey: "No date found."])
        }
        let preferredTitle = selection.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? (title.isEmpty ? "Event" : title)
        let id = try await CalendarService.shared.addEvent(
            title: preferredTitle,
            start: range.start,
            end: range.end,
            notes: text
        )
        return ["ok": true, "message": "Event created (\(id))."]
    }

    private func handleExtractContact(text: String) async throws -> [String: Any] {
        let detected = ContactParser.detect(in: text)
        let id = try await ContactsService.save(contact: detected)
        return ["ok": true, "message": "Contact saved (\(id))."]
    }

    private func handleReceiptCSV(text: String) throws -> [String: Any] {
        let csv = CSVExporter.makeReceiptCSV(from: text)
        let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
        let fileURL = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
        return ["ok": true, "message": "CSV exported.", "fileURL": fileURL.absoluteString]
    }
}
