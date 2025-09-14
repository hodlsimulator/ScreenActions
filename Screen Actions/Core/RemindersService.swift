//
//  RemindersService.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import Foundation
import EventKit

enum RemindersServiceError: Error, LocalizedError {
    case accessDenied
    case noWritableList
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Reminders access was not granted."
        case .noWritableList:
            return "No writable reminders list is available."
        case .saveFailed(let message):
            return "Failed to save reminder: \(message)"
        }
    }
}

@MainActor
final class RemindersService {
    static let shared = RemindersService()

    private let store = EKEventStore()

    /// Adds a reminder and returns its identifier. (iOS 26-only target)
    func addReminder(title: String, due: Date?, notes: String?) async throws -> String {
        try await requestAccess()

        let calendar = try defaultWritableRemindersCalendar()

        let reminder = EKReminder(eventStore: store)
        reminder.title = title.isEmpty ? "New Reminder" : title
        reminder.notes = notes
        reminder.calendar = calendar

        if let due {
            // Due date components (no seconds). Reminders uses date components rather than a concrete Date.
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.dueDateComponents = comps

            // Optional: add an alarm at the due time
            let alarm = EKAlarm(absoluteDate: due)
            reminder.addAlarm(alarm)
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw RemindersServiceError.saveFailed(error.localizedDescription)
        }

        let id = reminder.calendarItemIdentifier
        guard !id.isEmpty else {
            throw RemindersServiceError.saveFailed("Reminder saved but identifier is unavailable.")
        }
        return id
    }

    // MARK: - Permissions (iOS 26 API surface)

    /// Requests full access to reminders (Info.plist must contain NSRemindersFullAccessUsageDescription).
    func requestAccess() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestFullAccessToReminders { granted, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard granted else {
                    cont.resume(throwing: RemindersServiceError.accessDenied)
                    return
                }
                cont.resume(returning: ())
            }
        }
    }

    // MARK: - Helpers

    private func defaultWritableRemindersCalendar() throws -> EKCalendar {
        if let cal = store.defaultCalendarForNewReminders(), cal.allowsContentModifications {
            return cal
        }
        if let writable = store.calendars(for: .reminder).first(where: { $0.allowsContentModifications }) {
            return writable
        }
        throw RemindersServiceError.noWritableList
    }
}
