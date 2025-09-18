//
//  ReceiptToCSVIntent.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//
//  iOS 26: prefers Vision document tables when an image is supplied.
//

import AppIntents

struct ReceiptToCSVIntent: AppIntent {
    static var title: LocalizedStringResource { "Receipt → CSV" }
    static var description: IntentDescription {
        IntentDescription("Scans text or a photo/screenshot of a receipt and returns a CSV of line items.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text")
    var text: String?

    @Parameter(title: "Image")
    var image: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> & ProvidesDialog {
        // Text-only path (fast path).
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let csv = CSVExporter.makeReceiptCSV(from: t)
            let url = try write(csv: csv)
            return .result(value: IntentFile(fileURL: url), dialog: "CSV exported.")
        }

        // Image path → prefer Vision documents on iOS 26; else fallback to OCR.
        if let data = image?.data {
            if #available(iOS 26, *) {
                var _hint: VisionDocumentReader.SmudgeHint?
                let csv = try await VisionDocumentReader.receiptCSV(from: data, smudgeHint: &_hint)
                let url = try write(csv: csv)
                return .result(value: IntentFile(fileURL: url), dialog: "CSV exported.")
            } else {
                let text = try TextExtractor.from(imageFile: image)
                guard !text.isEmpty else { throw $text.needsValueError("Provide text or an image with text.") }
                let csv = CSVExporter.makeReceiptCSV(from: text)
                let url = try write(csv: csv)
                return .result(value: IntentFile(fileURL: url), dialog: "CSV exported.")
            }
        }

        throw $text.needsValueError("Provide text or an image with text.")
    }

    // MARK: - Helpers

    @MainActor
    private func write(csv: String) throws -> URL {
        let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
        return try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
    }
}

extension ReceiptToCSVIntent {
    @MainActor
    static func runStandalone(text: String) async throws -> (String, URL) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("Provide text first.", AppStorageService.shared.containerURL())
        }
        let csv = CSVExporter.makeReceiptCSV(from: trimmed)
        let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
        let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
        return ("CSV exported.", url)
    }
}
