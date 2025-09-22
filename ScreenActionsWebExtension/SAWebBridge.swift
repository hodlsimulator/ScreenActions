//
//  SAWebBridge.swift
//  Screen Actions
//
//  Created by . . on 9/22/25.
//

import Foundation
import Contacts
import EventKit

@objc(SAWebBridge)
@MainActor
final class SAWebBridge: NSObject {

    @objc class func handle(_ action: String,
                            payload: [String: Any],
                            completion: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            do {
                let result = try await route(action: action, payload: payload)
                completion(result)
            } catch {
                var out: [String: Any] = ["ok": false, "message": error.localizedDescription]
                if let hint = permissionHint(for: error.localizedDescription, action: action) {
                    out["hint"] = hint
                }
                completion(out)
            }
        }
    }

    // MARK: - Router

    private class func route(action: String, payload: [String: Any]) async throws -> [String: Any] {
        let selection = (payload["selection"] as? String) ?? ""
        let title     = (payload["title"] as? String) ?? ""
        let url       = (payload["url"] as? String) ?? ""

        var text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, !title.isEmpty { text = title }
        if !url.isEmpty { text += (text.isEmpty ? "" : "\n") + url }

        switch action {
        case "getProStatus":
            return ["ok": true, "pro": isProActive()]

        case "autoDetect":
            return try await handleAutoDetect(text: text, title: title, selection: selection)

        case "createReminder":
            return try await handleCreateReminder(text: text, title: title, selection: selection)

        case "addEvent":
            return try await handleAddEvent(text: text, title: title, selection: selection)

        case "extractContact":
            return try await handleExtractContact(text: text)

        case "receiptCSV":
            let gate = QuotaManager.consume(feature: .receiptCSVExport, isPro: isProActive())
            guard gate.allowed else { return ["ok": false, "message": gate.message] }
            return try handleReceiptCSV(text: text)

        default:
            return ["ok": false, "message": "Unknown action."]
        }
    }

    // MARK: - Actions (reuse your existing services)

    private class func handleAutoDetect(text: String, title: String, selection: String) async throws -> [String: Any] {
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

    private class func handleCreateReminder(text: String, title: String, selection: String) async throws -> [String: Any] {
        let preferredTitle = selection.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? (title.isEmpty ? "Reminder" : title)
        let due = DateParser.firstDateRange(in: text)?.start
        let id = try await RemindersService.shared.addReminder(title: preferredTitle, due: due, notes: text)
        return ["ok": true, "message": "Reminder created (\(id))."]
    }

    private class func handleAddEvent(text: String, title: String, selection: String) async throws -> [String: Any] {
        guard let range = DateParser.firstDateRange(in: text) else {
            throw NSError(domain: "ScreenActions", code: 2, userInfo: [NSLocalizedDescriptionKey: "No date found."])
        }
        let preferredTitle = selection.components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? (title.isEmpty ? "Event" : title)
        let id = try await CalendarService.shared.addEvent(title: preferredTitle, start: range.start, end: range.end, notes: text)
        return ["ok": true, "message": "Event created (\(id))."]
    }

    private class func handleExtractContact(text: String) async throws -> [String: Any] {
        let detected = ContactParser.detect(in: text)
        let id = try await ContactsService.save(contact: detected)
        return ["ok": true, "message": "Contact saved (\(id))."]
    }

    private class func handleReceiptCSV(text: String) throws -> [String: Any] {
        let csv = CSVExporter.makeReceiptCSV(from: text)
        let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
        let fileURL = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
        return ["ok": true, "message": "CSV exported.", "fileURL": fileURL.absoluteString]
    }

    // MARK: - Hints & helpers

    private class func permissionHint(for message: String, action: String) -> String? {
        let lower = message.lowercased()
        if lower.contains("calendar access") || (action == "addEvent" && lower.contains("not granted")) {
            return "Open Settings → Privacy & Security → Calendars and allow access for Screen Actions. If you haven’t opened the app yet, run it once so iPadOS can show the permission dialog."
        }
        if lower.contains("reminders access") || (action == "createReminder" && lower.contains("not granted")) {
            return "Open Settings → Privacy & Security → Reminders and allow access for Screen Actions. If you haven’t opened the app yet, run it once so iPadOS can show the permission dialog."
        }
        if lower.contains("contacts") && lower.contains("not granted") {
            return "Open Settings → Privacy & Security → Contacts and allow access for Screen Actions."
        }
        if lower.contains("no date found") {
            return "Select text that includes a date/time (e.g. “Fri 3pm”), or use ‘Create Reminder’ instead."
        }
        return nil
    }

    private static let groupID = AppStorageService.appGroupID
    private class func isProActive() -> Bool {
        let d = UserDefaults(suiteName: groupID) ?? .standard
        return d.bool(forKey: "iap.pro.active")
    }
}
