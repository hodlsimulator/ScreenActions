//
//  RemindersService.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  Updated: auto-create/select a writable Reminders list; fixed entityType check.
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

    private static let preferredListKey = "sa.reminders.preferredCalendarID"
    private let fallbackListName = "Screen Actions"

    /// Adds a reminder and returns its identifier.
    func addReminder(title: String, due: Date?, notes: String?) async throws -> String {
        try await requestAccess()

        let calendar = try ensureWritableRemindersCalendar()

        let reminder = EKReminder(eventStore: store)
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Reminder" : title
        reminder.notes = (notes?.isEmpty == false) ? notes : nil
        reminder.calendar = calendar

        if let due {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.dueDateComponents = comps
            reminder.addAlarm(EKAlarm(absoluteDate: due))
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
}

// MARK: - Permissions

extension RemindersService {
    func requestAccess() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestFullAccessToReminders { granted, error in
                if let error { cont.resume(throwing: error); return }
                guard granted else {
                    cont.resume(throwing: RemindersServiceError.accessDenied)
                    return
                }
                cont.resume(returning: ())
            }
        }
    }
}

// MARK: - Calendar selection / creation

extension RemindersService {

    /// Returns a writable reminders calendar, creating “Screen Actions” if needed.
    private func ensureWritableRemindersCalendar() throws -> EKCalendar {
        let defaults = AppStorageService.shared.defaults

        // Build a fast lookup of all Reminders calendars by id.
        let reminderCalendars = store.calendars(for: .reminder)
        let reminderIDs = Set(reminderCalendars.map(\.calendarIdentifier))

        // Helper to validate a calendar really is a writable Reminders calendar.
        func isWritableRemindersCalendar(_ cal: EKCalendar) -> Bool {
            cal.allowsContentModifications && reminderIDs.contains(cal.calendarIdentifier)
        }

        // 0) Previously saved preferred list
        if let savedID = defaults.string(forKey: Self.preferredListKey),
           let saved = store.calendar(withIdentifier: savedID),
           isWritableRemindersCalendar(saved) {
            return saved
        }

        // 1) Default list, if writable
        if let cal = store.defaultCalendarForNewReminders(), isWritableRemindersCalendar(cal) {
            persistPreferred(cal, defaults: defaults)
            return cal
        }

        // 2) Our own list by name, if present and writable
        if let ours = reminderCalendars.first(where: { $0.title == fallbackListName && $0.allowsContentModifications }) {
            persistPreferred(ours, defaults: defaults)
            return ours
        }

        // 3) Any writable Reminders list
        if let anyWritable = reminderCalendars.first(where: { $0.allowsContentModifications }) {
            persistPreferred(anyWritable, defaults: defaults)
            return anyWritable
        }

        // 4) None exist → try to create one in the best available source
        if let created = try? createListNamed(fallbackListName) {
            persistPreferred(created, defaults: defaults)
            return created
        }

        // 5) Still no luck
        throw RemindersServiceError.noWritableList
    }

    private func persistPreferred(_ cal: EKCalendar, defaults: UserDefaults = AppStorageService.shared.defaults) {
        defaults.set(cal.calendarIdentifier, forKey: Self.preferredListKey)
    }

    /// Attempts to create a list in a suitable source (prefers iCloud CalDAV, then Local, then Exchange).
    private func createListNamed(_ name: String) throws -> EKCalendar {
        // Prefer iCloud CalDAV → Local → Exchange → others.
        let sources = store.sources.sorted { lhs, rhs in
            rank(lhs) < rank(rhs)
        }

        for source in sources {
            let cal = EKCalendar(for: .reminder, eventStore: store)
            cal.title = name
            cal.source = source
            do {
                try store.saveCalendar(cal, commit: true)
                return cal
            } catch {
                // Try next source
                continue
            }
        }

        throw RemindersServiceError.noWritableList
    }

    private func rank(_ s: EKSource) -> Int {
        switch s.sourceType {
        case .calDAV:
            // Prefer iCloud over other CalDAV sources.
            return s.title.localizedCaseInsensitiveContains("icloud") ? 0 : 1
        case .local:
            return 2
        case .exchange:
            return 3
        default:
            return 10
        }
    }
}
