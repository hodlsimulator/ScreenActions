# Screen Actions

Screen Actions is an iOS app with a Share Extension, an iOS Safari Web Extension, and optional Live Activity controls. It extracts useful data from the current page/selection (dates, contacts, receipts, etc.) and lets you act on it instantly: add Calendar events, create Reminders, extract Contacts, or export Receipts to CSV.

> Built and tested with **Xcode 26**. Targets modern iOS (17+). iPhone is the primary device.

---

## Features

- **Auto-detect**: quick parsing of selected text (dates, addresses, phone numbers, emails).
- **Add to Calendar**: inline editor with start/end, alerts, notes, location.
- **New: Geofencing for events**  
  - **Notify on arrival/departure** at the event’s location.  
  - Adjustable **radius** (50–2,000 m).  
  - Works offline once the location is resolved (enter/exit uses GPS).  
- **Create Reminder**: fast capture with due date and notes.
- **Extract Contact**: build a contact card from the page selection.
- **Receipt → CSV**: parse line items and share a CSV.
- **Safari Web Extension (iOS)**: popup UI to run the same actions without leaving Safari.
- **Settings → Request Location Access**: a simple way to trigger the iOS prompt so the app appears in Location Services.

---

## Project Layout

