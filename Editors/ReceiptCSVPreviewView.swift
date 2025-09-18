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
    @EnvironmentObject private var pro: ProStore

    @State private var items: [ReceiptItem]
    @State private var isExporting = false
    @State private var error: String?
    @State private var shareURLWrapper: ShareWrapper?
    @State private var seededFromImage = false
    @State private var smudgeNote: String?
    @State private var showPaywall = false

    public let onCancel: () -> Void
    public let onExported: (String) -> Void

    private let sourceImageData: Data?

    public init(sourceText: String, sourceImageData: Data? = nil, onCancel: @escaping () -> Void, onExported: @escaping (String) -> Void) {
        _items = State(initialValue: Self.parseItems(from: sourceText))
        self.sourceImageData = sourceImageData
        self.onCancel = onCancel
        self.onExported = onExported
    }

    private var canExport: Bool {
        guard !isExporting, !items.isEmpty else { return false }
        let allBlank = items.allSatisfy { $0.title.trimmingCharacters(in: .whitespaces).isEmpty && $0.amount.trimmingCharacters(in: .whitespaces).isEmpty }
        return !allBlank
    }

    public var body: some View {
        NavigationStack {
            Form {
                itemsSection
                previewSection
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
                if seededFromImage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.viewfinder")
                            Text("Seeded from document image")
                            if let s = smudgeNote { Spacer(); Text(s).foregroundStyle(.secondary) }
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
                        Button { Task { await exportCSV(openShare: false) } } label: { Label("Export CSV", systemImage: "square.and.arrow.down") }
                        Button { Task { await exportCSV(openShare: true) } } label: { Label("Export & Open In…", systemImage: "square.and.arrow.up") }
                    } label: { Text("Export") }
                        .disabled(!canExport)
                }
            }
            .overlay(alignment: .center) { if isExporting { ProgressView().scaleEffect(1.2) } }
            .sheet(item: $shareURLWrapper) { share in InlineActivityView(activityItems: [share.url]) }
            .sheet(isPresented: $showPaywall) { ProPaywallView().environmentObject(pro) }
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
            } label: { Label("Add line", systemImage: "plus.circle") }
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

    // MARK: Export with quota gate (3/day free)
    private func exportCSV(openShare: Bool) async {
        error = nil; isExporting = true; defer { isExporting = false }
        let gate = QuotaManager.consume(feature: .receiptCSVExport, isPro: pro.isPro)
        guard gate.allowed else {
            self.error = gate.message
            self.showPaywall = true
            return
        }
        do {
            let csv = makeCSV()
            let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
            let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
            onExported("CSV exported (\(url.lastPathComponent)).")
            if openShare { shareURLWrapper = ShareWrapper(url: url) }
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
        for (i, line) in csv.components(separatedBy: .newlines).enumerated() {
            if i == 0 { continue } // header
            let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            if s.hasPrefix("\""), let q = s.dropFirst().firstIndex(of: "\"") {
                let name = String(s[s.index(after: s.startIndex)..<q])
                let after = s[s.index(after: q)...]
                let parts = after.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                let amt = parts.count == 2 ? String(parts[1]) : ""
                out.append(ReceiptItem(title: name, amount: amt))
            } else {
                let parts = s.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                out.append(ReceiptItem(title: String(parts.first ?? ""), amount: parts.count == 2 ? String(parts[1]) : ""))
            }
        }
        return out
    }
}

// MARK: - Share sheet wrapper
private struct ShareWrapper: Identifiable { let id = UUID(); let url: URL }
private struct InlineActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
