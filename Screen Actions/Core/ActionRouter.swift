//
//  ActionRouter.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import Foundation

// NOTE: Keep these internal (no `public`) because RouteDecision references
// the internal `DetectedDateRange` type defined in DataDetectors.swift.

enum ScreenActionKind: String {
    case reminder, event, contact, receipt
}

struct RouteDecision {
    let kind: ScreenActionKind
    let reason: String
    let dateRange: DetectedDateRange?
}

enum ActionRouter {
    /// Heuristic router that scores the four built-in actions and picks one.
    /// Pure and cheap: uses NSDataDetector + regexes only.
    static func route(text raw: String, locale: Locale = .current) -> RouteDecision {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var scores: [ScreenActionKind: Int] = [.reminder: 0, .event: 0, .contact: 0, .receipt: 0]
        var reasons: [String] = []

        // Prepare detectors up-front
        let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
        let addressDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)

        // Currency lines (receipt)
        let currencyPattern = #"([€£$])\s?([0-9]+(?:\.[0-9]{2})?)"#
        let currencyRegex = try? NSRegularExpression(pattern: currencyPattern)
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        var currencyHits = 0
        if let currencyRegex {
            for line in lines {
                let range = NSRange(location: 0, length: (line as NSString).length)
                if currencyRegex.firstMatch(in: line, range: range) != nil { currencyHits += 1 }
            }
        }
        if currencyHits >= 2 { scores[.receipt, default: 0] += 4; reasons.append("≥2 currency lines") }
        if text.localizedCaseInsensitiveContains("subtotal") || text.localizedCaseInsensitiveContains("total") ||
           text.localizedCaseInsensitiveContains("vat") || text.localizedCaseInsensitiveContains("tax") ||
           text.localizedCaseInsensitiveContains("tip") {
            scores[.receipt, default: 0] += 2; reasons.append("receipt keywords")
        }
        if lines.count >= 6 && averageLineLength(lines) < 28 {
            scores[.receipt, default: 0] += 1; reasons.append("short receipt-like lines")
        }

        // Contact signals
        var emailCount = 0
        if let linkDetector {
            let r = NSRange(text.startIndex..., in: text)
            linkDetector.enumerateMatches(in: text, options: [], range: r) { match, _, _ in
                guard let match, let url = match.url else { return }
                if url.scheme?.lowercased() == "mailto" || url.absoluteString.contains("@") { emailCount += 1 }
            }
        } else {
            // Fallback simple email regex
            let emailPattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
            if let re = try? NSRegularExpression(pattern: emailPattern, options: [.caseInsensitive]) {
                emailCount = re.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            }
        }
        if emailCount > 0 { scores[.contact, default: 0] += 3; reasons.append("has email") }

        let phoneCount = phoneDetector?.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? 0
        if phoneCount > 0 { scores[.contact, default: 0] += 2; reasons.append("has phone") }

        let addressCount = addressDetector?.numberOfMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? 0
        if addressCount > 0 { scores[.contact, default: 0] += 2; reasons.append("has address") }

        // Event vs Reminder (dates + verbs)
        let dateRange = DateParser.firstDateRange(in: text)
        if dateRange != nil { scores[.event, default: 0] += 4; reasons.append("has date") }

        if containsAny(text, [
            "meeting","call","dinner","flight","concert","appointment","appt","zoom","teams","google meet","rsvp","from","to","at"
        ]) {
            scores[.event, default: 0] += 1
        }

        if containsAny(text, [
            "remind me","remember to","todo","to-do","buy","pick up","call","email","pay","renew","follow up","due","by "
        ]) {
            scores[.reminder, default: 0] += (dateRange == nil ? 3 : 1)
        }

        // Fallback nudges
        if scores.values.allSatisfy({ $0 == 0 }) {
            scores[.reminder] = 1
            reasons.append("fallback→reminder")
        }

        // Tie-breaks: receipt > contact > event > reminder when equal
        let order: [ScreenActionKind] = [.receipt, .contact, .event, .reminder]
        let winner = order.max { (a, b) in scores[a, default: 0] < scores[b, default: 0] } ?? .reminder
        return RouteDecision(kind: winner, reason: reasons.joined(separator: ", "), dateRange: dateRange)
    }

    private static func averageLineLength(_ lines: [String]) -> Double {
        guard !lines.isEmpty else { return 0 }
        let total = lines.reduce(0) { $0 + $1.count }
        return Double(total) / Double(lines.count)
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        for w in needles { if haystack.localizedCaseInsensitiveContains(w) { return true } }
        return false
    }
}
