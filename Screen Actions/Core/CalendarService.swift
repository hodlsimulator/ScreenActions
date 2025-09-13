//
//  CalendarService.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import Foundation
import EventKit

enum CalendarService {
    static func addEvent(title: String, start: Date, end: Date, notes: String?) async throws -> String {
        let store = EKEventStore()
        try await requestCalendarAccess(store: store)

        let event = EKEvent(eventStore: store)
        event.title = title.isEmpty ? "New Event" : title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents

        try store.save(event, span: .thisEvent)

        guard let id = event.eventIdentifier else {
            throw NSError(domain: "CalendarService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Event saved but identifier unavailable."])
        }
        return id
    }

    private static func requestCalendarAccess(store: EKEventStore) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestFullAccessToEvents { granted, err in
                if let err { cont.resume(throwing: err); return }
                guard granted else {
                    cont.resume(throwing: NSError(domain: "CalendarService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Calendar access not granted."]))
                    return
                }
                cont.resume(returning: ())
            }
        }
    }
}
