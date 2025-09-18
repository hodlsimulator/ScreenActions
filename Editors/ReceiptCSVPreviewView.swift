//
//  ReceiptCSVPreviewView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Preview + edit receipt items. Seeds from an image via Vision on iOS 26.

import SwiftUI
import UIKit

@MainActor
public struct ReceiptCSVPreviewView: View {
    public let sourceText: String
    public let sourceImageData: Data?
    public let onCancel: () -> Void
    public let onExported: (String) -> Void

    @State private var input: String
    @State private var csv: String = ""
    @State private var error: String?

    // Primary initialiser (used by the Share Extension and by the app when passing an image)
    public init(
        sourceText: String,
        sourceImageData: Data?,
        onCancel: @escaping () -> Void,
        onExported: @escaping (String) -> Void
    ) {
        self.sourceText = sourceText
        self.sourceImageData = sourceImageData
        self.onCancel = onCancel
        self.onExported = onExported
        _input = State(initialValue: sourceText)
    }

    // Convenience initialiser (keeps your existing app call site compiling)
    public init(
        sourceText: String,
        onCancel: @escaping () -> Void,
        onExported: @escaping (String) -> Void
    ) {
        self.init(
            sourceText: sourceText,
            sourceImageData: nil,
            onCancel: onCancel,
            onExported: onExported
        )
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Form {
                    Section("Input") {
                        TextEditor(text: $input)
                            .frame(minHeight: 160)
                            .font(.body)

                        HStack {
                            Button("Re-parse") { parse() }

                            if let data = sourceImageData {
                                Button {
                                    Task { await parseFromImage(data) }
                                } label: {
                                    Label("Parse From Image", systemImage: "doc.viewfinder")
                                }
                            }
                        }
                    }

                    Section("CSV Preview") {
                        ScrollView {
                            Text(csv.isEmpty ? "—" : csv)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(minHeight: 160)
                    }

                    if let error {
                        Section { Text(error).foregroundStyle(.red).font(.footnote) }
                    }
                }

                HStack {
                    Button("Cancel", role: .cancel, action: onCancel)
                    Spacer()
                    Button("Export CSV") { Task { await export() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .navigationTitle("Receipt → CSV")
            .onAppear { parse() }
        }
    }

    // MARK: - Actions

    private func parse() {
        error = nil
        csv = CSVExporter.makeReceiptCSV(from: input)
    }

    private func parseFromImage(_ data: Data) async {
        do {
            if #available(iOS 26, *) {
                var hint: VisionDocumentReader.SmudgeHint?
                let out = try await VisionDocumentReader.receiptCSV(from: data, smudgeHint: &hint)
                csv = out
            } else {
                error = "Requires iOS 26."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func export() async {
        do {
            let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
            let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
            UIPasteboard.general.url = url
            onExported("CSV exported (\(url.lastPathComponent)).")
        } catch {
            self.error = error.localizedDescription
        }
    }
}
