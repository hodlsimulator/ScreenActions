//
//  ReceiptToCSVIntent.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import AppIntents

struct ReceiptToCSVIntent: AppIntent {
    static var title: LocalizedStringResource { "Receipt → CSV" }
    static var description: IntentDescription {
        IntentDescription("Scans text or an image of a receipt and returns a CSV file with line items and detected amounts.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text")
    var text: String?

    @Parameter(title: "Image")
    var image: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let sourceText: String
        if let t = text, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sourceText = t
        } else {
            sourceText = try TextExtractor.from(imageFile: image)
        }

        guard !sourceText.isEmpty else {
            throw $text.needsValueError("Provide text or an image with text.")
        }

        let csv = CSVExporter.makeReceiptCSV(from: sourceText)
        let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
        let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
        let file = IntentFile(fileURL: url)
        return .result(value: file, dialog: "CSV exported.")
    }
}

extension ReceiptToCSVIntent {
    @MainActor
    static func runStandalone(text: String) async throws -> (String, URL) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("Provide text first.", AppStorageService.shared.containerURL()) }
        let csv = CSVExporter.makeReceiptCSV(from: trimmed)
        let filename = AppStorageService.shared.nextExportFilename(prefix: "receipt", ext: "csv")
        let url = try CSVExporter.writeCSVToAppGroup(filename: filename, csv: csv)
        return ("CSV exported.", url)
    }
}
