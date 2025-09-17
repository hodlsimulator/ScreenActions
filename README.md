# Screen Actions

**iOS 26+ (iPhone only).** On-device App Intents that act on what’s on screen: add calendar events, create reminders, extract contacts, and turn receipts into CSVs.

- **Bundle ID:** `com.conornolan.Screen-Actions`  
- **App Group:** `group.com.conornolan.screenactions`

---

## What’s new (17 Sep 2025)

- **Geofencing UI implemented.** Event editor now has **Notify on arrival / departure** toggles and a **radius** slider (50–2,000 m). Includes a brief explainer to request **Always** location. Wired via `CalendarService.addEvent(…, geofenceProximity:, geofenceRadius:)`.
- **Safari Web Extension working (iOS Safari).** Popup actions call the native handler via Safari’s native messaging; background worker kept minimal for now.
- **Popup polish.** Selection is now **frame-aware** (grabs text from iframes and focused inputs), falls back to **title/URL** when nothing’s selected, and shows **permission hints** if Calendars/Reminders/Contacts access is denied.
- **Event alert minutes remembered.** The Event editor **remembers your last alert choice** (e.g. “30 minutes before”) across launches.
- **APIs tidied for iOS 26.** MapKit 26 clean-ups: no deprecated placemark APIs; uses `MKMapItem.location` and time-zone fallback via `MKReverseGeocodingRequest`. Concurrency warnings removed.

---

## Requirements & compatibility
- **Minimum OS:** iOS **26**.
- **Devices:** iPhones with **Apple Intelligence** support (e.g. iPhone 15 Pro/Pro Max, the iPhone 16 family, the iPhone 17 family, and newer).
- **Apple Intelligence:** Turn on in **Settings → Apple Intelligence & Siri**; availability varies by language/region.
- **Device support:** **iPhone only** (no iPad, no macOS).
- **Capabilities:** Calendars, Reminders, Contacts, **Location (When In Use)**, **Always & When In Use** (for geofencing), and App Group **`group.com.conornolan.screenactions`** must be enabled.

## What you can do
- **Add to Calendar** — Detects dates/times in text and creates an event *(optional location, alert, travel-time alarm, and geofenced arrive/leave notifications)*.
- **Create Reminder** — Finds tasks/deadlines and makes a reminder.
- **Extract Contact** — Pulls names, emails, phones, and addresses into Contacts.
- **Receipt → CSV** — Parses receipt-like text to a shareable CSV.

All actions use on-device Apple frameworks (Vision OCR, `NSDataDetector`, EventKit, Contacts, MapKit).

## Targets in this project
- **Screen Actions (App)** — main SwiftUI app with inline editors and a bottom toolbar.
- **ScreenActionsActionExtension** — action extension (grabs selected text via `GetSelection.js`) and hosts the shared panel.
- **ScreenActionsShareExtension** — share-sheet flow to pass text/images; OCRs images then hosts the shared panel.
- **ScreenActionsControls** — widget/live activity utilities.
- **ScreenActionsWebExtension** — **iOS Safari Web Extension**: popup UI + native messaging. *(iOS does not support context menus.)*

## Build & run
1. Open **`Screen Actions.xcodeproj`** in Xcode.
2. Set **iOS Deployment Target = 26.0** for **all** targets/configs (Debug/Release).
3. In **Signing & Capabilities**:
   - App target bundle ID: **com.conornolan.Screen-Actions**
   - App Group: **group.com.conornolan.screenactions**
4. Run on an Apple Intelligence-capable iPhone on **iOS 26**.
5. (If needed) Enable **Apple Intelligence** in **Settings → Apple Intelligence & Siri**.
6. To use the Safari Web Extension on device: enable it in **Settings → Safari → Extensions → Screen Actions**.
7. To appear in Location Services quickly: in-app **Settings → Request Location Access**, then allow **While Using** and **Always**.
8. *(Dev tip)* Verify extension wiring from Terminal (expect “✅ All checks passed.”):
    
       ruby tools/verify_webext_guard.rb

## Permissions used (Info.plist)
- `NSCalendarsFullAccessUsageDescription` — lets the app add events.
- `NSRemindersFullAccessUsageDescription` — lets the app create reminders.
- `NSContactsUsageDescription` — lets the app save contacts.
- `NSLocationWhenInUseUsageDescription` — used for travel-time and geofenced arrive/leave notifications.
- `NSLocationAlwaysAndWhenInUseUsageDescription` — allows geofence notifications even if the app is closed.
- `NSSupportsLiveActivities` — enables live activities (where supported).

## How it works (high level)
- **Text capture:** via share/action/web extensions (`SAGetSelection.js` / `GetSelection.js`) and `ActionViewController.swift`.
- **OCR (optional):** Vision recognises text from images (`TextRecognition.swift`).
- **Parsing:** `NSDataDetector` pulls dates, phones, and addresses (`DataDetectors.swift`).  
- **Location hint (events):** heuristics extract places from text (postal address detection plus “at/@/in …” phrases).  
- **Calendar:** `CalendarService` writes `event.location`, structured location (`EKStructuredLocation`), optional **travel-time alarm**, and registers **geofenced arrive/leave** via `GeofencingManager` (driven by the editor’s arrival/departure toggles + radius).
- **Time zone inference:** prefers `MKMapItem.timeZone`; falls back to **`MKReverseGeocodingRequest`** to resolve a best-effort zone (iOS 26-compliant).
- **CSV export:** `CSVExporter.writeCSVToAppGroup(...)` writes into the App Group’s `Exports/` folder.

## Storage
Exports are written to:  
`~/Library/Group Containers/group.com.conornolan.screenactions/Exports`

*(Extensions fall back to a private temp folder if the App Group isn’t present; the app uses the App Group when available.)*

## Troubleshooting
- If extensions don’t appear, clean build, reinstall to device, then enable the relevant extension in **Settings → Safari → Extensions**.
- If the popup shows “can’t connect” errors, ensure the extension is enabled and the app is installed on the device.
- If CSV isn’t visible, check the App Group path above and that the App Group entitlement matches exactly.
- If Apple Intelligence options aren’t visible, confirm your device is supported, language settings match, and there’s sufficient free space.

---

## Roadmap (updated 17 Sep 2025)

### Core (on-device)
- ✅ Date parsing: `DateParser.firstDateRange` (`NSDataDetector`).
- ✅ Contact parsing: `ContactParser.detect`.
- ✅ OCR utilities for images (Vision).
- ✅ CSV export (v1) + App Group/Temp routing.
- ✅ Services: create EK events/reminders; save contacts.
- ✅ **Events:** location string + **structured location (`EKStructuredLocation`)**, **travel-time alarm**, and **optional geofencing (enter/exit)** via `GeofencingManager`.
- ✅ **iOS 26 clean-up:** MapKit 26 (`MKMapItem.location`, `timeZone`)—removed deprecated placemark APIs.

### Auto-Detect (router + intent)
- ✅ Heuristic router picks receipt/contact/event/reminder and returns optional date range.
- ✅ App Intent: `AutoDetectIntent` calls the router; also exposes `runStandalone`.

### App UI (main app)
- ✅ Text editor + bottom toolbar for the five actions.
- ✅ **Inline editors** for Event/Reminder/Contact and **Receipt-to-CSV preview** presented as sheets.
- ✅ **Geofencing UI** in Event editor: arrival/departure toggles + radius slider (50–2,000 m) with permission explainer.

### Unified action panel (extensions)
- ✅ `SAActionPanelView` shared by Action/Share extensions with inline editors and direct-run shortcuts.

### Safari Web Extension (iOS)
- ✅ Popup shows 5 buttons (Auto Detect + four manual).
- ✅ Native handler supports `autoDetect`, `createReminder`, `addEvent`, `extractContact`, `receiptCSV`.
- ✅ **Popup polish:** frame-aware selection; fall back to title/URL; permission hints when access is denied.
- ℹ️ **No context menus on iOS**; manifest intentionally omits `contextMenus`.

### Shortcuts
- ✅ Tiles for all five, including Auto Detect (phrases + colour).

### Internationalisation & locale smarts
- ⏳ Respect `Locale.current` for dates/currency/addresses; tests for en-IE/en-GB/en-US.

### Reliability & UX polish
- ⏳ Unify service calls; consistent error dialogs/toasts; tidy OSLog categories across UI/Core/Extensions.
- ⏳ App Intents: audit `ReturnsValue` usage to keep the generic surface tidy.

### Add-on features
- ⛳ Flights & itineraries: airline+flight regex; IATA origin/destination; tz inference; title `BA284 LHR → SFO`.
- ⛳ Bills & subscriptions: keywords → `EKRecurrenceRule`.
- ⛳ Parcel tracking helper: patterns for UPS/FedEx/DHL/Royal Mail/An Post; carrier links; delivery-day reminder.
- ⛳ Receipt parser v2 (subtotal/tax/tip/total + categories, multi-currency).
- ⛳ PDF & multi-page OCR (PDFKit → Vision).
- ⛳ Barcode & QR decoder (tickets/URLs/Wi-Fi); suggest actions.
- ⛳ Live camera **Scan Mode** (Data Scanner) → route via `ActionRouter`.
- ⛳ History & Undo: persist last 20 actions; undo via EventKit/CNContact delete.

---

## Action plan (clear next steps)

**Next patch:**
1. **Distribution signing & archive**  
   - Archive/Validate for App Store; verify the web-extension entitlement `com.apple.Safari.web-extension` persists in **distribution** profiles.
2. **QA matrix (device)**  
   - Exercise all actions across permission states (granted/denied), iframes, text inputs; tighten error surfaces.
3. **Locale & tests**  
   - en-IE/en-GB/en-US date/number formats; CSV decimals/commas; currency symbols.
4. **A11y & localisation**  
   - VoiceOver labels for popup/buttons; Dynamic Type checks; initial strings in `en.lproj`.
5. **Docs**  
   - Quick start section for dev scripts (`tools/verify_webext_guard.rb`) and typical failure cases.

**Then (sequenced):**
- **Receipts v2 + PDF OCR** → structured totals; rasterise PDF pages for Vision.  
- **History & Undo** → App Group ledger + simple “Undo last” surface.  
- **Reliability polish** → error surfaces, toasts, OSLog categories; unify service calls.  
- **Scan Mode** → Data Scanner → `ActionRouter`.  
- **Flights & parcels** → new parsers + deep links.

---

© 2025. All rights reserved.
