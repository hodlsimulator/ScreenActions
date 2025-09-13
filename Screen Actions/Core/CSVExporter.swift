//
//  CSVExporter.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import Foundation

enum CSVExporter {
    static func makeReceiptCSV(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Raw-string regex for currency lines like "€12.34", "$ 9.99", "£100.00"
        let pattern = #"([€£$])\s?([0-9]+(?:\.[0-9]{2})?)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        var csv = "Item,Amount\n"

        for line in lines {
            var amountString = ""

            if let regex {
                let range = NSRange(location: 0, length: (line as NSString).length)
                if let match = regex.firstMatch(in: line, options: [], range: range), match.numberOfRanges >= 3 {
                    let sym = (line as NSString).substring(with: match.range(at: 1))
                    let amt = (line as NSString).substring(with: match.range(at: 2))
                    amountString = "\(sym)\(amt)"
                }
            }

            let safeItem = line.replacingOccurrences(of: ",", with: " ")
            if amountString.isEmpty {
                csv += "\"\(safeItem)\"\n"
            } else {
                csv += "\"\(safeItem)\",\(amountString)\n"
            }
        }

        return csv
    }

    static func writeCSVToAppGroup(filename: String, csv: String) throws -> URL {
        let base = AppStorageService.shared.containerURL().appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let url = base.appendingPathComponent(filename)

        guard let data = csv.data(using: .utf8) else {
            throw NSError(domain: "CSVExporter", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "UTF-8 encoding failed."])
        }

        try data.write(to: url, options: .atomic)
        return url
    }
}
