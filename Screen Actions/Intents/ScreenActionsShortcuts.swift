//
//  ScreenActionsShortcuts.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import AppIntents

struct ScreenActionsShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    // iOS 26: implement using the builder (no array literal)
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddToCalendarIntent(),
            phrases: [
                "Add to calendar with \(.applicationName)",
                "Create event with \(.applicationName)"
            ],
            shortTitle: "Add to Calendar",
            systemImageName: "calendar.badge.plus"
        )

        AppShortcut(
            intent: CreateReminderIntent(),
            phrases: [
                "Create reminder with \(.applicationName)"
            ],
            shortTitle: "Create Reminder",
            systemImageName: "checklist"
        )

        AppShortcut(
            intent: ExtractContactIntent(),
            phrases: [
                "Save contact with \(.applicationName)"
            ],
            shortTitle: "Extract Contact",
            systemImageName: "person.crop.circle.badge.plus"
        )

        AppShortcut(
            intent: ReceiptToCSVIntent(),
            phrases: [
                "Receipt to CSV with \(.applicationName)"
            ],
            shortTitle: "Receipt → CSV",
            systemImageName: "doc.richtext"
        )
    }
}
