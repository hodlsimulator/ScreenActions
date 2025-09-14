//
//  EventEditorView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Inline editor for calendar events used by the app & extensions.
//  Prepopulates from pasted text and DateParser.firstDateRange.
//  Saves via CalendarService.
//

import SwiftUI

@MainActor
public struct EventEditorView: View {
    // Editable fields
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var notes: String

    // UI state
    @State private var isSaving = false
    @State private var error: String?

    // Callbacks
    public let onCancel: () -> Void
    public let onSaved: (String) -> Void

    public init(sourceText: String, onCancel: @escaping () -> Void, onSaved: @escaping (String) -> Void) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultStart = Date()
        let defaultEnd = defaultStart.addingTimeInterval(60 * 60)

        if let range = DateParser.firstDateRange(in: trimmed) {
            _start = State(initialValue: range.start)
            _end = State(initialValue: range.end)
        } else {
            _start = State(initialValue: defaultStart)
            _end = State(initialValue: defaultEnd)
        }

        let firstLine = trimmed
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        _title = State(initialValue: firstLine.isEmpty ? "Event" : (firstLine.count > 64 ? String(firstLine.prefix(64)) : firstLine))
        _notes = State(initialValue: trimmed)

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
            .overlay { if isSaving { ProgressView().scaleEffect(1.2) } }
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
                notes: notes.isEmpty ? nil : notes
            )
            onSaved("Event created (\(id)).")
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
