//
//  AddToCalendarIntent.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//  Updated: 15/09/2025 – Location + time zone + alert parameters
//

import AppIntents

struct AddToCalendarIntent: AppIntent {
    static var title: LocalizedStringResource { "Add to Calendar" }
    static var description: IntentDescription {
        IntentDescription("Creates a calendar event by detecting a date/time in your text or image. Optionally include a place and an alert.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text", description: "Paste text containing a date/time")
    var text: String?

    @Parameter(title: "Image", description: "Use an image or screenshot with a visible date/time")
    var image: IntentFile?

    @Parameter(title: "Location", description: "Optional place or address (e.g. “Google London”, “1 Drummond Gate, SW1V”).")
    var location: String?

    @Parameter(title: "Alert Minutes Before", description: "Set an alert (e.g. 5, 10, 15, 30). Leave empty for none.")
    var alertMinutesBefore: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let sourceText: String
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceText = t
        } else {
            sourceText = try TextExtractor.from(imageFile: image)
        }

        guard !sourceText.isEmpty else {
            throw $text.needsValueError("Provide text or an image with text.")
        }
        guard let range = DateParser.firstDateRange(in: sourceText) else {
            return .result(value: "No date found.", dialog: "I couldn't find a date/time in the provided content.")
        }

        let title = makeTitle(from: sourceText)
        let id = try await CalendarService.shared.addEvent(
            title: title,
            start: range.start,
            end: range.end,
            notes: sourceText,
            locationHint: (location?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 },
            inferTimeZoneFromLocation: true,
            alertMinutesBefore: (alertMinutesBefore ?? 0) > 0 ? alertMinutesBefore : nil
        )
        return .result(value: "Event created (\(id)).", dialog: "Event created.")
    }

    private func makeTitle(from text: String) -> String {
        let first = text
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if first.isEmpty { return "Event" }
        return first.count > 64 ? String(first.prefix(64)) : first
    }
}

extension AddToCalendarIntent {
    @MainActor
    static func runStandalone(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Provide text first." }
        guard let range = DateParser.firstDateRange(in: trimmed) else { return "No date found." }

        let title = trimmed
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Event"

        let id = try await CalendarService.shared.addEvent(
            title: title,
            start: range.start,
            end: range.end,
            notes: trimmed,
            locationHint: nil,
            inferTimeZoneFromLocation: true,
            alertMinutesBefore: nil
        )
        return "Event created (\(id))."
    }
}
