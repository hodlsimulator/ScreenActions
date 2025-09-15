//
//  EventEditorView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//  Updated: 15/09/2025 – Location + time zone + alert controls
//
//  Inline editor for calendar events used by the app & extensions.
//  Prepopulates from pasted text and DateParser.firstDateRange.
//  Saves via CalendarService (rich builder).
//

import SwiftUI

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

    // UI state
    @State private var isSaving = false
    @State private var error: String?

    // Callbacks
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
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                }

                Section("Location") {
                    TextField("Place or address (optional)", text: $location)
                        .textInputAutocapitalization(.words)
                    Toggle("Infer time zone from location", isOn: $inferTZ)
                        .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .overlay {
                if isSaving { ProgressView().scaleEffect(1.2) }
            }
        }
    }

    private func save() async {
        error = nil
        isSaving = true
        do {
            let id = try await CalendarService.shared.addEvent(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                start: start,
                end: end,
                notes: notes.isEmpty ? nil : notes,
                locationHint: location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : location,
                inferTimeZoneFromLocation: inferTZ,
                alertMinutesBefore: alertMinutes == 0 ? nil : alertMinutes
            )
            onSaved("Event created (\(id)).")
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
