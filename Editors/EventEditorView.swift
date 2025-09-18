//  EventEditorView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Updated: 17/09/2025 – Geofencing UI + iOS 17+ onChange fix.
//  Updated: 17/09/2025 – Persist last-used alert minutes via AppStorageService.
//

import SwiftUI
import CoreLocation
import MapKit

@MainActor
public struct EventEditorView: View {
    @EnvironmentObject private var pro: ProStore

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
    @State private var geoRadius: Double = 150

    // UI state
    @State private var isSaving = false
    @State private var error: String?

    // Permission explainer
    @State private var showLocationExplainer = false
    private let locationManager = CLLocationManager()

    @State private var showPaywall = false

    public let onCancel: () -> Void
    public let onSaved: (String) -> Void

    public init(sourceText: String, onCancel: @escaping () -> Void, onSaved: @escaping (String) -> Void) {
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
        let firstLine = trimmed.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let initialTitle = firstLine.isEmpty ? "Event" : (firstLine.count > 64 ? String(firstLine.prefix(64)) : firstLine)
        _title = State(initialValue: initialTitle)

        // Notes
        _notes = State(initialValue: trimmed)

        // Location hint
        let hint = CalendarService.firstLocationHint(in: trimmed) ?? ""
        _location = State(initialValue: hint)
        _inferTZ  = State(initialValue: !hint.isEmpty) // infer if we already have a place

        // Alert default (0 = None)
        _alertMinutes = State(initialValue: AppStorageService.getDefaultAlertMinutes())

        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                }

                Section("Location") {
                    TextField("Place or address (optional)", text: $location)
                        .textInputAutocapitalization(.words)
                    Toggle("Infer time zone from location", isOn: $inferTZ)
                        .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Geofencing") {
                    Toggle("Notify on arrival", isOn: $geoNotifyOnArrival)
                        .onChange(of: geoNotifyOnArrival) { _, new in if new { promptAlwaysLocationExplainer() } }
                    Toggle("Notify on departure", isOn: $geoNotifyOnDeparture)
                        .onChange(of: geoNotifyOnDeparture) { _, new in if new { promptAlwaysLocationExplainer() } }

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

                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay { if isSaving { ProgressView().scaleEffect(1.2) } }
            .alert("Allow “Always” Location?", isPresented: $showLocationExplainer) {
                Button("Not now", role: .cancel) { }
                Button("Continue") { requestAlwaysLocation() }
            } message: {
                Text("""
                To notify when you arrive or leave an event location, Screen Actions needs “Always & When In Use” access to your location.
                You can change this any time in Settings.
                """)
            }
            .sheet(isPresented: $showPaywall) { ProPaywallView().environmentObject(pro) }
        }
    }

    // MARK: - Save
    private func save() async {
        error = nil; isSaving = true; defer { isSaving = false }

        // Build geofencing (nil if none selected)
        let geofenceProx: GeofencingManager.GeofenceProximity? = {
            var p: GeofencingManager.GeofenceProximity = []
            if geoNotifyOnArrival { p.insert(.enter) }
            if geoNotifyOnDeparture { p.insert(.exit) }
            return p.isEmpty ? nil : p
        }()

        // Gate: only when geofencing is requested (1/day free)
        if geofenceProx != nil {
            let gate = QuotaManager.consume(feature: .geofencedEventCreation, isPro: pro.isPro)
            guard gate.allowed else {
                self.error = gate.message
                self.showPaywall = true
                return
            }
        }

        do {
            let id = try await CalendarService.shared.addEvent(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                start: start, end: end, notes: notes.isEmpty ? nil : notes,
                locationHint: location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location,
                inferTimeZoneFromLocation: inferTZ,
                alertMinutesBefore: alertMinutes == 0 ? nil : alertMinutes,
                travelTimeAlarm: false,
                transport: .automobile,
                geofenceProximity: geofenceProx,
                geofenceRadius: clampRadius(geoRadius)
            )
            if alertMinutes > 0 { AppStorageService.setDefaultAlertMinutes(alertMinutes) }
            onSaved("Event created (\(id)).")
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Helpers
    private func promptAlwaysLocationExplainer() {
        if !showLocationExplainer { showLocationExplainer = true }
    }
    private func requestAlwaysLocation() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.locationManager.requestAlwaysAuthorization() }
        case .authorizedWhenInUse, .authorizedAlways, .restricted, .denied:
            locationManager.requestAlwaysAuthorization()
        @unknown default:
            locationManager.requestAlwaysAuthorization()
        }
    }
    private func clampRadius(_ r: Double) -> Double { max(50, min(r, 2000)) }
}
