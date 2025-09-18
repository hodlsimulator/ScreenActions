# Screen Actions

**iOS 26+ (iPhone only).** On-device App Intents that act on what’s on screen: add calendar events, create reminders, extract contacts, and turn receipts into CSVs.

- **Bundle ID:** `com.conornolan.Screen-Actions`  
- **App Group:** `group.com.conornolan.screenactions`

---

## What’s new (18 Sep 2025)

- **📄 iOS 26 “Document Mode” (on-device, no servers).**  
  Uses Vision 26 document understanding to read real **tables** and structured text:
  - **Receipt → CSV v2:** photos/screenshots of receipts become accurate CSVs (rows/columns, not heuristics).  
  - **Batch contact capture:** a photographed sign-up sheet becomes multiple Contacts in one go.  
  - **Lens-smudge hint:** friendly nudge if the camera looks foggy (no blocking; still processes).
  - **Editors wired:** **ReceiptCSVPreviewView** and **ContactEditorView** can **seed from an image** if present.
  - **Shared panel wired:** **SAActionPanelView** shows “Document Mode available” when an image is passed in and adds quick actions (“Export From Image”, “Save From Image (batch)”).
  - **Share Extension updated:** passes original **image data** into the shared panel so Document Mode can run there too.
  - **App Intents updated:** **ReceiptToCSVIntent** and **ExtractContactIntent** prefer Document Mode on iOS 26; fall back to OCR on older OSes.
  - **100% on-device; no network or costs.**
- **💫 Monetisation (StoreKit 2) — Pro + Tip Jar + daily free quotas.**  
  - **Products (exact IDs):**  
    - `com.conornolan.Screen_Actions.pro.monthly` — Auto-Renewable Subscription (1 month)  
    - `com.conornolan.Screen_Actions.pro.lifetime` — Non-Consumable  
    - `com.conornolan.Screen_Actions.tip.small` — Consumable  
    - `com.conornolan.Screen_Actions.tip.medium` — Consumable  
    - `com.conornolan.Screen_Actions.tip.large` — Consumable
  - **Suggested pricing (pick nearby tiers):** Monthly €0.99 • Lifetime €16.99 • Tips €0.99 / €2.99 / €4.99.  
    UI shows **localised** prices via `Product.displayPrice` (no hard-coded currency).
  - **Free (daily quotas):** Receipt → CSV **3/day** • Create Contact **from image 5/day** • Add Event **with geofence 1/day**.  
    **Pro** removes limits and unlocks the **“Remember last action”** toggle in the Safari popup.
  - **Implementation:** StoreKit 2 (`ProStore`, `SAProducts`, `ProPaywallView`), quota gates in editors and extensions, and Pro status mirrored to the App Group (`iap.pro.active`) for the Safari/Share/Action extensions. (See **Monetisation** section below.)
- **New app icon** applied across app, extensions, and widgets; asset catalog tidied and 1024-px sources updated.
- **Home Screen redesign:** clearer action cards with a top-row entry for **Scan / Paste / Share**; toolbar simplified for one-hand reach; typography/spacing aligned with iOS 26.
- **📋 Paste button fixes.**  
  Fixed the **Paste** button sometimes getting hidden; it now **greys out** when there’s nothing on the clipboard.
- **Onboarding overhaul (design finished, first pass shipped):** short, privacy-first flow that explains what runs on device, requests the right permissions, and offers quick enable steps for the Safari/Share extensions and Scan.
- **Auto Detect** now opens the relevant **Edit** page first (matches manual actions), so you review before saving.
- **Visual Intelligence scanner implemented** (VisionKit Data Scanner) for barcodes/QR + text; routes into the matching editor.
- **Scanner responsiveness tuned:** barcode path uses `.fast` quality, a narrower **regionOfInterest**, limited OCR languages, and first-hit auto-capture.

**Dev notes (18 Sep 2025):**
- New helper: **`Screen Actions/Core/VisionDocumentReader.swift`** (iOS 26 only).  
  **Target membership:** ✅ **Screen Actions**, ✅ **ScreenActionsActionExtension**, ✅ **ScreenActionsShareExtension** (not the Safari Web Extension / Controls).  
  The file is tolerant to minor SDK shape differences and falls back to classic OCR when no tables are detected.

---

## What’s new (17 Sep 2025)

- **Geofencing UI implemented.** Event editor now has **Notify on arrival / departure** toggles and a **radius** slider (50–2,000 m). Includes a brief explainer to request **Always** location. Wired via `CalendarService.addEvent(…, geofenceProximity:, geofenceRadius:)`.
- **Safari Web Extension working (iOS Safari).** Popup actions call the native handler via Safari’s native messaging; background worker kept minimal for now. **Shipping note:** the extension **ships without** the ExtensionKit entitlement; see “Signing approach” below.
- **Popup polish.** Selection is now **frame-aware** (grabs text from iframes and focused inputs), falls back to **title/URL** when nothing’s selected, and shows **permission hints** if Calendars/Reminders/Contacts access is denied.
- **Event alert minutes remembered.** The Event editor **remembers your last alert choice** (e.g. “30 minutes before”) across launches.
- **APIs tidied for iOS 26.** MapKit 26 clean-ups: no deprecated placemark APIs; uses `MKMapItem.location` and time-zone fallback via `MKReverseGeocodingRequest`. Concurrency warnings removed.

---

## Signing approach (Sept 2025 — read me)

We **intentionally do not request** the ExtensionKit entitlement (`com.apple.developer.extensionkit.extension-point-identifiers`) for the iOS Safari Web Extension. The extension **works without it** and archives/upload reliably. Requesting the key caused profile mismatches and wasted cycles.  
**Plan:** ship with App Group only. If we ever decide to add the key, we’ll do it on a short-lived branch with a pinned profile; if it pushes back, we revert immediately.

**Checklist for Release archives:**
- App + appex sign with **Apple Distribution** (so `get-task-allow = 0`).
- App Group present on the web-extension appex.
- **No** ExtensionKit entitlement requested anywhere.

Optional guard (advisory): `ruby tools/verify_webext_guard.rb`

---

## 🛒 Monetisation (Pro + Tip Jar — StoreKit 2)

**Products to create in App Store Connect (IDs must match exactly):**
- `com.conornolan.Screen_Actions.pro.monthly` — Auto-Renewable (1 month)
- `com.conornolan.Screen_Actions.pro.lifetime` — Non-Consumable
- `com.conornolan.Screen_Actions.tip.small` — Consumable
- `com.conornolan.Screen_Actions.tip.medium` — Consumable
- `com.conornolan.Screen_Actions.tip.large` — Consumable

**Suggested pricing (choose nearby tiers in ASC):**  
Monthly €0.99 • Lifetime €16.99 • Tips €0.99 / €2.99 / €4.99.  
UI shows localised prices via **StoreKit 2** (`Product.displayPrice`) — **no hard-coded €**.

**Free vs Pro (what ships today):**
- **Free (daily quotas):**
  - Receipt → CSV: **up to 3 exports/day**
  - Create Contact **from image**: **up to 5 saves/day**
  - Add Event **with geofence**: **up to 1/day**
- **Pro (unlimited + QoL):**
  - Unlimited CSV exports / contacts-from-images / geofenced events
  - **Safari popup:** **“Remember last action”** toggle (Pro-only), plus **Run Last** button when enabled
  - “Early features” as they ship (server-side switch with local checks — no app update required)

**Implementation notes (repo):**
- **StoreKit 2 core:** `Core/IAP/SAProducts.swift` (IDs) + `Core/IAP/ProStore.swift` (loading, purchase/restore, entitlement) + `Screen Actions/ProPaywallView.swift` (UI).  
  `ProStore` mirrors entitlement to App Group keys:  
  - `iap.pro.active` (Bool)  
  - `iap.pro.exp` (optional expiry timestamp for subs)
- **Quota gating:** `Core/QuotaManager.swift` (app) with per-day keys like `quota.v1.<feature>.<yyyy-m-d>` in the App Group. Editors call it where relevant:
  - `ReceiptCSVPreviewView` → gate on export (3/day)
  - `ContactEditorView` → gate **only** when seeded from an image (5/day)
  - `EventEditorView` → gate **only** when geofencing is enabled (1/day)
- **Extensions:** small, target-local quota helpers mirroring the same logic (share App Group storage):
  - Action Ext: `ScreenActionsActionExtension/AEQuotaManager.swift`
  - Share Ext:  `ScreenActionsShareExtension/SEQuotaManager.swift`
  - Safari Web Ext: `ScreenActionsWebExtension/WEQuotaManager.swift` (CSV gate in `SafariWebExtensionHandler`)
- **Safari popup (Web Extension):** shows **Pro-only** “Remember last action” toggle; persists flag and exposes **Run Last** when set. Pro status is read from App Group (`iap.pro.active`) via native messaging.
- **Settings → Tip Jar:** three buttons wired to the tip consumables; prices come from `displayPrice`. Restore Purchases is available.

**To ship:**
1. Create the five IAPs in **App Store Connect** using the **exact IDs** above, choose nearby pricing tiers.  
2. Enable **In-App Purchase** capability on the **app** target.  
3. Build to a device; StoreKit displays sandbox prices. No currency is hard-coded; all prices are localised.

---

## Requirements & compatibility
- **Minimum OS:** iOS **26**.
- **Devices:** iPhones with **Apple Intelligence** support (e.g. iPhone 15 Pro/Pro Max, the iPhone 16 family, the iPhone 17 family, and newer).
- **Apple Intelligence:** Turn on in **Settings → Apple Intelligence & Siri**; availability varies by language/region.
- **Device support:** **iPhone only** (no iPad, no macOS).
- **Capabilities:** Calendars, Reminders, Contacts, **Location (When In Use)**, **Always & When In Use** (for geofencing), Camera (for Scan), and App Group **`group.com.conornolan.screenactions`** must be enabled.

## What you can do
- **Add to Calendar** — Detects dates/times in text and creates an event *(optional location, alert, travel-time alarm, and geofenced arrive/leave notifications)*.
- **Create Reminder** — Finds tasks/deadlines and makes a reminder.
- **Extract Contact** — Pulls names, emails, phones, and addresses into Contacts.  
  **iOS 26+:** can **batch-create** contacts from a photographed table (e.g. sign-up sheet).
- **Receipt → CSV** — Parses receipt-like text to a shareable CSV.  
  **iOS 26+:** accepts **photos/screenshots** of receipts and produces more accurate CSVs via table reading.
- **Scan (live)** — Use the Visual Intelligence scanner to capture text or barcodes/QR and jump straight to the matching editor.

All actions use on-device Apple frameworks (Vision OCR, Vision 26 Document Mode, `NSDataDetector`, EventKit, Contacts, MapKit).

## Targets in this project
- **Screen Actions (App)** — SwiftUI app with redesigned Home, inline editors, and a simplified toolbar. Includes **Scan** entry and Document Mode hooks in editors.
- **ScreenActionsActionExtension** — action extension (grabs selected text via `GetSelection.js`) and hosts the **shared panel** (now accepts optional image data for Document Mode).
- **ScreenActionsShareExtension** — share-sheet flow to pass text/images; **for images, passes original data** into the shared panel so Document Mode can run there; OCRs for preview text if needed.
- **ScreenActionsControls** — widget/live activity utilities.
- **ScreenActionsWebExtension** — **iOS Safari Web Extension**: popup UI + native messaging. *(iOS does not support context menus.)*

## Build & run
1. Open **`Screen Actions.xcodeproj`** in Xcode.
2. Set **iOS Deployment Target = 26.0** for **all** targets/configs (Debug/Release).
3. In **Signing & Capabilities**:
   - App target bundle ID: **com.conornolan.Screen-Actions**
   - App Group: **group.com.conornolan.screenactions**
   - **In-App Purchase:** enable on the **app** target.
4. Run on an Apple Intelligence-capable iPhone on **iOS 26**.
5. (If needed) Enable **Apple Intelligence** in **Settings → Apple Intelligence & Siri**.
6. To use the Safari Web Extension on device: enable it in **Settings → Safari → Extensions → Screen Actions**.
7. To appear in Location Services quickly: in-app **Settings → Request Location Access**, then allow **While Using** and **Always**.
8. To try **Scan**: open the app’s Home and tap **Scan** (camera prompts appear on first use).
9. *(Dev notes — Document Mode)* Ensure **`Core/VisionDocumentReader.swift`** is a member of:
   - ✅ **Screen Actions**  
   - ✅ **ScreenActionsActionExtension**  
   - ✅ **ScreenActionsShareExtension**
10. *(Dev tip)* Verify extension wiring from Terminal (expect “✅ All checks passed.”):
    
       ruby tools/verify_webext_guard.rb

## Permissions used (Info.plist)
- `NSCalendarsFullAccessUsageDescription` — lets the app add events.
- `NSRemindersFullAccessUsageDescription` — lets the app create reminders.
- `NSContactsUsageDescription` — lets the app save contacts.
- `NSLocationWhenInUseUsageDescription` — used for travel-time and geofenced arrive/leave notifications.
- `NSLocationAlwaysAndWhenInUseUsageDescription` — allows geofence notifications even if the app is closed.
- `NSCameraUsageDescription` — required for the Visual Intelligence scanner.
- `NSSupportsLiveActivities` — enables live activities (where supported).

## How it works (high level)
- **Text capture:** via share/action/web extensions (`SAGetSelection.js` / `GetSelection.js`) and `ActionViewController.swift`.
- **iOS 26 Document Mode:** Vision 26 **RecognizeDocumentsRequest** groups text into paragraphs/tables; we walk **table rows/cells** and attach **detected data** (emails/phones/addresses) per cell. A **smudge** check provides a gentle “clean lens?” note (no blocking).
- **OCR (fallback):** Vision recognises text from images (`TextRecognition.swift`) when no table is found or on older OSes.
- **Live scan:** VisionKit Data Scanner (`VisualScannerView`) for barcodes/QR and text.
  - Uses `.fast` quality for barcodes, a narrowed **regionOfInterest**, and limited OCR languages to keep it responsive.
  - Auto-captures the first solid barcode hit; otherwise allows tap-to-pick text.
- **Parsing:** `NSDataDetector` pulls dates, phones, and addresses (`DataDetectors.swift`).  
- **Location hint (events):** heuristics extract places from text (postal address detection plus “at/@/in …” phrases).  
- **Calendar:** `CalendarService` writes `event.location`, structured location (`EKStructuredLocation`), optional **travel-time alarm**, and registers **geofenced arrive/leave** via `GeofencingManager` (driven by the editor’s arrival/departure toggles + radius).
- **Time zone inference:** prefers `MKMapItem.timeZone`; falls back to **`MKReverseGeocodingRequest`** to resolve a best-effort zone (iOS 26-compliant).
- **CSV export:** `CSVExporter.writeCSVToAppGroup(...)` writes into the App Group’s `Exports/` folder.
- **Editors & flow:** Manual actions and Auto Detect both open the relevant editor first (review → Save).
- **Monetisation internals:** StoreKit 2 entitlement mirrored into the App Group, extensions read `iap.pro.active` for UI/limits; per-feature daily counters stored under `quota.v1.*` keys (reside in the App Group for cross-target consistency).

## Storage
Exports are written to:  
`~/Library/Group Containers/group.com.conornolan.screenactions/Exports`

*(Extensions fall back to a private temp folder if the App Group isn’t present; the app uses the App Group when available.)*

## Troubleshooting
- If extensions don’t appear, clean build, reinstall to device, then enable the relevant extension in **Settings → Safari → Extensions**.
- If the popup shows “can’t connect” errors, ensure the extension is enabled and the app is installed on the device.
- If CSV isn’t visible, check the App Group path above and that the App Group entitlement matches exactly.
- If Apple Intelligence options aren’t visible, confirm your device is supported, language settings match, and there’s sufficient free space.
- If Archive fails with an ExtensionKit entitlement error, ensure you are **not** requesting that entitlement anywhere (by design we don’t).
- If Scan feels sluggish, try barcode-only mode first and fill more of the ROI band with the code.
- If purchases don’t show: confirm IAPs exist in App Store Connect with the **exact IDs**, In-App Purchase capability is enabled, and test on-device with a sandbox Apple ID (prices appear localised via StoreKit).

---

## Roadmap (updated 18 Sep 2025)

### Core (on-device)
- ✅ Date parsing: `DateParser.firstDateRange` (`NSDataDetector`).
- ✅ Contact parsing: `ContactParser.detect`.
- ✅ OCR utilities for images (Vision).
- ✅ CSV export (v1) + App Group/Temp routing.
- ✅ Services: create EK events/reminders; save contacts.
- ✅ **Events:** location string + **structured location (`EKStructuredLocation`)**, **travel-time alarm**, and **optional geofencing (enter/exit)** via `GeofencingManager`.
- ✅ **iOS 26: Document Mode** — Vision document tables + smudge hint; editors, App Intents, and shared panel wired.
- ✅ Visual Intelligence scanner baseline (barcodes/QR + text, ROI, `.fast` path, haptics).

### Auto-Detect (router + intent)
- ✅ Heuristic router picks receipt/contact/event/reminder and returns optional date range.
- ✅ Opens editor before saving (matches manual actions).
- ✅ App Intent: `AutoDetectIntent` calls the router; also exposes `runStandalone`.

### App UI (main app)
- ✅ Home Screen redesign (cards, Scan/Paste/Share row, simplified toolbar).
- ✅ Inline editors for Event/Reminder/Contact and Receipt-to-CSV preview presented as sheets.
- ✅ Geofencing UI in Event editor: arrival/departure toggles + radius slider (50–2,000 m) with permission explainer.
- ⏳ Onboarding overhaul — staged rollout of guided prompts and extension enablement flows.

### Unified action panel (extensions)
- ✅ `SAActionPanelView` shared by Action/Share extensions with inline editors and direct-run shortcuts.
- ✅ **Document Mode hooks** (image → quick actions, seeding editors).

### Safari Web Extension (iOS)
- ✅ Popup shows 5 buttons (Auto Detect + four manual).
- ✅ Native handler supports `autoDetect`, `createReminder`, `addEvent`, `extractContact`, `receiptCSV`.
- ✅ Popup polish: frame-aware selection; fall back to title/URL; permission hints when access is denied.
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

---

## Action plan (clear next steps)

**Completed on 18 Sep 2025**
- ✅ Visual Intelligence scanner shipped (barcodes/QR + text), with ROI & `.fast` path and limited OCR languages for speed.
- ✅ Home Screen redesign landed.
- ✅ Auto Detect → Editor-first behaviour matched to manual actions.
- ✅ New app icon rolled out across all targets.
- ✅ Onboarding overhaul: design complete + first pass shipped (permissions & extensions guidance).
- ✅ **iOS 26 Document Mode** wired across app + extensions (tables, smudge hint, editors, intents).
- ✅ **Monetisation**: Pro + Tip Jar shipped with StoreKit 2; daily free quotas enforced across app and extensions; Safari popup gains Pro-only “Remember last action”.

**Completed on 17 Sep 2025**
- ✅ **Distribution signing & archive** — Release archive uploaded to App Store Connect; web extension embedded; **no** ExtensionKit entitlement requested; App Group present; delivered package has `get-task-allow = 0`.

**Next patch:**
1. QA matrix (device) — exercise all actions across permission states (granted/denied), iframes, text inputs; tighten error surfaces.
2. Locale & tests — en-IE/en-GB/en-US date/number formats; CSV decimals/commas; currency symbols.
3. A11y & localisation — VoiceOver labels for popup/buttons; Dynamic Type checks; initial strings in `en.lproj`.
4. Docs — quick start for dev scripts (`tools/verify_webext_guard.rb`) and typical failure cases.

**Then (sequenced):**
- Receipts v2 + PDF OCR → structured totals; rasterise PDF pages for Vision.  
- History & Undo → App Group ledger + simple “Undo last” surface.  
- Reliability polish → error surfaces, toasts, OSLog categories; unify service calls.  
- Flights & parcels → new parsers + deep links.

---

© 2025. All rights reserved.
