# Screen Actions (iOS 26)

**Event-centric actions for iPhone — built and tested on _iOS 26_ with _Xcode 26_.**  
Add calendar events, create reminders, extract contacts, and turn receipts into CSV — from the app, the Share sheet, or the iOS Safari Web Extension.

> **iOS 26 prominence:** This project targets modern APIs (SwiftUI, App Intents) and ships first-class support for iOS 26. Geofencing is fully integrated into the event editor with an “Always” permission nudge aligned to current iOS guidance.

---

## Features

- **Auto-detect** useful bits from selected text: dates, addresses, phones, emails.  
- **Add to Calendar** with start/end, alerts, notes, and location.  
- **🆕 Geofencing for events (iOS 26-ready)**
  - Toggle **Notify on arrival** / **Notify on departure** per event.
  - Adjustable **radius** (50–2,000 m), clamped on save.
  - Offline-friendly: enter/exit uses GPS; only initial geocoding needs Internet.
  - Built-in explainer to request **Always & While Using** location access.
- **Create Reminder** quickly with due date and notes.  
- **Extract Contact** from selection into a contact card.  
- **Receipt → CSV** exporter.  
- **iOS Safari Web Extension** popup to run actions without leaving Safari.  
- **Settings → Request Location Access** to make the app appear in Location Services.

---

## Requirements

- **Xcode 26**  
- **iOS 17+** (developed and verified on **iOS 26**)  
- iPhone (device recommended for geofencing; Simulator supported for basic flows)

---

## Project Layout

```text
Screen Actions/                      # Main app (SwiftUI)
  Core/                              # Calendar/Reminders/Contacts/CSV/Parsing/Logging
  Intents/                           # App Intents for Shortcuts
  Resources/                         # Assets, Localizable.strings
  Screen_ActionsApp.swift
  SettingsView.swift                 # Includes “Request Location Access”
  Editors/                           # Event/Reminder/Contact/Receipt editors

ScreenActionsShareExtension/         # Share extension (UI + JS bridge)
ScreenActionsActionExtension/        # Optional action-style target

ScreenActionsWebExtension/           # iOS Safari Web Extension target
  WebRes/                            # manifest, background.js, popup.*, icons, locales
  SafariWebExtensionHandler.swift
```

---

## Build & Run (device recommended)

1. Open `Screen Actions.xcodeproj` in **Xcode 26**.  
2. Select **Screen Actions** scheme → **Run** on a physical iPhone.  
3. In the app, open **Settings → Location & Geofencing → Request Location Access**.  
   Grant **While Using** then **Always** (or switch to **Always** later in iOS Settings).  
4. (Optional) Enable the Safari Web Extension: **Settings → Safari → Extensions → Screen Actions**.

---

## Permissions & Capabilities

Ensure the app target’s **Info.plist** includes:

- `NSLocationWhenInUseUsageDescription`  
- `NSLocationAlwaysAndWhenInUseUsageDescription`

Recommended capability:

- **Background Modes** → **Location updates** (improves region event delivery when backgrounded).

---

## Geofencing (Arrival/Departure + Radius)

- Event editor: `Editors/EventEditorView.swift`
  - Toggles: **Notify on arrival**, **Notify on departure**
  - **Radius slider**: 50–2,000 m (saved value is clamped)
  - Enabling a toggle shows a brief explainer and requests **Always** access.
- Persists via:
  - `CalendarService.addEvent(... geofenceProximity:, geofenceRadius:)`

**Practical tips**

- Start with **150–300 m** for reliable testing.  
- Do **geocoding** (place name → coordinates) once on Wi-Fi; enter/exit works offline.  
- Don’t force-quit during tests; background is fine.  
- Core Location enforces a **~20 monitored regions per app** limit; rotate the nearest N if you scale up.

---

## Quick Testing (from the sofa)

### A) Best: Simulate on your **iPhone** via Xcode

1. Run the app on device (cable or wireless debugging).  
2. Create an event with a real **Location** (e.g. “Dublin Castle”), enable **Arrival/Departure**, set **Radius**, **Save**.  
3. Xcode → **Debug → Simulate Location** → choose an **Outside** GPX, then switch to **Inside** to simulate **arrival** (reverse for **departure**).

Add these GPX files anywhere in your project and select them from the Simulate Location menu.

```xml
<!-- dublin_castle_outside.gpx -->
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="ScreenActionsTest" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="53.3460" lon="-6.2800"><name>Dublin Castle Outside (~1km W)</name></wpt>
</gpx>
```

```xml
<!-- dublin_castle_inside.gpx -->
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="ScreenActionsTest" xmlns="http://www.topografix.com/GPX/1/1">
  <wpt lat="53.3430" lon="-6.2675"><name>Dublin Castle Inside</name></wpt>
</gpx>
```

```xml
<!-- dublin_castle_crossing.gpx (optional route: outside → inside) -->
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="ScreenActionsTest" xmlns="http://www.topografix.com/GPX/1/1">
  <trk><name>Outside to Inside</name><trkseg>
    <trkpt lat="53.346500" lon="-6.283500"></trkpt>
    <trkpt lat="53.345900" lon="-6.281900"></trkpt>
    <trkpt lat="53.345000" lon="-6.279000"></trkpt>
    <trkpt lat="53.344200" lon="-6.274500"></trkpt>
    <trkpt lat="53.343600" lon="-6.270500"></trkpt>
    <trkpt lat="53.343000" lon="-6.267500"></trkpt>
  </trkseg></trk>
</gpx>
```

### B) Simulator

Use the same GPX files via **Debug → Simulate Location** (device remains more faithful for region enter/exit).

---

## Troubleshooting

- **App not shown in Location Services**  
  Open the app’s **Settings** page and tap **Request Location Access** once; after granting, it will appear in iOS Location Services.

- **No enter/exit firing**
  - iOS **Settings → Screen Actions → Location**: ensure **Allow Location Access: Always** and **Precise Location: On**.
  - Use a larger radius (**150–300 m** to start).
  - Confirm the event’s location geocodes to a map pin before going offline.

- **Background delivery**  
  Works when backgrounded; avoid force-quitting during tests.

---

## iOS Safari Web Extension — packaging & signing (iOS 26-verified)

- iOS Safari has **no `contextMenus`/`menus` API**; expose actions via the **popup** and/or the **Share extension**.  
- **Native messaging on iOS** must originate from an extension page (popup/service worker), not a content script.  
- **Manifest path** in the extension **Info.plist** must point to the packed resources inside the `.appex`:
  - `NSExtensionAttributes → SFSafariWebExtensionManifestPath = WebRes/manifest.json`
- **Package `WebRes` inside the `.appex`** using **Copy Files (Resources)** on the extension target:
  - `WebRes/manifest.json`, `background.js`, `popup.html`, `popup.css`, `popup.js`
  - `WebRes/_locales/en/messages.json`
  - `WebRes/images/*` (all icons + `toolbar-icon.svg`)
- **Embed the appex** in the app target via **Embed Foundation Extensions** and add a **Target Dependency** on the extension.

### Entitlements & provisioning

- The extension must carry:
```text
com.apple.developer.extensionkit.extension-point-identifiers = ["com.apple.Safari.web-extension"]
```

- Reliable dev-profile recipe (iOS 26):
  1) Create a fresh iOS **Safari Extension** target (Xcode template).  
  2) Build to a physical device with **Automatic signing** to mint the profile containing the ExtensionKit entitlement.  
  3) If Xcode later picks a wildcard profile, switch the extension to **Manual** and pin the minted profile.

### Verify what’s embedded

```bash
# Adjust the path to your build products
codesign -d --entitlements :- \
"…/Build/Products/Debug-iphoneos/Screen Actions.app/PlugIns/ScreenActionsWebExtension.appex" | plutil -p -

/usr/libexec/PlistBuddy -c "Print :NSExtension" \
"…/ScreenActionsWebExtension.appex/Info.plist"
```

---

## Developer Notes

- If principal-class instantiation becomes fussy, an Objective-C principal (`SAWebExtensionHandler : NSObject <NSExtensionRequestHandling>`) that bridges into Swift is a proven fallback; current project uses a Swift principal (`SafariWebExtensionHandler.swift`).  
- Keep the extension `MinimumOSVersion` ≤ your device’s OS.  
- Core Location’s **~20 monitored regions per app** limit still applies; when scaling, rotate the nearest N regions in your `GeofencingManager`.

---

## Roadmap

- Region rotation/refresh for multiple upcoming events.  
- App Intents surface for Shortcuts (toggle arrival/departure for a selected event).  
- Optional travel-time alarms.

---

## Licence

Proprietary — © Conor Nolan. All rights reserved.
