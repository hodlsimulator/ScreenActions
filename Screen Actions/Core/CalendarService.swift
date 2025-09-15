//
//  CalendarService.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//  Updated: 15/09/2025 – iOS 26 clean: no deprecated MapKit/CLGeocoder, location string + alerts
//

import Foundation
import EventKit

enum CalendarServiceError: Error, LocalizedError {
    case accessDenied
    case noWritableCalendar
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:          return "Calendar access was not granted."
        case .noWritableCalendar:    return "No writable calendar is available."
        case .saveFailed(let msg):   return "Failed to save event: \(msg)"
        }
    }
}

@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()

    /// Adds an event and returns its identifier.
    /// - Parameters:
    ///   - title: Title to display (falls back to "New Event" if empty).
    ///   - start: Start date.
    ///   - end: End date.
    ///   - notes: Optional notes to include.
    ///   - locationHint: Optional place/address text. If nil, we’ll try to extract from `notes/title`.
    ///   - inferTimeZoneFromLocation: Reserved for future MapKit reverse-geocoding (unused on iOS-26 clean path).
    ///   - alertMinutesBefore: Optional alert (e.g. 5, 10, 15, 30). Omit or 0 for none.
    func addEvent(
        title: String,
        start: Date,
        end: Date,
        notes: String?,
        locationHint: String? = nil,
        inferTimeZoneFromLocation _: Bool = true,
        alertMinutesBefore: Int? = nil
    ) async throws -> String {
        try await requestAccess()
        let calendar = try defaultWritableCalendar()

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Event" : title
        event.startDate = start
        event.endDate = end
        event.notes = notes

        // Best-effort location (text only — no deprecated MapKit calls).
        let combinedText = [title, notes ?? ""].joined(separator: "\n")
        if let query = (locationHint?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap({ $0.isEmpty ? nil : $0 })
            ?? Self.firstLocationHint(in: combinedText)
        {
            event.location = query
        }

        // Optional alert.
        if let m = alertMinutesBefore, m > 0 {
            let alarm = EKAlarm(relativeOffset: TimeInterval(-m * 60))
            event.addAlarm(alarm)
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalendarServiceError.saveFailed(error.localizedDescription)
        }

        guard let id = event.eventIdentifier, !id.isEmpty else {
            throw CalendarServiceError.saveFailed("Event saved but identifier is unavailable.")
        }
        return id
    }

    /// Legacy overload kept for existing code paths.
    func addEvent(title: String, start: Date, end: Date, notes: String?) async throws -> String {
        try await addEvent(
            title: title,
            start: start,
            end: end,
            notes: notes,
            locationHint: nil,
            inferTimeZoneFromLocation: true,
            alertMinutesBefore: nil
        )
    }
}

// MARK: - Heuristics (location hint)

extension CalendarService {
    /// Naïve extractor that looks for an address or “at/ @ /in …” phrases.
    static func firstLocationHint(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1) Address via NSDataDetector (postal addresses).
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = detector.firstMatch(in: trimmed, options: [], range: range),
               let r = Range(match.range, in: trimmed) {
                let candidate = String(trimmed[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return candidate }
            }
        }

        // 2) Look for “ at … / @ … / in …” up to end-of-line or punctuation.
        let patterns = [
            #"(?:^|\s)(?:at|@|in)\s+([^\n,.;:|]{3,80})"# // at Foo Bar London
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let r = NSRange(trimmed.startIndex..., in: trimmed)
                if let m = re.firstMatch(in: trimmed, options: [], range: r), m.numberOfRanges >= 2,
                   let range1 = Range(m.range(at: 1), in: trimmed) {
                    let candidate = String(trimmed[range1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty { return candidate }
                }
            }
        }

        return nil
    }
}

// MARK: - Permissions

extension CalendarService {
    /// Requests full access to calendars (Info.plist must contain NSCalendarsFullAccessUsageDescription).
    func requestAccess() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestFullAccessToEvents { granted, error in
                if let error { cont.resume(throwing: error); return }
                guard granted else { cont.resume(throwing: CalendarServiceError.accessDenied); return }
                cont.resume(returning: ())
            }
        }
    }

    private func defaultWritableCalendar() throws -> EKCalendar {
        if let cal = store.defaultCalendarForNewEvents, cal.allowsContentModifications { return cal }
        if let writable = store.calendars(for: .event).first(where: { $0.allowsContentModifications }) { return writable }
        throw CalendarServiceError.noWritableCalendar
    }
}
