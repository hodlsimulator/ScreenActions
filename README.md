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

## Roadmap

### Where we are (15 Sep 2025)

**Core (on-device)**
- ✅ Date parsing: `DateParser.firstDateRange` (`NSDataDetector`). — GitHub
- ✅ Contact parsing: `ContactParser.detect`. — GitHub
- ✅ OCR utilities for images (Vision). — GitHub
- ✅ CSV export (v1) + App Group/Temp routing. — GitHub +1
- ✅ Services: create EK events/reminders; save contacts. — GitHub +2
- GitHub +2

**Auto-Detect (router + intent)**
- ✅ Heuristic router picks receipt/contact/event/reminder and returns optional date range. — GitHub
- ✅ App Intent: `AutoDetectIntent` calls the router; also exposes `runStandalone`. — GitHub

**App UI (main app)**
- ✅ Text editor + bottom toolbar for: Auto Detect, Add to Calendar, Create Reminder, Extract Contact, Receipt → CSV. (Direct-run path; no inline editors here yet.) — GitHub

**Unified action panel (used by extensions)**
- ✅ `SAActionPanelView` with Auto Detect primary; manual actions open inline editors (Event/Reminder/Contact/CSV preview). Includes direct-run context menu shortcuts. — GitHub

**Share Extension (UI)**
- ✅ Hosts `SAActionPanelView`; falls back to Vision OCR for images before showing the panel. — GitHub

**Action Extension (UI)**
- ✅ Hosts `SAActionPanelView`; preloads selection/title/url from JS. — GitHub

**Safari Web Extension**
- ✅ Popup shows 5 buttons (Auto Detect + four manual). — GitHub
- ✅ Native handler supports `autoDetect`, `createReminder`, `addEvent`, `extractContact`, `receiptCSV`. — GitHub
- ⚠️ No context-menu actions yet; background is minimal; manifest has no `contextMenus` permission. — GitHub +1

**Shortcuts**
- ✅ Tiles for all five, including Auto Detect (phrases + colour). — GitHub

**Onboarding**
- ✅ Share-sheet pinning flow wired (checklist + “ping” bridge). — GitHub

**Permissions / Info.plist**
- ✅ Calendars/Reminders/Contacts usage strings present. — GitHub

**Delta since last plan**
- ✅ Auto Detect is now wired everywhere: App toolbar, Share Extension, Action Extension, Safari popup/handler, and Shortcuts tile. — GitHub +6  
  GitHub +6  
  GitHub +6
- ✅ Inline editors exist and are integrated in both extensions via the shared panel (Event/Reminder/Contact editors + CSV preview). App still uses direct-run. — GitHub

---

### What’s left (A–N)

**A) Auto Detect parity across surfaces**  
- ✅ Done (see Delta). Acceptance passes: all surfaces call the same router. — GitHub +2  
  GitHub +2

**B) Inline editors & previews**  
- ✅ Extensions: implemented (sheets for Event/Reminder/Contact; CSV preview with “Open in…”). — GitHub +4  
  GitHub +4  
  GitHub +4  
- ⏳ App: add the same “edit-first” path (either reuse the panel or present the editor sheets from `ContentView`).  
  **Acceptance:** “Edit first” in app + both extensions; Cancel cleanly returns (already handled in panel).

**C) Rich Event Builder (tz, location, travel time)**  
- ⛳ Implement `MKLocalSearch` → coords → inferred TZ; optional Maps ETA alarm; extend AddToCalendar intent params; write to `EKEvent` fields. (CalendarService currently basic.) — GitHub

**D) Flights & itineraries**  
- ⛳ Regex airline+flight; IATA origin/destination; tz inference as in (C); title “BA284 LHR → SFO”; terminals/gate in notes. (New parser.)

**E) Bills & subscriptions (recurring reminders)**  
- ⛳ Currency + recurrence keywords → `EKRecurrenceRule`; map “monthly/annual/… due <date>”.

**F) Parcel tracking helper**  
- ⛳ Tracking pattern library (UPS/FedEx/DHL/Royal Mail/An Post); carrier deep links; optional delivery-day reminder.

**G) Receipt parser v2 (subtotal/tax/tip/total + categories, multi-currency)**  
- ⛳ Extend current `CSVExporter` (v1 is line-based with simple currency regex). — GitHub

**H) PDF & multi-page OCR**  
- ⛳ PDFKit rasterise pages → Vision OCR (current OCR is image-only). — GitHub

**I) Barcode & QR decoder (tickets/URLs/Wi-Fi)**  
- ⛳ Vision barcodes; schema handlers (URL, vCard, Wi-Fi); suggest actions.

**J) Live camera “Scan Mode”**  
- ⛳ `DataScannerViewController` (text + barcodes) → route via `ActionRouter`.

**K) History & Undo**  
- ⛳ Persist last 20 actions in App Group; undo via EventKit/CNContact delete; deep link to created item.

**L) Safari extension upgrades**  
- ⏳ Add `contextMenus` items for right-click text; optional page screenshot when no selection; manifest permission + service-worker handlers. (Native handler already supports `autoDetect`.) — GitHub +1

**M) Internationalisation & locale smarts**  
- ⏳ Ensure parsing respects `Locale.current` for dates/currency/addresses; add tests for en-IE/en-GB/en-US. (Router/Detectors already lean on `NSDataDetector`; formalise tests.) — GitHub +1

**N) Reliability & UX polish**  
- ⏳ Unify service calls; consistent error dialogs/toasts; OSLog categories exist (UI/Core/Extension).  
- ⏳ App Intents: audit `ReturnsValue` generic usage to silence any generic-type warnings. — GitHub +4  
  GitHub +4  
  GitHub +4

---

### Suggested sequencing

**Next patch**
- Finish **B** (App inline editors): reuse `SAActionPanelView` in-app or present the editor sheets from `ContentView`. — GitHub +1  
- Start **L** (Safari context menus): add `contextMenus` permission + handlers; wire to existing native actions. — GitHub

**Then**
- **C + D** (event enrichments + flights) → **G + H** (receipts v2 + PDF OCR) → **K + L** (history + Safari upgrades) → **M + N** (locale + reliability).

---

© 2025. All rights reserved.
