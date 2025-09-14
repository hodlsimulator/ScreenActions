//
//  ReceiptCSVPreviewView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Editable preview of receipt items before exporting CSV.
//  Exports via CSVExporter.writeCSVToAppGroup and offers “Open in…”.
//

import SwiftUI
import UIKit

private struct ReceiptItem: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var amount: String // keep as string to support €, £, $ quickly
}

@MainActor
public struct ReceiptCSVPreviewView: View {
    @State private var items: [ReceiptItem]
    @State private var isExporting = false
    @State private var error: String?
    @State private var shareURL: URL?

    public let onCancel: () -> Void
    public let onExported: (String) -> Void

    public init(sourceText: String, onCancel: @escaping () -> Void, onExported: @escaping (String) -> Void) {
        _items = State(initialValue: Self.parseItems(from: sourceText))
        self.onCancel = onCancel
        self.onExported = onExported
    }

    // Break the heavy .disabled(...) condition into a fast computed var
    private var canExport: Bool {
        if isExporting { return false }
        if items.isEmpty { return false }
        // If every row is completely blank, disable
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
                        Text("No lines detected. Add a few below.")
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

                    Button {
                        items.append(.init(title: "", amount: ""))
                    } label: {
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
            }
            .navigationTitle("Receipt → CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button {
                            Task { await exportCSV(openShare: false) }
                        } label: { Label("Export CSV", systemImage: "square.and.arrow.down") }

                        Button {
                            Task { await exportCSV(openShare: true) }
                        } label: { Label("Export & Open In…", systemImage: "square.and.arrow.up") }
                    } label: { Text("Export") }
                    .disabled(!canExport)
                }
            }
            .overlay { if isExporting { ProgressView().scaleEffect(1.2) } }
            .sheet(item: Binding(
                get: { shareURL.map { ShareWrapper(url: $0) } },
                set: { shareURL = $0?.url }
            )) { share in
                InlineActivityView(activityItems: [share.url])
            }
        }
    }

    private func exportCSV(openShare: Bool) async {
        error = nil
        isExporting = true
        defer { isExporting = false }
        do {
            let csv = makeCSV()
            let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
            let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
            onExported("CSV exported (\(url.lastPathComponent)).")
            if openShare { shareURL = url }
        } catch {
            self.error = error.localizedDescription
        }
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
                if let m = regex.firstMatch(in: line, options: [], range: range),
                   m.numberOfRanges >= 3 {
                    let sym = ns.substring(with: m.range(at: 1))
                    let amt = ns.substring(with: m.range(at: 2))
                    amount = "\(sym)\(amt)"
                }
            }
            return ReceiptItem(title: line, amount: amount)
        }
    }

    private struct ShareWrapper: Identifiable {
        let id = UUID()
        let url: URL
    }
}

// Local share sheet so we don’t depend on ActivityView.swift
private struct InlineActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
