# Screen Actions

On-device actions for what’s on screen: quickly add calendar events and reminders, pull out contact details, and turn receipt text into a CSV. iPhone only.

---

## Where we are (quick audit)

### Core extraction & actions (on-device)
- Date parsing (`DateParser.firstDateRange`)
- Contact parsing
- CSV export
- OCR (Vision)
- Services create **EventKit** events/reminders and save contacts

### Auto-Detect engine (Core)
- `ActionRouter` scores text and routes to **receipt / contact / event / reminder**

### App UI
- Text editor + toolbar: **Add to Calendar**, **Create Reminder**, **Extract Contact**, **Receipt → CSV**  
  _(No **Auto Detect** button yet.)_

### App Intents
- **Add / Reminder / Contact / Receipt** are in place
- **AutoDetectIntent** exists and calls the router (returns a status string)
- _Note:_ some Intents still use **ReturnsValue** without a concrete type; audit these

### Share Extension (UI)
- Presents an action picker that includes **Auto Detect** (default)
- Falls back to **Vision OCR** for images

### Action Extension (UI)
- Uses **SAActionPanelView** with the four manual actions _(no Auto Detect)_

### Safari Web Extension
- Popup shows the four actions
- Native handler supports those four only _(no `autoDetect` message)_

### Shortcuts
- Exposes the four actions; **Auto Detect isn’t on the tiles yet**

### Storage & exports
- App Group helper in place
- CSV writes to **Exports/** under the group (or temp for extensions)

### Onboarding
- Share-sheet pinning flow is wired

**Delta since last plan:**  
Auto-Detect engine + intent are in, and **Share Extension** can use it. **App UI**, **Action Extension**, **Safari Web Extension**, and **Shortcuts** still show only the four manual actions.

---

## Advanced features (specs) still to implement

**A) Finish wiring Auto Detect everywhere**  
_User story:_ One-tap “Do the right thing” from any surface.  
_Surfaces:_ App toolbar, Action Extension panel, Safari popup/handler, Shortcuts tile.  
_Tech:_ Add “Auto Detect” button to `ContentView` and `SAActionPanelView`; add `autoDetect` to web popup + native handler; add `AppShortcut` for `AutoDetectIntent`.  
_Acceptance:_ Same text/image yields the same routed action on all four surfaces.

**B) Inline editors & previews**  
_User story:_ Edit before saving—event fields, reminder due, contact fields; preview CSV table.  
_Surfaces:_ App + Share/Action extensions.  
_Tech:_ SwiftUI sheets for each action; simple CSV table viewer with “Open in…”; pass edited values back into services.  
_Acceptance:_ “Edit first” path available for all four actions; Cancel cleanly returns.

**C) Rich Event Builder (tz, location, travel time)**  
_User story:_ Paste an invite; event gets correct time zone, location, optional travel time alert.  
_Tech:_ `MKLocalSearch` to geocode; tz from coordinates; Maps ETA for travel time; extend `AddToCalendarIntent` parameters.  
_Acceptance:_ Correct tz inferred for cross-zone text; location populated when geocodable.

**D) Flights & itineraries**  
_User story:_ “BA284 12 Oct 14:20” → event titled “BA284 LHR → SFO”, terminals/gate in notes.  
_Tech:_ Regex airline+flight; origin/destination from common patterns; time zone inference as in (C).  
_Acceptance:_ Recognises major IATA codes and builds a valid event.

**E) Bills & subscriptions (recurring reminders)**  
_User story:_ “£19.99 monthly due 3 Oct” → monthly reminder with amount/payee.  
_Tech:_ Currency + recurrence keywords → `EKRecurrenceRule`.  
_Acceptance:_ Correct monthly/annual recurrence for typical phrasing.

**F) Parcel tracking helper**  
_User story:_ Detect tracking numbers; offer carrier deep link; optional delivery-day reminder.  
_Tech:_ Pattern library (UPS/FedEx/DHL/Royal Mail/An Post).  
_Acceptance:_ ≥95% carrier classification on common formats.

**G) Receipt parser v2 (subtotal/tax/tip/total + categories)**  
_User story:_ Cleaner CSV (merchant, date, subtotal, tax, tip, total; optional line-item categories).  
_Tech:_ Extend `CSVExporter` with multi-currency amounts and field extraction; keep on-device.  
_Acceptance:_ Totals detected on ≥90% of clear receipts; CSV opens in Numbers/Excel without edits.

**H) PDF & multi-page OCR**  
_User story:_ Share a 2-page invoice; app extracts all pages.  
_Tech:_ PDFKit rasterise → Vision OCR (OCR utilities already exist).  
_Acceptance:_ Good text recovery on typical invoices; runtime scales roughly linearly.

**I) Barcode & QR decoder (tickets/URLs/Wi-Fi)**  
_User story:_ Share/snap a boarding pass QR/PDF417 → decode and suggest actions.  
_Tech:_ Vision barcodes; schema handlers (URL, vCard, Wi-Fi).  
_Acceptance:_ Decodes standard QR/PDF417 at screenshot quality.

**J) Live camera “Scan Mode”**  
_User story:_ Point camera at poster/receipt; live chip suggests action.  
_Tech:_ `DataScannerViewController` (text + barcodes) → reuse router.  
_Acceptance:_ Sub-second classification on iPhone 12+.

**K) History & Undo**  
_User story:_ See last 20 actions; undo an event/reminder within 24h.  
_Tech:_ Persist light entries in App Group; reverse via EventKit/CNContact deletes where safe.  
_Acceptance:_ Undo works immediately after creation; deep link opens the created item.

**L) Safari extension upgrades**  
_User story:_ Right-click text → “Screen Actions → [Auto/Event/Reminder/Contact/Receipt]”; optional page screenshot when no selection.  
_Tech:_ Add `contextMenus`; tab capture; add `autoDetect` route in handler.  
_Acceptance:_ Context menu mirrors popup actions and Auto Detect parity.

**M) Internationalisation & locale smarts**  
_User story:_ Dates/currencies/addresses parse correctly for en-IE/en-GB/en-US as a baseline.  
_Tech:_ Respect `Locale.current`; currency symbols; address formatting via Contacts.  
_Acceptance:_ Happy-path tests pass for the three locales.

**N) Reliability & UX polish**  
_User story:_ Clear success/failure messages; no dead ends.  
_Tech:_ Unify service calls (avoid mixing `.shared` vs static), add consistent error dialogs, copyable error details, OSLog categories.  
_Acceptance:_ Clean build (no generic-type warnings in Intents), crash-free on fuzzed inputs, consistent toasts.

---

## Suggested sequencing

**Next patch:** (A) Wire **Auto Detect** across App, Action Extension, Safari popup/handler, and Shortcuts.  
**Then:** (B) Inline editors → (C)+(D) event/flight enrichments → (G)+(H) receipts/PDF → (K)+(L) history + Safari upgrades → (M)+(N) locale + reliability.
