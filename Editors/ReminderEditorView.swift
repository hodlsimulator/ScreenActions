//
//  ReminderEditorView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Inline editor for reminders, prepopulated from text.
//  Saves via RemindersService.
//

import SwiftUI

@MainActor
public struct ReminderEditorView: View {
    @State private var title: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var notes: String

    @State private var isSaving = false
    @State private var error: String?

    public let onCancel: () -> Void
    public let onSaved: (String) -> Void

    public init(sourceText: String, onCancel: @escaping () -> Void, onSaved: @escaping (String) -> Void) {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _title = State(initialValue: firstLine.isEmpty ? "Todo" : (firstLine.count > 64 ? String(firstLine.prefix(64)) : firstLine))

        if let r = DateParser.firstDateRange(in: trimmed) {
            _hasDue = State(initialValue: true)
            _due = State(initialValue: r.start)
        } else {
            _hasDue = State(initialValue: false)
            _due = State(initialValue: Date().addingTimeInterval(60 * 60))
        }
        _notes = State(initialValue: trimmed)

        self.onCancel = onCancel
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Due", selection: $due, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .font(.body)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("New Reminder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
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
            let id = try await RemindersService.shared.addReminder(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                due: hasDue ? due : nil,
                notes: notes.isEmpty ? nil : notes
            )
            onSaved("Reminder created (\(id)).")
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
