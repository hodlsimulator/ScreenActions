//
//  CalendarService.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import Foundation
import EventKit

enum CalendarServiceError: Error, LocalizedError {
    case accessDenied
    case noWritableCalendar
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was not granted."
        case .noWritableCalendar:
            return "No writable calendar is available."
        case .saveFailed(let message):
            return "Failed to save event: \(message)"
        }
    }
}

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()

    /// Adds an event and returns its identifier (iOS 26-only target).
    func addEvent(title: String, start: Date, end: Date, notes: String?) async throws -> String {
        try await requestAccess()

        let calendar = try defaultWritableCalendar()
        let event = EKEvent(eventStore: store)
        event.title = title.isEmpty ? "New Event" : title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.calendar = calendar

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

    // MARK: - Permissions (iOS 26 API surface)

    /// Requests full access to calendars (Info.plist must contain NSCalendarsFullAccessUsageDescription).
    func requestAccess() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard granted else {
                    cont.resume(throwing: CalendarServiceError.accessDenied)
                    return
                }
                cont.resume(returning: ())
            }
        }
    }

    // MARK: - Helpers

    private func defaultWritableCalendar() throws -> EKCalendar {
        if let cal = store.defaultCalendarForNewEvents, cal.allowsContentModifications {
            return cal
        }
        if let writable = store.calendars(for: .event).first(where: { $0.allowsContentModifications }) {
            return writable
        }
        throw CalendarServiceError.noWritableCalendar
    }
}
