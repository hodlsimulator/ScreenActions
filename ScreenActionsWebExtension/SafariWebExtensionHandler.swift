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
import MapKit
import CoreLocation

@objc(SafariWebExtensionHandler)
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

        let action  = (body["action"]  as? String) ?? ""
        let payload = (body["payload"] as? [String: Any]) ?? [:]
        let selection = (payload["selection"] as? String) ?? ""
        let title     = (payload["title"]     as? String) ?? ""
        let url       = (payload["url"]       as? String) ?? ""
        let text = composeInput(selection: selection, title: title, url: url)

        Task { @MainActor in
            do {
                let result: [String: Any]
                switch action {
                case "ping":
                    result = ["ok": true, "message": "pong"]

                case "getProStatus":
                    result = ["ok": true, "pro": Self.isProActive()]

                // -------- Editors: prepare (prefill) ----------
                case "prepareEvent":
                    result = Self.prepareEvent(text: text)
                case "prepareReminder":
                    result = Self.prepareReminder(text: text)
                case "prepareContact":
                    result = Self.prepareContact(text: text)
                case "prepareReceiptCSV":
                    result = Self.prepareReceiptCSV(text: text)

                // -------- Editors: save ----------
                case "saveEvent":
                    result = try await Self.saveEvent(payload: payload)
                case "saveReminder":
                    result = try await Self.saveReminder(payload: payload)
                case "saveContact":
                    result = try await Self.saveContact(payload: payload)
                case "exportReceiptCSV":
                    result = try Self.exportReceiptCSV(payload: payload)

                // -------- Legacy one-taps (keep working) ----------
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
                var out: [String: Any] = ["ok": false, "message": error.localizedDescription]
                if let hint = Self.permissionHint(for: error.localizedDescription, action: action) {
                    out["hint"] = hint
                }
                reply(context, out)
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
        if lower.contains("calendar") && lower.contains("not granted") {
            return "Open Settings → Privacy & Security → Calendars and allow access for Screen Actions."
        }
        if lower.contains("reminders") && lower.contains("not granted") {
            return "Open Settings → Privacy & Security → Reminders and allow access for Screen Actions."
        }
        if lower.contains("contacts") && lower.contains("not granted") {
            return "Open Settings → Privacy & Security → Contacts and allow access for Screen Actions."
        }
        if lower.contains("no date found") {
            return "Select text that includes a date/time (e.g. “Fri 3pm”), or use ‘Create Reminder’."
        }
        return nil
    }

    // MARK: - Pro status / quotas
    private static let groupID = AppStorageService.appGroupID
    private static func isProActive() -> Bool {
        let d = UserDefaults(suiteName: groupID) ?? .standard
        return d.bool(forKey: "iap.pro.active")
    }

    // MARK: - Prepare payloads (mirror share-sheet defaults)
    private static func prepareEvent(text: String) -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let range = DateParser.firstDateRange(in: trimmed) ?? DetectedDateRange(
            start: now, end: now.addingTimeInterval(60 * 60)
        )
        let firstLine = trimmed.components(separatedBy: .newlines)
            .first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initialTitle = firstLine.isEmpty ? "Event" : String(firstLine.prefix(64))
        let hint = CalendarService.firstLocationHint(in: trimmed) ?? ""
        let alertDefault = AppStorageService.getDefaultAlertMinutes()

        return ["ok": true, "fields": [
            "title": initialTitle,
            "startISO": iso(range.start),
            "endISO": iso(range.end),
            "notes": trimmed,
            "location": hint,
            "inferTZ": !hint.isEmpty,
            "alertMinutes": alertDefault
        ]]
    }

    private static func prepareReminder(text: String) -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines)
            .first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let r = DateParser.firstDateRange(in: trimmed)
        return ["ok": true, "fields": [
            "title": firstLine.isEmpty ? "Todo" : String(firstLine.prefix(64)),
            "hasDue": (r != nil),
            "dueISO": iso(r?.start ?? Date().addingTimeInterval(60 * 60)),
            "notes": trimmed
        ]]
    }

    private static func prepareContact(text: String) -> [String: Any] {
        let d = ContactParser.detect(in: text)
        var fields: [String: Any] = [
            "givenName": d.givenName ?? "",
            "familyName": d.familyName ?? "",
            "emails": d.emails,
            "phones": d.phones,
            "street": "",
            "city": "",
            "state": "",
            "postalCode": "",
            "country": ""
        ]
        if let a = d.postalAddress {
            fields["street"] = a.street
            fields["city"] = a.city
            fields["state"] = a.state
            fields["postalCode"] = a.postalCode
            fields["country"] = a.country
        }
        return ["ok": true, "fields": fields]
    }

    private static func prepareReceiptCSV(text: String) -> [String: Any] {
        let csv = CSVExporter.makeReceiptCSV(from: text)
        return ["ok": true, "csv": csv]
    }

    // MARK: - Save handlers
    private static func saveEvent(payload: [String: Any]) async throws -> [String: Any] {
        guard let f = payload["fields"] as? [String: Any] else {
            return ["ok": false, "message": "Missing fields."]
        }
        let title = (f["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = parseISO(f["startISO"] as? String),
              let end   = parseISO(f["endISO"] as? String) else {
            return ["ok": false, "message": "Invalid date."]
        }
        let notes = (f["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = (f["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferTZ = (f["inferTZ"] as? Bool) ?? true
        let alertMinutes = (f["alertMinutes"] as? Int).flatMap { $0 > 0 ? $0 : nil }

        let id = try await CalendarService.shared.addEvent(
            title: title.isEmpty ? "Event" : title,
            start: start, end: end,
            notes: (notes?.isEmpty == true) ? nil : notes,
            locationHint: (location?.isEmpty == true) ? nil : location,
            inferTimeZoneFromLocation: inferTZ,
            alertMinutesBefore: alertMinutes,
            travelTimeAlarm: false,
            transport: .automobile,
            geofenceProximity: nil,
            geofenceRadius: 150
        )

        if let m = f["alertMinutes"] as? Int { AppStorageService.setDefaultAlertMinutes(m) }
        return ["ok": true, "message": "Event created (\(id)).", "id": id]
    }

    private static func saveReminder(payload: [String: Any]) async throws -> [String: Any] {
        guard let f = payload["fields"] as? [String: Any] else {
            return ["ok": false, "message": "Missing fields."]
        }
        let title = (f["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDue = (f["hasDue"] as? Bool) ?? false
        let due = hasDue ? parseISO(f["dueISO"] as? String) : nil
        let notes = (f["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let id = try await RemindersService.shared.addReminder(
            title: title.isEmpty ? "Todo" : title,
            due: due,
            notes: (notes?.isEmpty == true) ? nil : notes
        )
        return ["ok": true, "message": "Reminder created (\(id)).", "id": id]
    }

    private static func saveContact(payload: [String: Any]) async throws -> [String: Any] {
        guard let f = payload["fields"] as? [String: Any] else {
            return ["ok": false, "message": "Missing fields."]
        }
        var dc = DetectedContact()
        let gn = (f["givenName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let fn = (f["familyName"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        if !gn.isEmpty { dc.givenName = gn }
        if !fn.isEmpty { dc.familyName = fn }
        dc.emails = (f["emails"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        dc.phones = (f["phones"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let street = (f["street"] as? String ?? "")
        let city = (f["city"] as? String ?? "")
        let state = (f["state"] as? String ?? "")
        let postal = (f["postalCode"] as? String ?? "")
        let country = (f["country"] as? String ?? "")
        if !(street.isEmpty && city.isEmpty && state.isEmpty && postal.isEmpty && country.isEmpty) {
            let a = CNMutablePostalAddress()
            a.street = street; a.city = city; a.state = state; a.postalCode = postal; a.country = country
            dc.postalAddress = a.copy() as? CNPostalAddress
        }

        let hasAny = (dc.givenName?.isEmpty == false) || (dc.familyName?.isEmpty == false) || !dc.emails.isEmpty || !dc.phones.isEmpty || (dc.postalAddress != nil)
        guard hasAny else { return ["ok": false, "message": "Enter at least one contact field."] }

        let id = try await ContactsService.save(contact: dc)
        return ["ok": true, "message": "Contact saved (\(id)).", "id": id]
    }

    private static func exportReceiptCSV(payload: [String: Any]) throws -> [String: Any] {
        let csv = (payload["csv"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !csv.isEmpty else { return ["ok": false, "message": "Nothing to export."] }
        let gate = QuotaManager.consume(feature: .receiptCSVExport, isPro: Self.isProActive())
        guard gate.allowed else { return ["ok": false, "message": gate.message] }

        let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
        let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
        return ["ok": true, "message": "CSV exported.", "fileURL": url.absoluteString]
    }

    // MARK: - Legacy direct actions
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

    // MARK: - ISO helpers
    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static func iso(_ d: Date) -> String { isoFmt.string(from: d) }
    private static func parseISO(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        return isoFmt.date(from: s) ?? {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: s)
        }()
    }
}
