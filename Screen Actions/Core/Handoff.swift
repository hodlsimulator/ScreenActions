//
//  Handoff.swift
//  Screen Actions
//
//  Created by . . on 9/23/25.
//

import Foundation

enum HandoffKind: String {
    case event, reminder, contact, csv
}

enum Handoff {
    private static let groupID = AppStorageService.appGroupID
    private static let K_TEXT = "handoff.text"
    private static let K_KIND = "handoff.kind"
    private static let K_PENDING = "handoff.pending"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: groupID) ?? .standard
    }

    /// App side: read & clear a pending handoff (if any)
    static func take() -> (text: String, kind: HandoffKind)? {
        guard defaults.bool(forKey: K_PENDING) else { return nil }
        let text = defaults.string(forKey: K_TEXT) ?? ""
        guard let k = HandoffKind(rawValue: defaults.string(forKey: K_KIND) ?? "") else {
            defaults.set(false, forKey: K_PENDING)
            return nil
        }
        defaults.set(false, forKey: K_PENDING)
        return (text, k)
    }

    /// Extension side ALSO uses this file name, but it writes via its own copy (below).
}
