//
//  ContentView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import SwiftUI

struct ContentView: View {
    @State private var inputText: String = """
Pick up dry cleaning on Friday 5pm, call Sarah +44 7700 900123, email sarah@example.com
Invoice #2211 Total €48.90
"""
    @State private var status: String = "Ready"

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                TextEditor(text: $inputText)
                    .frame(minHeight: 180)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary))
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button("Add to Calendar") {
                            Task {
                                do {
                                    let text = inputText
                                    let result = try await AddToCalendarIntent.runStandalone(text: text)
                                    status = result
                                } catch {
                                    status = "Calendar error: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Create Reminder") {
                            Task {
                                do {
                                    let text = inputText
                                    let result = try await CreateReminderIntent.runStandalone(text: text)
                                    status = result
                                } catch {
                                    status = "Reminders error: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Extract Contact") {
                            Task {
                                do {
                                    let text = inputText
                                    let result = try await ExtractContactIntent.runStandalone(text: text)
                                    status = result
                                } catch {
                                    status = "Contacts error: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.bordered)

                        Button("Receipt → CSV") {
                            Task {
                                do {
                                    let text = inputText
                                    let (msg, _) = try await ReceiptToCSVIntent.runStandalone(text: text)
                                    status = msg
                                } catch {
                                    status = "CSV error: \(error.localizedDescription)"
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                }

                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Screen Actions")
        }
    }
}
