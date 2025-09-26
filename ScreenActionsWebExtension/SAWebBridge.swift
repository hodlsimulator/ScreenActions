//
//  SAWebBridge.swift
//  Screen Actions
//
//  Created by . . on 9/22/25.
//
// SAWebBridge.swift — popup parsing + saves + haptics
// 

//
// SAWebBridge.swift — popup parsing + saves + haptics
//

import Foundation
import os
import Contacts
import EventKit
import UIKit
@preconcurrency import MapKit

@objc(SAWebBridge)
@MainActor
final class SAWebBridge: NSObject {

    static let log = Logger(subsystem: "com.conornolan.Screen-Actions.WebExtension", category: "native")

    // Entry called by the Obj-C principal → SafariWebExtensionHandler
    @objc
    class func handle(_ action: String, payload: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            do {
                log.info("[SA] handle action=\(action, privacy: .public)")
                let result = try await route(action: action, payload: payload)
                completion(result)
            } catch {
                log.error("[SA] error: \(error.localizedDescription, privacy: .public)")
                completion(["ok": false, "message": error.localizedDescription])
            }
        }
    }

    // MARK: - Router

    private class func route(action: String, payload: [String: Any]) async throws -> [String: Any] {
        // Normalise selection/title/url like the share extension
        let selection = (payload["selection"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title     = (payload["title"]     as? String) ?? ""
        let url       = (payload["url"]       as? String) ?? ""

        var text = selection
        if text.isEmpty, !title.isEmpty { text = title }
        if !url.isEmpty { text += (text.isEmpty ? "" : "\n") + url }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch action {
        // ---- Prefill (parse) ----
        case "prepareEvent":       return try await prepareEvent(from: text)
        case "prepareReminder":    return try await prepareReminder(from: text)
        case "prepareContact":     return try await prepareContact(from: text)
        case "prepareReceiptCSV":  return try await prepareReceiptCSV(from: text)
        case "prepareAutoDetect":  return try await prepareAutoDetect(from: text)

        // ---- Saves / export ----
        case "saveEvent":          return try await saveEvent(fields: (payload["fields"] as? [String: Any]) ?? [:])
        case "saveReminder":       return try await saveReminder(fields: (payload["fields"] as? [String: Any]) ?? [:])
        case "saveContact":        return try await saveContact(fields: (payload["fields"] as? [String: Any]) ?? [:])
        case "exportReceiptCSV":   return try await exportReceiptCSV(csv: (payload["csv"] as? String) ?? "")

        // ---- Haptics ----
        case "hapticSuccess":
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.success)
            return ["ok": true]

        // ---- Ping / legacy handoff (kept for compatibility) ----
        case "ping":              return ["ok": true, "message": "pong"]
        case "addEvent":          Handoff.save(text: text, kind: .event);    return ["ok": true, "openURL": "screenactions://handoff?kind=event"]
        case "createReminder":    Handoff.save(text: text, kind: .reminder); return ["ok": true, "openURL": "screenactions://handoff?kind=reminder"]
        case "extractContact":    Handoff.save(text: text, kind: .contact);  return ["ok": true, "openURL": "screenactions://handoff?kind=contact"]
        case "receiptCSV":        Handoff.save(text: text, kind: .csv);      return ["ok": true, "openURL": "screenactions://handoff?kind=csv"]
        case "autoDetect":
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return ["ok": false, "message": "No text selected."] }
            Handoff.save(text: t, kind: .event) // app will still choose the right editor
            return ["ok": true, "openURL": "screenactions://handoff?kind=auto"]

        default:
            return ["ok": false, "message": "Unknown action."]
        }
    }

    // MARK: - Prefill (parsing)

    private class func prepareEvent(from text: String) async throws -> [String: Any] {
        guard !text.isEmpty else { return ["ok": false, "message": "No text selected."] }

        let defaultStart = Date()
        let defaultEnd   = defaultStart.addingTimeInterval(60 * 60)

        let range  = DateParser.firstDateRange(in: text)
        let start  = range?.start ?? defaultStart
        let end    = range?.end   ?? defaultEnd

        let firstLine = firstNonEmptyLine(text) ?? ""
        let title     = firstLine.isEmpty ? "Event" : trunc(firstLine, max: 64)

        let locHint = CalendarService.firstLocationHint(in: text) ?? ""
        let inferTZ = !locHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let alertDefault = AppStorageService.getDefaultAlertMinutes() // 0 = None

        let fields: [String: Any] = [
            "title": title,
            "startISO": iso(start),
            "endISO":   iso(end),
            "location": locHint,
            "inferTZ":  inferTZ,
            "alertMinutes": alertDefault > 0 ? alertDefault : 0,
            "notes": text
        ]
        return ["ok": true, "fields": fields]
    }

    private class func prepareReminder(from text: String) async throws -> [String: Any] {
        guard !text.isEmpty else { return ["ok": false, "message": "No text selected."] }

        let firstLine = firstNonEmptyLine(text) ?? ""
        let title     = firstLine.isEmpty ? "Todo" : trunc(firstLine, max: 64)
        let due       = DateParser.firstDateRange(in: text)?.start

        let fields: [String: Any] = [
            "title": title,
            "hasDue": due != nil,
            "dueISO": due.map { iso($0) } as Any,
            "notes": text
        ]
        return ["ok": true, "fields": fields]
    }

    private class func prepareContact(from text: String) async throws -> [String: Any] {
        guard !text.isEmpty else { return ["ok": false, "message": "No text selected."] }

        let dc = ContactParser.detect(in: text)
        let addr = dc.postalAddress

        let fields: [String: Any] = [
            "givenName": dc.givenName ?? "",
            "familyName": dc.familyName ?? "",
            "emails": dc.emails,
            "phones": dc.phones,
            "street": addr?.street ?? "",
            "city": addr?.city ?? "",
            "state": addr?.state ?? "",
            "postalCode": addr?.postalCode ?? "",
            "country": addr?.country ?? ""
        ]
        return ["ok": true, "fields": fields]
    }

    private class func prepareReceiptCSV(from text: String) async throws -> [String: Any] {
        guard !text.isEmpty else { return ["ok": false, "message": "No text selected."] }
        let csv = CSVExporter.makeReceiptCSV(from: text)
        return ["ok": true, "csv": csv]
    }

    private class func prepareAutoDetect(from text: String) async throws -> [String: Any] {
        guard !text.isEmpty else { return ["ok": false, "message": "No text selected."] }
        let decision = ActionRouter.route(text: text)
        switch decision.kind {
        case .event:   var out = try await prepareEvent(from: text);    out["route"] = "event";    return out
        case .reminder:var out = try await prepareReminder(from: text); out["route"] = "reminder"; return out
        case .contact: var out = try await prepareContact(from: text);  out["route"] = "contact";  return out
        case .receipt: let csv = CSVExporter.makeReceiptCSV(from: text); return ["ok": true, "route": "csv", "csv": csv]
        }
    }

    // MARK: - Saves / export

    private class func saveEvent(fields: [String: Any]) async throws -> [String: Any] {
        let title = (fields["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Event"

        guard let start = parseISO(fields["startISO"] as? String),
              let end   = parseISO(fields["endISO"]   as? String)
        else {
            return ["ok": false, "message": "Invalid start/end."]
        }

        let notes    = (fields["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let location = (fields["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferTZ  = (fields["inferTZ"] as? Bool) ?? false

        let alertMinutes: Int? = {
            if let n = fields["alertMinutes"] as? Int, n > 0 { return n }
            if let s = fields["alertMinutes"] as? String, let n = Int(s), n > 0 { return n }
            return nil
        }()

        // --- NEW: read geofencing toggles from the web sheet ---
        let geoArrive = (fields["geoArrive"] as? Bool) ?? false
        let geoDepart = (fields["geoDepart"] as? Bool) ?? false
        var geofence: GeofencingManager.GeofenceProximity? = nil
        if geoArrive || geoDepart {
            var p = GeofencingManager.GeofenceProximity([])
            if geoArrive { p.insert(.enter) }
            if geoDepart { p.insert(.exit)  }
            geofence = p
        }
        // -------------------------------------------------------

        let id = try await CalendarService.shared.addEvent(
            title: title,
            start: start,
            end: end,
            notes: notes,
            locationHint: (location?.isEmpty == true) ? nil : location,
            inferTimeZoneFromLocation: inferTZ,
            alertMinutesBefore: alertMinutes,
            travelTimeAlarm: false,
            transport: .automobile,
            geofenceProximity: geofence,
            geofenceRadius: 150
        )

        if let m = alertMinutes, m > 0 {
            AppStorageService.setDefaultAlertMinutes(m)
        }

        return ["ok": true, "message": "Event created (\(id))."]
    }

    private class func saveReminder(fields: [String: Any]) async throws -> [String: Any] {
        let title = (fields["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Todo"
        let hasDue = (fields["hasDue"] as? Bool) ?? false
        let dueISO = fields["dueISO"] as? String
        let due    = hasDue ? parseISO(dueISO) : nil
        let notes  = (fields["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let id = try await RemindersService.shared.addReminder(title: title, due: due, notes: notes)
        return ["ok": true, "message": "Reminder created (\(id))."]
    }

    private class func saveContact(fields: [String: Any]) async throws -> [String: Any] {
        var dc = DetectedContact()

        if let g = (fields["givenName"] as? String)?.trimmingCharacters(in: .whitespaces), !g.isEmpty { dc.givenName = g }
        if let f = (fields["familyName"] as? String)?.trimmingCharacters(in: .whitespaces), !f.isEmpty { dc.familyName = f }

        dc.emails = (fields["emails"] as? [String])?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
        dc.phones = (fields["phones"] as? [String])?.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? []

        let street  = (fields["street"] as? String) ?? ""
        let city    = (fields["city"] as? String) ?? ""
        let state   = (fields["state"] as? String) ?? ""
        let postal  = (fields["postalCode"] as? String) ?? ""
        let country = (fields["country"] as? String) ?? ""

        if !(street.isEmpty && city.isEmpty && state.isEmpty && postal.isEmpty && country.isEmpty) {
            let a = CNMutablePostalAddress()
            a.street = street; a.city = city; a.state = state; a.postalCode = postal; a.country = country
            dc.postalAddress = (a.copy() as? CNPostalAddress)
        }

        let hasAny = (dc.givenName?.isEmpty == false) || (dc.familyName?.isEmpty == false) || !dc.emails.isEmpty || !dc.phones.isEmpty || (dc.postalAddress != nil)
        guard hasAny else { return ["ok": false, "message": "Enter at least one contact field."] }

        let id = try await ContactsService.save(contact: dc)
        return ["ok": true, "message": "Contact saved (\(id))."]
    }

    private class func exportReceiptCSV(csv: String) async throws -> [String: Any] {
        let isPro = (UserDefaults(suiteName: AppStorageService.appGroupID)?.bool(forKey: "iap.pro.active")) ?? false
        let gate = QuotaManager.consume(feature: .receiptCSVExport, isPro: isPro)
        guard gate.allowed else { return ["ok": false, "message": gate.message] }

        let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
        _ = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
        return ["ok": true, "message": "CSV exported."]
    }

    // MARK: - Helpers

    private class func firstNonEmptyLine(_ text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private class func trunc(_ s: String, max: Int) -> String {
        return s.count <= max ? s : String(s.prefix(max))
    }

    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private class func iso(_ d: Date) -> String { isoFmt.string(from: d) }

    private class func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = isoFmt.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
}
