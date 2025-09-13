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
    static func firstDateRange(in text: String, defaultDuration: TimeInterval = 60 * 60) -> DetectedDateRange? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var first: DetectedDateRange?
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, stop in
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

        // Very light "name" heuristic: first non-empty line
        if let firstLine = text.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let parts = firstLine.split(separator: " ").map(String.init)
            if parts.count >= 2 {
                contact.givenName = parts.first
                contact.familyName = parts.dropFirst().joined(separator: " ")
            } else {
                contact.givenName = parts.first
            }
        }

        // Phones
        if let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            phoneDetector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let num = match?.phoneNumber {
                    contact.phones.append(num)
                }
            }
        }

        // Emails
        if let emailRegex = try? NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            emailRegex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                if let match, let r = Range(match.range, in: text) {
                    contact.emails.append(String(text[r]))
                }
            }
        }

        // Addresses
        if let addressDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            addressDetector.enumerateMatches(in: text, options: [], range: range) { match, _, stop in
                guard let components = match?.addressComponents else { return }
                let addr = CNMutablePostalAddress()
                addr.street = components[NSTextCheckingKey.street] ?? ""
                addr.city = components[NSTextCheckingKey.city] ?? ""
                addr.state = components[NSTextCheckingKey.state] ?? ""
                addr.postalCode = components[NSTextCheckingKey.zip] ?? ""   // ZIP key
                addr.country = components[NSTextCheckingKey.country] ?? ""
                contact.postalAddress = addr.copy() as? CNPostalAddress
                stop.pointee = true
            }
        }

        return contact
    }
}
