//
//  DataDetectors.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import Foundation
import Contacts

struct DetectedDateRange {
    let start: Date
    let end: Date
}

enum DateParser {
    /// Finds the first date/time in the text and returns a start/end (defaults to 1 hour if no duration).
    static func firstDateRange(in text: String, defaultDuration: TimeInterval = 60 * 60) -> DetectedDateRange? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var first: DetectedDateRange?

        detector.enumerateMatches(in: text, options: [], range: range) { match, _, stop in
            guard let match, let date = match.date else { return }
            let duration = match.duration > 0 ? match.duration : defaultDuration
            first = DetectedDateRange(start: date, end: date.addingTimeInterval(duration))
            stop.pointee = true
        }
        return first
    }
}

struct DetectedContact {
    var givenName: String?
    var familyName: String?
    var emails: [String] = []
    var phones: [String] = []
    var postalAddress: CNPostalAddress?
}

enum ContactParser {
    static func detect(in text: String) -> DetectedContact {
        var contact = DetectedContact()

        // Name: naive — first non-empty line split into given/family
        if let firstLine = text.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        {
            let parts = firstLine.split(separator: " ").map(String.init)
            if parts.count >= 2 {
                contact.givenName = parts.first
                contact.familyName = parts.dropFirst().joined(separator: " ")
            } else {
                contact.givenName = parts.first
            }
        }

        // Phones (NSDataDetector)
        if let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            let r = NSRange(text.startIndex..<text.endIndex, in: text)
            phoneDetector.enumerateMatches(in: text, options: [], range: r) { match, _, _ in
                if let num = match?.phoneNumber {
                    contact.phones.append(num)
                }
            }
        }

        // Emails (regex)
        do {
            let pattern = #"(?:[A-Z0-9._%+-]+)@(?:[A-Z0-9.-]+)\.[A-Z]{2,}"#
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let r = NSRange(text.startIndex..<text.endIndex, in: text)
            regex.enumerateMatches(in: text, options: [], range: r) { match, _, _ in
                if let match, let range = Range(match.range, in: text) {
                    contact.emails.append(String(text[range]))
                }
            }
        } catch {
            // ignore if regex fails to compile
        }

        // Address (NSDataDetector -> CNPostalAddress). Use only keys available cross-platform.
        if let addressDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let r = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = addressDetector.firstMatch(in: text, options: [], range: r),
               let comps = match.addressComponents
            {
                let addr = CNMutablePostalAddress()
                addr.street = comps[.street] ?? ""
                addr.city = comps[.city] ?? ""
                addr.state = comps[.state] ?? ""
                addr.postalCode = comps[.zip] ?? ""
                addr.country = comps[.country] ?? ""

                if !(addr.street.isEmpty && addr.city.isEmpty && addr.state.isEmpty && addr.postalCode.isEmpty && addr.country.isEmpty) {
                    contact.postalAddress = addr.copy() as? CNPostalAddress
                }
            }
        }

        return contact
    }
}
