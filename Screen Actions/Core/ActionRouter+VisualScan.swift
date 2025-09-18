//
//  ActionRouter+VisualScan.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//
//  Bridges a live scan payload into either:
//  • open a URL (for typical QR links), or
//  • hand off to your existing editors via ActionRouter.
//

import Foundation
import Contacts
import UIKit

enum VisualScanResolution {
    case openURL(URL)
    case saveContact(DetectedContact)                 // for vCard QR payloads
    case handoff(decision: RouteDecision, text: String)
}

enum VisualScanRouter {
    static func resolve(_ payload: VisualScanPayload) -> VisualScanResolution {
        let s = payload.rawString.trimmingCharacters(in: .whitespacesAndNewlines)

        // vCard in QR → save contact directly
        if looksLikeVCard(s), let dc = detectedContact(fromVCard: s) {
            return .saveContact(dc)
        }

        // URL-like payload → open it
        if let url = firstURL(in: s) {
            return .openURL(url)
        }

        // Otherwise route text to existing editors
        let decision = ActionRouter.route(text: s)
        return .handoff(decision: decision, text: s)
    }
}

// MARK: - Helpers

private func looksLikeVCard(_ s: String) -> Bool {
    let u = s.uppercased()
    return u.contains("BEGIN:VCARD") && u.contains("END:VCARD")
}

private func detectedContact(fromVCard s: String) -> DetectedContact? {
    let data = s.data(using: .utf8) ?? Data()
    do {
        let contacts = try CNContactVCardSerialization.contacts(with: data)
        guard let c = contacts.first else { return nil }
        var dc = DetectedContact()
        if !c.givenName.isEmpty { dc.givenName = c.givenName }
        if !c.familyName.isEmpty { dc.familyName = c.familyName }
        dc.emails = c.emailAddresses.map { String($0.value) }
        dc.phones = c.phoneNumbers.map { $0.value.stringValue }
        if let addr = c.postalAddresses.first?.value {
            dc.postalAddress = addr
        }
        return dc
    } catch {
        return nil
    }
}

private func firstURL(in text: String) -> URL? {
    // Direct parse
    if let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty {
        return url
    }
    // Detect links in free text
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        let r = NSRange(text.startIndex..., in: text)
        if let match = detector.firstMatch(in: text, options: [], range: r),
           let range = Range(match.range, in: text) {
            return URL(string: String(text[range]))
        }
    }
    return nil
}
