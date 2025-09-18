//
//  ReceiptCSVPreviewView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Preview + edit receipt items. Seeds from an image via Vision on iOS 26.

import SwiftUI
import UniformTypeIdentifiers

@MainActor
public struct ReceiptCSVPreviewView: View {
    public let sourceText: String
    public let sourceImageData: Data?
    public let onCancel: () -> Void
    public let onExported: (String) -> Void

    @State private var input: String
    @State private var csv: String = ""
    @State private var error: String?

    // File exporter state (single primary button uses this)
    @State private var showFileExporter = false
    @State private var exporterFilename: String = "receipt.csv"

    // Primary initialiser (used by Share Extension and app)
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

    // Convenience initialiser (keeps existing call sites)
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
                        Section {
                            Text(error).foregroundStyle(.red).font(.footnote)
                        }
                    }
                }

                // Actions (single primary button)
                HStack {
                    Button("Cancel", role: .cancel, action: onCancel)

                    Spacer()

                    Button("Export CSV…") {
                        exporterFilename = AppStorageService.shared
                            .nextExportFilename(prefix: "receipt", ext: "csv")
                        showFileExporter = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .navigationTitle("Receipt → CSV")
            .onAppear { parse() }
            .fileExporter(
                isPresented: $showFileExporter,
                document: _InlineCSVDocument(text: csv),
                contentType: .commaSeparatedText,
                defaultFilename: exporterFilename
            ) { result in
                switch result {
                case .success(let url):
                    onExported("Saved to Files (\(url.lastPathComponent)).")
                case .failure(let err):
                    self.error = err.localizedDescription
                }
            }
        }
    }

    // MARK: - Actions

    private func parse() {
        error = nil
        csv = CSVExporter.makeReceiptCSV(from: $input.wrappedValue)
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
}

// MARK: - Inline FileDocument (no target-membership gotchas)

private struct _InlineCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText, .plainText, .utf8PlainText, .text]
    }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let s = String(data: data, encoding: .utf8) {
            self.text = s
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}
