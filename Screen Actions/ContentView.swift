//
//  ContentView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  Target: iOS 26+ (system-driven Liquid Glass)
//

import SwiftUI

struct ContentView: View {
    @State private var inputText: String = ""
    @State private var status: String = "Ready"
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Input") {
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("Type or paste any text…")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .accessibilityHidden(true)
                        }

                        TextEditor(text: $inputText)
                            .frame(minHeight: 180)
                            .focused($isEditorFocused)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                            .font(.body)
                            .accessibilityLabel("Input text")
                    }
                }

                Section("Status") {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel("Status")
                }
            }
            .navigationTitle("Screen Actions")
            .toolbar {
                // Bottom actions — system will style these (Liquid Glass on iOS 26)
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        Task { await addToCalendar() }
                    } label: {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }

                    Button {
                        Task { await createReminder() }
                    } label: {
                        Label("Create Reminder", systemImage: "checkmark.circle.badge.plus")
                    }

                    Button {
                        Task { await extractContact() }
                    } label: {
                        Label("Extract Contact", systemImage: "person.crop.rectangle.badge.plus")
                    }

                    Button {
                        Task { await receiptToCSV() }
                    } label: {
                        Label("Receipt → CSV", systemImage: "doc.text.magnifyingglass")
                    }
                }

                // Keyboard toolbar for convenience
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditorFocused = false }
                }
            }
        }
    }

    // MARK: - Intent helpers

    private func addToCalendar() async {
        do {
            let result = try await AddToCalendarIntent.runStandalone(text: inputText)
            status = result
        } catch {
            status = "Calendar error: \(error.localizedDescription)"
        }
    }

    private func createReminder() async {
        do {
            let result = try await CreateReminderIntent.runStandalone(text: inputText)
            status = result
        } catch {
            status = "Reminders error: \(error.localizedDescription)"
        }
    }

    private func extractContact() async {
        do {
            let result = try await ExtractContactIntent.runStandalone(text: inputText)
            status = result
        } catch {
            status = "Contacts error: \(error.localizedDescription)"
        }
    }

    private func receiptToCSV() async {
        do {
            let (msg, _) = try await ReceiptToCSVIntent.runStandalone(text: inputText)
            status = msg
        } catch {
            status = "CSV error: \(error.localizedDescription)"
        }
    }
}
