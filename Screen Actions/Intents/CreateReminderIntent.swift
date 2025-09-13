//
//  CreateReminderIntent.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import AppIntents

struct CreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource { "Create Reminder" }
    static var description: IntentDescription { IntentDescription("Creates a reminder by detecting a date/time (if present) and using the first line as the title.") }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text")
    var text: String?

    @Parameter(title: "Image")
    var image: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let sourceText: String
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceText = t
        } else {
            sourceText = try TextExtractor.from(imageFile: image)
        }

        guard !sourceText.isEmpty else {
            throw $text.needsValueError("Provide text or an image with text.")
        }

        let title = makeTitle(from: sourceText)
        let due = DateParser.firstDateRange(in: sourceText)?.start
        let id = try await RemindersService.addReminder(title: title, due: due, notes: sourceText)
        return .result(value: "Reminder created (\(id)).", dialog: "Reminder created.")
    }

    private func makeTitle(from text: String) -> String {
        let first = text.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if first.isEmpty { return "Todo" }
        return first.count > 64 ? String(first.prefix(64)) : first
    }
}

extension CreateReminderIntent {
    @MainActor
    static func runStandalone(text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Provide text first." }
        let title = trimmed.components(separatedBy: .newlines).first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? "Todo"
        let due = DateParser.firstDateRange(in: trimmed)?.start
        let id = try await RemindersService.addReminder(title: title, due: due, notes: trimmed)
        return "Reminder created (\(id))."
    }
}
