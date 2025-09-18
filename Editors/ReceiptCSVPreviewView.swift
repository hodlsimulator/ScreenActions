//
//  ReceiptCSVPreviewView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Preview + edit receipt items. Seeds from an image via Vision on iOS 26.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct ReceiptItem: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var amount: String
}

@MainActor
public struct ReceiptCSVPreviewView: View {
    @EnvironmentObject private var pro: ProStore

    @State private var items: [ReceiptItem]
    @State private var isExporting = false
    @State private var error: String?

    // Sharing state (stable, avoids instant dismissal)
    @State private var showShare = false
    @State private var shareURL: URL?

    // FileExporter (Save to Files…)
    @State private var showFileExporter = false
    @State private var exportDocument: CSVDocument?
    @State private var exportDefaultFilename = "receipt.csv"

    @State private var seededFromImage = false
    @State private var smudgeNote: String?
    @State private var showPaywall = false

    public let onCancel: () -> Void
    public let onExported: (String) -> Void
    private let sourceImageData: Data?

    public init(
        sourceText: String,
        sourceImageData: Data? = nil,
        onCancel: @escaping () -> Void,
        onExported: @escaping (String) -> Void
    ) {
        _items = State(initialValue: Self.parseItems(from: sourceText))
        self.sourceImageData = sourceImageData
        self.onCancel = onCancel
        self.onExported = onExported
    }

    private var canExport: Bool {
        guard !isExporting, !items.isEmpty else { return false }
        let allBlank = items.allSatisfy {
            $0.title.trimmingCharacters(in: .whitespaces).isEmpty &&
            $0.amount.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !allBlank
    }

    public var body: some View {
        NavigationStack {
            Form {
                itemsSection
                previewSection

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }

                if seededFromImage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.viewfinder")
                            Text("Seeded from document image")
                            if let s = smudgeNote {
                                Spacer()
                                Text(s).foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)
                    }
                }
            }
            .navigationTitle("Receipt → CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        // 1) Save directly to Files (user picks a folder they can find later)
                        Button {
                            let csv = makeCSV()
                            exportDefaultFilename = AppStorageService.shared
                                .nextExportFilename(prefix: "receipt", ext: "csv")
                            exportDocument = CSVDocument(text: csv)
                            showFileExporter = true
                        } label: {
                            Label("Save to Files…", systemImage: "externaldrive")
                        }

                        // 2) Share sheet (Mail, Notes, Messages, etc.)
                        Button {
                            Task { await exportCSVAndShare() }
                        } label: {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }

                        // 3) Background save to app's Exports area (for power users)
                        Button {
                            Task { await exportCSVToAppExports() }
                        } label: {
                            Label("Save to App Exports", systemImage: "square.and.arrow.down")
                        }
                    } label: { Text("Export") }
                    .disabled(!canExport)
                }
            }
            .overlay(alignment: .center) {
                if isExporting { ProgressView().scaleEffect(1.2) }
            }

            // Share sheet (stable boolean)
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }

            // System "Save to Files…" UI
            .fileExporter(
                isPresented: $showFileExporter,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: exportDefaultFilename
            ) { result in
                switch result {
                case .success(let url):
                    onExported("Saved to Files (\(url.lastPathComponent)).")
                case .failure(let err):
                    self.error = err.localizedDescription
                }
            }

            // Pro paywall if quota exhausted
            .sheet(isPresented: $showPaywall) {
                ProPaywallView().environmentObject(pro)
            }

            // Optional vision seeding
            .task {
                if let data = sourceImageData {
                    if #available(iOS 26, *) {
                        do {
                            var smudge: VisionDocumentReader.SmudgeHint?
                            let csv = try await VisionDocumentReader
                                .receiptCSV(from: data, smudgeHint: &smudge)
                            if !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                items = Self.parseCSVToItems(csv)
                                seededFromImage = true
                                if let s = smudge, s.isLikely {
                                    smudgeNote = "Lens looked smudged."
                                }
                            }
                        } catch {
                            /* keep text-seeded items */
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections split (keeps type-checker happy)

    private var itemsSection: some View {
        Section("Items") {
            if items.isEmpty {
                Text("No lines detected.\nAdd a few below.")
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(items.indices), id: \.self) { i in
                HStack {
                    TextField(
                        "Item",
                        text: Binding(
                            get: { items[i].title },
                            set: { items[i].title = $0 }
                        )
                    )

                    TextField(
                        "Amount",
                        text: Binding(
                            get: { items[i].amount },
                            set: { items[i].amount = $0 }
                        )
                    )
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
    }

    private var previewSection: some View {
        Section("Preview (CSV)") {
            ScrollView {
                let csv = makeCSV()
                Text(csv)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Export helpers (quota gate)

    private func gateOrShowPaywall() -> Bool {
        let gate = QuotaManager.consume(feature: .receiptCSVExport, isPro: pro.isPro)
        guard gate.allowed else {
            self.error = gate.message
            self.showPaywall = true
            return false
        }
        return true
    }

    /// Background save to app container (power users, not Files)
    private func exportCSVToAppExports() async {
        guard gateOrShowPaywall() else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let csv = makeCSV()
            let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
            let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
            onExported("Saved to App Exports (\(url.lastPathComponent)).")
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Write once, then open Share sheet (Mail / Messages / Notes / etc.)
    private func exportCSVAndShare() async {
        guard gateOrShowPaywall() else { return }
        isExporting = true
        defer { isExporting = false }

        do {
            let csv = makeCSV()
            let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
            let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
            onExported("CSV exported (\(url.lastPathComponent)).")
            self.shareURL = url
            self.showShare = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func makeCSV() -> String {
        var out = "Item,Amount\n"
        for it in items {
            let safeTitle = it.title.replacingOccurrences(of: "\"", with: "\"\"")
            let trimmedAmt = it.amount.trimmingCharacters(in: .whitespaces)
            if trimmedAmt.isEmpty {
                out += "\"\(safeTitle)\"\n"
            } else {
                out += "\"\(safeTitle)\",\(trimmedAmt)\n"
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

    private static func parseCSVToItems(_ csv: String) -> [ReceiptItem] {
        var out: [ReceiptItem] = []
        let rows = csv.components(separatedBy: .newlines)
        for (i, raw) in rows.enumerated() {
            if i == 0 { continue } // header
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }

            if s.hasPrefix("\"") {
                // Format: "name",amount  OR  "name","amount"
                var name = ""
                var rest = s.dropFirst()
                if let q = rest.firstIndex(of: "\"") {
                    name = String(rest[..<q])
                    rest = rest[rest.index(after: q)...]
                }
                let afterComma: Substring = {
                    if let c = rest.firstIndex(of: ",") {
                        return rest[rest.index(after: c)...]
                    }
                    return Substring("")
                }()
                let amt = String(afterComma).trimmingCharacters(in: .whitespaces)
                out.append(.init(title: name, amount: amt))
            } else {
                // name,amount   or just name
                let parts = s.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                let name = parts.first.map(String.init) ?? ""
                let amt = parts.count > 1 ? String(parts[1]) : ""
                out.append(.init(title: name, amount: amt))
            }
        }
        return out
    }
}
