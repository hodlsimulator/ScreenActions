//
//  ReceiptCSVPreviewView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Preview + edit receipt items. Seeds from an image via Vision on iOS 26.
//

import SwiftUI
import UIKit

private struct ReceiptItem: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var amount: String
}

@MainActor
public struct ReceiptCSVPreviewView: View {
    @State private var items: [ReceiptItem]
    @State private var isExporting = false
    @State private var error: String?
    @State private var shareURL: URL?
    @State private var seededFromImage = false
    @State private var smudgeNote: String?

    public let onCancel: () -> Void
    public let onExported: (String) -> Void

    private let sourceImageData: Data?

    public init(sourceText: String,
                sourceImageData: Data? = nil,
                onCancel: @escaping () -> Void,
                onExported: @escaping (String) -> Void) {
        _items = State(initialValue: Self.parseItems(from: sourceText))
        self.sourceImageData = sourceImageData
        self.onCancel = onCancel
        self.onExported = onExported
    }

    private var canExport: Bool {
        if isExporting { return false }
        if items.isEmpty { return false }
        let allBlank = items.allSatisfy {
            $0.title.trimmingCharacters(in: .whitespaces).isEmpty &&
            $0.amount.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !allBlank
    }

    public var body: some View {
        NavigationView {
            Form {
                Section("Items") {
                    if items.isEmpty {
                        Text("No lines detected.\nAdd a few below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($items) { $it in
                        HStack {
                            TextField("Item", text: $it.title)
                            TextField("Amount", text: $it.amount)
                                .keyboardType(.numbersAndPunctuation)
                                .frame(width: 120)
                        }
                    }
                    .onDelete { idx in items.remove(atOffsets: idx) }
                    Button { items.append(.init(title: "", amount: "")) } label: {
                        Label("Add line", systemImage: "plus.circle")
                    }
                }

                Section("Preview (CSV)") {
                    ScrollView {
                        Text(makeCSV())
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                if seededFromImage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.viewfinder")
                            Text("Seeded from document image")
                            if let smudgeNote { Spacer(); Text(smudgeNote).foregroundStyle(.secondary) }
                        }
                        .font(.footnote)
                    }
                }
            }
            .navigationTitle("Receipt → CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button { Task { await exportCSV(openShare: false) } } label: {
                            Label("Export CSV", systemImage: "square.and.arrow.down")
                        }
                        Button { Task { await exportCSV(openShare: true) } } label: {
                            Label("Export & Open In…", systemImage: "square.and.arrow.up")
                        }
                    } label: { Text("Export") }
                    .disabled(!canExport)
                }
            }
            .overlay(alignment: .center) { if isExporting { ProgressView().scaleEffect(1.2) } }
            .sheet(item: Binding(
                get: { shareURL.map { ShareWrapper(url: $0) } },
                set: { shareURL = $0?.url }
            )) { share in
                InlineActivityView(activityItems: [share.url])
            }
            .task {
                if let data = sourceImageData {
                    if #available(iOS 26, *) {
                        do {
                            var smudge: VisionDocumentReader.SmudgeHint?
                            let csv = try await VisionDocumentReader.receiptCSV(from: data, smudgeHint: &smudge)
                            if !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                items = Self.parseCSVToItems(csv)
                                seededFromImage = true
                                if let s = smudge, s.isLikely { smudgeNote = "Lens looked smudged." }
                            }
                        } catch { /* keep text-seeded items */ }
                    }
                }
            }
        }
    }

    // MARK: Export

    private func exportCSV(openShare: Bool) async {
        error = nil; isExporting = true; defer { isExporting = false }
        do {
            let csv = makeCSV()
            let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
            let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
            onExported("CSV exported (\(url.lastPathComponent)).")
            if openShare { shareURL = url }
        } catch { self.error = error.localizedDescription }
    }

    private func makeCSV() -> String {
        var out = "Item,Amount\n"
        for it in items {
            let safeTitle = it.title.replacingOccurrences(of: "\"", with: "\"\"")
            if it.amount.trimmingCharacters(in: .whitespaces).isEmpty {
                out += "\"\(safeTitle)\"\n"
            } else {
                out += "\"\(safeTitle)\",\(it.amount)\n"
            }
        }
        return out
    }

    // MARK: Parsing helpers

    private static func parseItems(from text: String) -> [ReceiptItem] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let pattern = #"([€£$])\s?([0-9]+(?:\.[0-9]{2})?)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        return lines.map { line in
            var amount = ""
            if let regex {
                let ns = line as NSString
                let range = NSRange(location: 0, length: ns.length)
                if let m = regex.firstMatch(in: line, options: [], range: range), m.numberOfRanges >= 3 {
                    let sym = ns.substring(with: m.range(at: 1))
                    let amt = ns.substring(with: m.range(at: 2))
                    amount = "\(sym)\(amt)"
                }
            }
            return ReceiptItem(title: line, amount: amount)
        }
    }

    private static func parseCSVToItems(_ csv: String) -> [ReceiptItem] {
        var out: [ReceiptItem] = []
        let lines = csv.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() {
            if idx == 0 { continue } // header
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            // naive split for "Item,Amount" with quoted item
            if trimmed.hasPrefix("\""), let end = trimmed.dropFirst().firstIndex(of: "\"") {
                let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
                let after = trimmed[trimmed.index(end, offsetBy: 2)...] // skip ","
                out.append(.init(title: name, amount: String(after)))
            } else {
                out.append(.init(title: trimmed, amount: ""))
            }
        }
        return out
    }

    private struct ShareWrapper: Identifiable { let id = UUID(); let url: URL }
}

private struct InlineActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
