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

        let action  = (body["action"] as? String) ?? ""
        let payload = (body["payload"] as? [String: Any]) ?? [:]
        let selection = (payload["selection"] as? String) ?? ""
        let title     = (payload["title"] as? String) ?? ""
        let urlString = (payload["url"] as? String) ?? ""
        let text = composeInput(selection: selection, title: title, url: urlString)

        Task { @MainActor in
            do {
                let result: [String: Any]
                switch action {
                case "getProStatus":
                    result = ["ok": true, "pro": Self.isProActive()]
                case "autoDetect":
                    result = try await handleAutoDetect(text: text, title: title, selection: selection)
                case "createReminder":
                    result = try await handleCreateReminder(text: text, title: title, selection: selection)
                case "addEvent":
                    result = try await handleAddEvent(text: text, title: title, selection: selection)
                case "extractContact":
                    result = try await handleExtractContact(text: text)
                case "receiptCSV":
                    // Gate CSV exports here as well (3/day for free)
                    let gate = QuotaManager.consume(feature: .receiptCSVExport, isPro: Self.isProActive())
                    guard gate.allowed else {
                        result = ["ok": false, "message": gate.message]
                        reply(context, result)
                        return
                    }
                    result = try handleReceiptCSV(text: text)
                default:
                    result = ["ok": false, "message": "Unknown action."]
                }
                reply(context, result)
            } catch {
                var payload: [String: Any] = ["ok": false, "message": error.localizedDescription]
                if let hint = Self.permissionHint(for: error.localizedDescription, action: action) {
                    payload["hint"] = hint
                }
                reply(context, payload)
            }
        }
    }

    // MARK: - Reply helper

    private func reply(_ context: NSExtensionContext, _ payload: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    // MARK: - Compose helper

    private func composeInput(selection: String, title: String, url: String) -> String {
        var t = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty, !title.isEmpty { t = title }
        if !url.isEmpty { t += (t.isEmpty ? "" : "\n") + url }
        return t
    }

    private static func permissionHint(for message: String, action: String) -> String? {
        let lower = message.lowercased()
        if lower.contains("calendar access") || (action == "addEvent" && lower.contains("not granted")) {
            return "Open Settings → Privacy & Security → Calendars and allow access for Screen Actions."
        }
        if lower.contains("reminders access") || (action == "createReminder" && lower.contains("not granted")) {
            return "Open Settings → Privacy & Security → Reminders and allow access for Screen Actions."
        }
        if lower.contains("contacts") && lower.contains("not granted") {
            return "Open Settings → Privacy & Security → Contacts and allow access for Screen Actions."
        }
        return nil
    }

    // MARK: - Pro status bridge (App Group)

    private static let groupID = AppStorageService.appGroupID
    private static func isProActive() -> Bool {
        let d = UserDefaults(suiteName: groupID) ?? .standard
        return d.bool(forKey: "iap.pro.active")
    }

    // MARK: - Actions (reuse Core services)

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
            let id = try await CalendarService.shared.addEvent(title: preferredTitle, start: range.start, end: range.end, notes: text)
            return ["ok": true, "message": "Auto → Event created (\(id))."]

        case .reminder:
            return try await handleCreateReminder(text: text, title: title, selection: selection)
        }
    }

    private func handleCreateReminder(text: String, title: String, selection: String) async throws -> [String: Any] {
        let preferredTitle = selection.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? (title.isEmpty ? "Reminder" : title)
        let due = DateParser.firstDateRange(in: text)?.start
        let id = try await RemindersService.shared.addReminder(title: preferredTitle, due: due, notes: text)
        return ["ok": true, "message": "Reminder created (\(id))."]
    }

    private func handleAddEvent(text: String, title: String, selection: String) async throws -> [String: Any] {
        guard let range = DateParser.firstDateRange(in: text) else {
            throw NSError(domain: "ScreenActions", code: 2, userInfo: [NSLocalizedDescriptionKey: "No date found."])
        }
        let preferredTitle = selection.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? (title.isEmpty ? "Event" : title)
        let id = try await CalendarService.shared.addEvent(title: preferredTitle, start: range.start, end: range.end, notes: text)
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
