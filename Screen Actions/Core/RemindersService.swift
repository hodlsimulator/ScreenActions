//
//  RemindersService.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import Foundation
import EventKit

enum RemindersService {
    static func addReminder(title: String, due: Date?, notes: String?) async throws -> String {
        let store = EKEventStore()
        try await requestRemindersAccess(store: store)

        let reminder = EKReminder(eventStore: store)
        reminder.title = title.isEmpty ? "New Reminder" : title
        reminder.notes = notes

        if let due {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.dueDateComponents = comps
        }

        reminder.calendar = store.defaultCalendarForNewReminders()
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    private static func requestRemindersAccess(store: EKEventStore) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestFullAccessToReminders { granted, err in
                if let err { cont.resume(throwing: err); return }
                guard granted else {
                    cont.resume(throwing: NSError(domain: "RemindersService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Reminders access not granted."]))
                    return
                }
                cont.resume(returning: ())
            }
        }
    }
}
