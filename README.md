# Screen Actions

**iOS 26+ (iPhone only).** On-device App Intents that act on what’s on screen: add calendar events, create reminders, extract contacts, and turn receipts into CSVs.

- **Bundle ID:** `com.conornolan.Screen-Actions`  
- **App Group:** `group.com.conornolan.screenactions`

## Requirements & compatibility
- **Minimum OS:** iOS **26**.
- **Devices:** iPhones with **Apple Intelligence** support (e.g. iPhone 15 Pro/Pro Max, the iPhone 16 family, the iPhone 17 family, and newer).
- **Apple Intelligence:** Turn on in **Settings → Apple Intelligence & Siri**; availability varies by language/region.
- **Capabilities:** Calendars, Reminders, Contacts, and App Group **`group.com.conornolan.screenactions`** must be enabled.

## What you can do
- **Add to Calendar** — Detects dates/times in text and creates an event.
- **Create Reminder** — Finds tasks/deadlines and makes a reminder.
- **Extract Contact** — Pulls names, emails, phones, and addresses into Contacts.
- **Receipt → CSV** — Parses receipt-like text to a shareable CSV.

All actions use on-device Apple frameworks (Vision OCR, `NSDataDetector`, EventKit, Contacts).

## Targets in this project
- **Screen Actions (App)** — main SwiftUI app.
- **ScreenActionsActionExtension** — action extension (grabs selected text via `GetSelection.js`).
- **ScreenActionsShareExtension** — share-sheet flow to pass text/images into actions.
- **ScreenActionsControls** — widget/live activity utilities.
- **ScreenActionsWebExtension** — Safari Web Extension resources (macOS Safari focused).

## Build & run
1. Open **`Screen Actions.xcodeproj`** in Xcode.
2. Set **iOS Deployment Target = 26.0** for **all** targets/configs (Debug/Release).
3. In **Signing & Capabilities**:
   - App target bundle ID: **com.conornolan.Screen-Actions**
   - App Group: **group.com.conornolan.screenactions**
4. Run on an Apple Intelligence-capable iPhone on **iOS 26**.
5. (If needed) Enable **Apple Intelligence** in **Settings → Apple Intelligence & Siri**.

## Permissions used (Info.plist)
- `NSCalendarsFullAccessUsageDescription` — lets the app add events.
- `NSRemindersFullAccessUsageDescription` — lets the app create reminders.
- `NSContactsUsageDescription` — lets the app save contacts.
- `NSSupportsLiveActivities` — enables live activities (where supported).

## How it works (high level)
- **Text capture:** via share/action/web extensions (`SAGetSelection.js` / `GetSelection.js`) and `ActionViewController.swift`.
- **OCR (optional):** Vision recognises text from images (`TextRecognition.swift`).
- **Parsing:** `NSDataDetector` pulls dates, phones, and addresses (`DataDetectors.swift`).
- **CSV export:** `CSVExporter.writeCSVToAppGroup(...)` writes into the App Group’s `Exports/` folder.

## Storage
Exports are written to:
`~/Library/Group Containers/group.com.conornolan.screenactions/Exports`

## Troubleshooting
- If extensions don’t appear, clean build, reinstall to device, then enable the relevant extension in Settings/Safari.
- If CSV isn’t visible, check the App Group path above and that the App Group entitlement matches exactly.
- If Apple Intelligence options aren’t visible, confirm your device is supported, language settings match, and there’s sufficient free space.

---

© 2025. All rights reserved.
EOFcat > README.md <<'EOF'
# Screen Actions

**iOS 26+ (iPhone only).** On-device App Intents that act on what’s on screen: add calendar events, create reminders, extract contacts, and turn receipts into CSVs.

- **Bundle ID:** `com.conornolan.Screen-Actions`  
- **App Group:** `group.com.conornolan.screenactions`

## Requirements & compatibility
- **Minimum OS:** iOS **26**.
- **Devices:** iPhones with **Apple Intelligence** support (e.g. iPhone 15 Pro/Pro Max, the iPhone 16 family, the iPhone 17 family, and newer).
- **Apple Intelligence:** Turn on in **Settings → Apple Intelligence & Siri**; availability varies by language/region.
- **Capabilities:** Calendars, Reminders, Contacts, and App Group **`group.com.conornolan.screenactions`** must be enabled.

## What you can do
- **Add to Calendar** — Detects dates/times in text and creates an event.
- **Create Reminder** — Finds tasks/deadlines and makes a reminder.
- **Extract Contact** — Pulls names, emails, phones, and addresses into Contacts.
- **Receipt → CSV** — Parses receipt-like text to a shareable CSV.

All actions use on-device Apple frameworks (Vision OCR, `NSDataDetector`, EventKit, Contacts).

## Targets in this project
- **Screen Actions (App)** — main SwiftUI app.
- **ScreenActionsActionExtension** — action extension (grabs selected text via `GetSelection.js`).
- **ScreenActionsShareExtension** — share-sheet flow to pass text/images into actions.
- **ScreenActionsControls** — widget/live activity utilities.
- **ScreenActionsWebExtension** — Safari Web Extension resources (macOS Safari focused).

## Build & run
1. Open **`Screen Actions.xcodeproj`** in Xcode.
2. Set **iOS Deployment Target = 26.0** for **all** targets/configs (Debug/Release).
3. In **Signing & Capabilities**:
   - App target bundle ID: **com.conornolan.Screen-Actions**
   - App Group: **group.com.conornolan.screenactions**
4. Run on an Apple Intelligence-capable iPhone on **iOS 26**.
5. (If needed) Enable **Apple Intelligence** in **Settings → Apple Intelligence & Siri**.

## Permissions used (Info.plist)
- `NSCalendarsFullAccessUsageDescription` — lets the app add events.
- `NSRemindersFullAccessUsageDescription` — lets the app create reminders.
- `NSContactsUsageDescription` — lets the app save contacts.
- `NSSupportsLiveActivities` — enables live activities (where supported).

## How it works (high level)
- **Text capture:** via share/action/web extensions (`SAGetSelection.js` / `GetSelection.js`) and `ActionViewController.swift`.
- **OCR (optional):** Vision recognises text from images (`TextRecognition.swift`).
- **Parsing:** `NSDataDetector` pulls dates, phones, and addresses (`DataDetectors.swift`).
- **CSV export:** `CSVExporter.writeCSVToAppGroup(...)` writes into the App Group’s `Exports/` folder.

## Storage
Exports are written to:
`~/Library/Group Containers/group.com.conornolan.screenactions/Exports`

## Troubleshooting
- If extensions don’t appear, clean build, reinstall to device, then enable the relevant extension in Settings/Safari.
- If CSV isn’t visible, check the App Group path above and that the App Group entitlement matches exactly.
- If Apple Intelligence options aren’t visible, confirm your device is supported, language settings match, and there’s sufficient free space.

---

© 2025. All rights reserved.
