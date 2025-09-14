# Screen Actions

On-device App Intents that act on whatever’s on screen: quickly add calendar events and reminders, pull out contact details, and turn receipt text into a CSV you can share. iPhone only.

- **Bundle ID:** `com.conornolan.Screen-Actions`
- **App Group:** `group.com.conornolan.screenactions`

## Requirements & compatibility

- **Minimum OS:** iOS **26**.
- **Devices:** Apple Intelligence-compatible iPhones only:
  - **iPhone 15 Pro** and **iPhone 15 Pro Max**
  - **All iPhone 16 models and later** (this includes the iPhone 17 family)
- **Apple Intelligence:** Make sure Apple Intelligence is enabled (Settings → **Apple Intelligence & Siri**). Your **device language** and **Siri language** must be set to a supported language. Apple notes that downloading on-device models may require ~**7 GB** free space.
- **Capabilities:** Calendars, Reminders, Contacts, and the App Group **`group.com.conornolan.screenactions`** must be enabled.
- **Notes for EU users:** Some Apple Intelligence features vary by region and language. See Apple’s support page for the latest details.

> For Apple’s current device/OS requirements for Apple Intelligence, see:  
> https://support.apple.com/121115

## What you can do

- **Add to Calendar** — Detects dates/times in selected or shared text and creates an event.
- **Create Reminder** — Finds tasks/deadlines in text and makes a reminder.
- **Extract Contact** — Pulls names, emails, phone numbers and addresses into a new contact.
- **Receipt → CSV** — Turns receipt-like lines into a CSV you can save or share.

All actions run on-device using Apple frameworks (e.g. **Vision** for OCR and `NSDataDetector` for dates, phones, addresses).

## Targets in this project

- **Screen Actions (App)** — main SwiftUI app.
- **ScreenActionsActionExtension** — action extension (uses `GetSelection.js`) to grab selected page text.
- **ScreenActionsShareExtension** — share-sheet flow to pass text/images into actions.
- **ScreenActionsControls** — widget/live activity utilities.
- **ScreenActionsWebExtension** — Safari Web Extension resources.

## Build & run

1. Open **`Screen Actions.xcodeproj`** in Xcode.
2. In **Signing & Capabilities**:
   - App target bundle ID: **com.conornolan.Screen-Actions**
   - App Group: **group.com.conornolan.screenactions**
3. Select an Apple Intelligence-compatible iPhone on **iOS 26** and **Run**.
4. (If needed) Enable Apple Intelligence in **Settings → Apple Intelligence & Siri** so on-device features are available.

## Permissions used (Info.plist)

- `NSCalendarsFullAccessUsageDescription` — lets the app add events.
- `NSRemindersFullAccessUsageDescription` — lets the app create reminders.
- `NSContactsUsageDescription` — lets the app save contacts.
- `NSSupportsLiveActivities` — enables live activities (where supported).

## How it works (high level)

- **Text capture:** via share/action/web extensions (see `GetSelection.js` and `ActionViewController.swift`).
- **OCR (optional):** Vision recognises text from images (`TextRecognition.swift`).
- **Parsing:** `NSDataDetector` pulls dates, phones and addresses (`DataDetectors.swift`).
- **CSV export:** `CSVExporter.writeCSVToAppGroup(...)` writes into the App Group’s `Exports/` folder.

## Privacy

Designed to process data locally on your device. Exports are written to the App Group container:  
`~/Library/Group Containers/group.com.conornolan.screenactions/Exports`

## Troubleshooting

- If extensions don’t appear, clean build, reinstall to device, then enable the relevant extension in Settings/Safari.
- If CSV isn’t visible, check the App Group path above and that the App Group entitlement matches exactly.
- If Apple Intelligence options aren’t visible, confirm your device is supported and languages are set as per Apple’s guidance.

---
© 2025. All rights reserved.
