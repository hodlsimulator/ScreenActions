//  EventEditorView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//  Updated: 17/09/2025 – Geofencing UI (arrival/departure + radius) with brief permission explainer.
//  Updated: 17/09/2025 – Fix: iOS 17+ onChange(two-param), MapKit import for .automobile, use instance authorizationStatus.
//
//  Inline editor for calendar events used by the app & extensions.
//  Prepopulates from pasted text and DateParser.firstDateRange.
//  Saves via CalendarService (rich builder).

import SwiftUI
import CoreLocation
import MapKit

@MainActor
public struct EventEditorView: View {
    // Editable fields
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var notes: String

    // Rich options
    @State private var location: String
    @State private var inferTZ: Bool
    @State private var alertMinutes: Int

    // Geofencing UI
    @State private var geoNotifyOnArrival: Bool = false
    @State private var geoNotifyOnDeparture: Bool = false
    @State private var geoRadius: Double = 150 // metres; clamped 50…2000 on save

    // UI state
    @State private var isSaving = false
    @State private var error: String?

    // Permission explainer
    @State private var showLocationExplainer = false
    private let locationManager = CLLocationManager()

    // Callbacks
    public let onCancel: () -> Void
    public let onSaved: (String) -> Void

    public init(sourceText: String,
                onCancel: @escaping () -> Void,
                onSaved: @escaping (String) -> Void) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Dates
        let defaultStart = Date()
        let defaultEnd = defaultStart.addingTimeInterval(60 * 60)
        if let range = DateParser.firstDateRange(in: trimmed) {
            _start = State(initialValue: range.start)
            _end = State(initialValue: range.end)
        } else {
            _start = State(initialValue: defaultStart)
            _end = State(initialValue: defaultEnd)
        }

        // Title
        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initialTitle = firstLine.isEmpty ? "Event" : (firstLine.count > 64 ? String(firstLine.prefix(64)) : firstLine)
        _title = State(initialValue: initialTitle)

        // Notes
        _notes = State(initialValue: trimmed)

        // Location hint (extract from text if possible)
        let hint = CalendarService.firstLocationHint(in: trimmed) ?? ""
        _location = State(initialValue: hint)
        _inferTZ = State(initialValue: !hint.isEmpty) // infer if we already have a place

        // Alert
        _alertMinutes = State(initialValue: 0)

        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)

                    DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])

                    DatePicker("Ends",
                               selection: $end,
                               in: start...,
                               displayedComponents: [.date, .hourAndMinute])
                }

                Section("Location") {
                    TextField("Place or address (optional)", text: $location)
                        .textInputAutocapitalization(.words)

                    Toggle("Infer time zone from location", isOn: $inferTZ)
                        .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Geofencing") {
                    Toggle("Notify on arrival", isOn: $geoNotifyOnArrival)
                        .onChange(of: geoNotifyOnArrival) { _, new in
                            if new { promptAlwaysLocationExplainer() }
                        }

                    Toggle("Notify on departure", isOn: $geoNotifyOnDeparture)
                        .onChange(of: geoNotifyOnDeparture) { _, new in
                            if new { promptAlwaysLocationExplainer() }
                        }

                    if geoNotifyOnArrival || geoNotifyOnDeparture {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Radius")
                                Spacer()
                                Text("\(Int(geoRadius)) m")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $geoRadius, in: 50...2000, step: 50)

                            if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Add a place above to use geofencing.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Section("Alert") {
                    Picker("Alert", selection: $alertMinutes) {
                        Text("None").tag(0)
                        Text("5 minutes before").tag(5)
                        Text("10 minutes before").tag(10)
                        Text("15 minutes before").tag(15)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 140)
                        .font(.body)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView().scaleEffect(1.2)
                }
            }
            .alert("Allow “Always” Location?", isPresented: $showLocationExplainer) {
                Button("Not now", role: .cancel) { }
                Button("Continue") { requestAlwaysLocation() }
            } message: {
                Text("To notify when you arrive or leave an event location, Screen Actions needs “Always & When In Use” access to your location. You can change this any time in Settings.")
            }
        }
    }

    // MARK: - Save

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }

        do {
            // Build geofencing option set (nil if no toggle selected)
            let geofenceProx: GeofencingManager.GeofenceProximity? = {
                var p: GeofencingManager.GeofenceProximity = []
                if geoNotifyOnArrival { p.insert(.enter) }
                if geoNotifyOnDeparture { p.insert(.exit) }
                return p.isEmpty ? nil : p
            }()

            let id = try await CalendarService.shared.addEvent(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                start: start,
                end: end,
                notes: notes.isEmpty ? nil : notes,
                locationHint: location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location,
                inferTimeZoneFromLocation: inferTZ,
                alertMinutesBefore: alertMinutes == 0 ? nil : alertMinutes,
                travelTimeAlarm: false,
                transport: .automobile,
                geofenceProximity: geofenceProx,
                geofenceRadius: clampRadius(geoRadius)
            )

            onSaved("Event created (\(id)).")
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func promptAlwaysLocationExplainer() {
        // Only show once per editing session when a toggle is first enabled.
        if !showLocationExplainer {
            showLocationExplainer = true
        }
    }

    private func requestAlwaysLocation() {
        // Best-effort: if never asked, request When In Use first, then Always.
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Nudge the Always prompt shortly after.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.locationManager.requestAlwaysAuthorization()
            }
        case .authorizedWhenInUse, .authorizedAlways, .restricted, .denied:
            locationManager.requestAlwaysAuthorization()
        @unknown default:
            locationManager.requestAlwaysAuthorization()
        }
    }

    private func clampRadius(_ r: Double) -> Double {
        return max(50, min(r, 2000))
    }
}
