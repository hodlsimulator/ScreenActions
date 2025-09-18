//
//  VisionDocumentReader.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//
//  iOS 26-only helper: on-device document reading (tables) + optional lens-smudge hint.
//  Tolerant to small SDK shape differences via reflection.
//

import Foundation
import Vision
import ImageIO
import CoreGraphics
import Contacts

#if canImport(DataDetection)
import DataDetection
#endif
#if canImport(DataDetector)
import DataDetector
#endif

@available(iOS 26, *)
enum VisionDocumentReader {

    // MARK: - Smudge hint

    struct SmudgeHint {
        let confidence: Float   // 0.0...1.0
        var isLikely: Bool { confidence >= 0.9 }
    }

    // MARK: - Public API

    static func receiptCSV(from imageData: Data,
                           smudgeHint: inout SmudgeHint?) async throws -> String {
        smudgeHint = await smudge(from: imageData)

        if let table = try await firstTable(in: imageData) {
            return csv(from: table)
        }

        let text = try ocrText(from: imageData)
        return CSVExporter.makeReceiptCSV(from: text)
    }

    static func contacts(from imageData: Data,
                         smudgeHint: inout SmudgeHint?) async throws -> [DetectedContact] {
        smudgeHint = await smudge(from: imageData)

        guard let document = try await recognizeDocument(on: imageData) else { return [] }

        if let table = firstTable(fromDocument: document) {
            var out: [DetectedContact] = []

            for row in table.rows {
                guard let firstCell = row.first else { continue }

                let rawName: String = String(firstCell.content.text.transcript)
                let name = rawName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

                var dc = DetectedContact()
                if !name.isEmpty {
                    let parts = name.split(separator: " ").map(String.init)
                    if parts.count >= 2 {
                        dc.givenName = parts.first
                        dc.familyName = parts.dropFirst().joined(separator: " ")
                    } else {
                        dc.givenName = parts.first
                    }
                }

                var emails = Set<String>()
                var phones = Set<String>()
                var postal: CNPostalAddress? = nil

                for cell in row {
                    // Prefer iOS 26 semantic matches when available.
                    #if canImport(DataDetection) || canImport(DataDetector)
                    let detected = cell.content.text.detectedData
                    for d in detected {
                        switch d.match.details {
                        case .emailAddress(let e):
                            emails.insert(e.emailAddress)
                        case .phoneNumber(let p):
                            phones.insert(p.phoneNumber)
                        case .postalAddress(let a):
                            if postal == nil {
                                let m = CNMutablePostalAddress()
                                m.street     = ddString(a, ["street","addressLine","streetAddress"]) ?? ""
                                m.city       = ddString(a, ["city","locality","town"]) ?? ""
                                m.state      = ddString(a, ["state","region","administrativeArea","province","county"]) ?? ""
                                m.postalCode = ddString(a, ["postalCode","zip","postcode"]) ?? ""
                                m.country    = ddString(a, ["country","countryCode","isoCountryCode"]) ?? ""
                                postal = m.copy() as? CNPostalAddress
                            }
                        default:
                            break
                        }
                    }
                    #endif

                    // Lightweight fallback so builds without DataDetection still get results.
                    let s: String = String(cell.content.text.transcript)

                    // E-mails
                    if let re = try? NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                                                         options: [.caseInsensitive]) {
                        let ns = s as NSString
                        let r  = NSRange(location: 0, length: ns.length)
                        re.enumerateMatches(in: s, options: [], range: r) { m,_,_ in
                            if let m { emails.insert(ns.substring(with: m.range)) }
                        }
                    }

                    // Phones
                    if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
                        let r = NSRange(s.startIndex..., in: s)
                        det.enumerateMatches(in: s, options: [], range: r) { m,_,_ in
                            if let m, let p = m.phoneNumber { phones.insert(p) }
                        }
                    }
                }

                dc.emails = Array(emails)
                dc.phones = Array(phones)
                dc.postalAddress = postal

                let has = (dc.givenName?.isEmpty == false) || (dc.familyName?.isEmpty == false)
                          || !dc.emails.isEmpty || !dc.phones.isEmpty || (dc.postalAddress != nil)
                if has { out.append(dc) }
            }
            return out
        }

        // No table → OCR then parse one contact as before.
        let text = try ocrText(from: imageData)
        let single = ContactParser.detect(in: text)
        let has = (single.givenName?.isEmpty == false) || (single.familyName?.isEmpty == false)
                  || !single.emails.isEmpty || !single.phones.isEmpty || (single.postalAddress != nil)
        return has ? [single] : []
    }

    // MARK: - Vision plumbing

    private static func recognizeDocument(on imageData: Data) async throws -> Vision.DocumentObservation? {
        let request = Vision.RecognizeDocumentsRequest()
        let result: Vision.RecognizeDocumentsRequest.Result = try await request.perform(on: imageData)
        let observations: [Vision.DocumentObservation] = result
        return observations.first
    }

    private static func firstTable(fromDocument document: Vision.DocumentObservation) -> Vision.DocumentObservation.Container.Table? {
        // Try direct `document.tables`
        if let direct: [Vision.DocumentObservation.Container.Table] =
            reflectGet(document, name: "tables", as: [Vision.DocumentObservation.Container.Table].self) {
            return direct.first
        }
        // Try `document.content.tables`
        if let content: Any = reflectGet(document, name: "content", as: Any.self) {
            if let nested: [Vision.DocumentObservation.Container.Table] =
                reflectGet(content, name: "tables", as: [Vision.DocumentObservation.Container.Table].self) {
                return nested.first
            }
        }
        return nil
    }

    private static func firstTable(in imageData: Data) async throws -> Vision.DocumentObservation.Container.Table? {
        guard let document = try await recognizeDocument(on: imageData) else { return nil }
        return firstTable(fromDocument: document)
    }

    // MARK: - CSV builder

    private static func csv(from table: Vision.DocumentObservation.Container.Table) -> String {
        var rows: [[String]] = []

        for row in table.rows {
            var cols: [String] = []
            for cell in row {
                let raw: String = String(cell.content.text.transcript)
                cols.append(csvQuote(raw))
            }
            rows.append(cols)
        }

        let columnCounts: [Int] = rows.map { $0.count }
        let maxCols: Int = columnCounts.max() ?? 0

        var out: [String] = []
        if maxCols == 2 { out.append("Item,Amount") }
        else if maxCols > 0 { out.append((1...maxCols).map { "Column \($0)" }.joined(separator: ",")) }

        for r in rows {
            var padded: [String] = r
            let toAdd: Int = Swift.max(0, maxCols - r.count)
            if toAdd > 0 { padded.append(contentsOf: Array(repeating: "\"\"", count: toAdd)) }
            out.append(padded.joined(separator: ","))
        }
        return out.joined(separator: "\n")
    }

    private static func csvQuote(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - Smudge detection

    private static func smudge(from imageData: Data) async -> SmudgeHint? {
        do {
            let obs: Vision.SmudgeObservation = try await Vision.DetectLensSmudgeRequest().perform(on: imageData)
            return SmudgeHint(confidence: obs.confidence)
        } catch {
            return nil
        }
    }

    // MARK: - OCR fallback

    private static func ocrText(from data: Data) throws -> String {
        let cf = data as CFData
        guard let src = CGImageSourceCreateWithData(cf, nil),
              let cg  = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw NSError(domain: "VisionDocumentReader",
                          code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Could not decode image data."])
        }

        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        try handler.perform([req])
        let strings: [String] = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return strings.joined(separator: "\n")
    }
}

// MARK: - Tiny reflection helpers

@available(iOS 26, *)
private func reflectGet<T>(_ base: Any, name: String, as type: T.Type) -> T? {
    let mirror = Mirror(reflecting: base)
    for (label, value) in mirror.children {
        if label == name, let cast = value as? T { return cast }
    }
    return nil
}

@available(iOS 26, *)
private func ddString(_ base: Any, _ names: [String]) -> String? {
    for n in names {
        if let v: String = reflectGet(base, name: n, as: String.self) { return v }
        if let vOpt: String? = reflectGet(base, name: n, as: Optional<String>.self) { return vOpt }
    }
    return nil
}
