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
    private static let groupID = "group.com.conornolan.screenactions" // same as AppStorageService.appGroupID
    private static let K_TEXT = "handoff.text"
    private static let K_KIND = "handoff.kind"
    private static let K_PENDING = "handoff.pending"
    private static var defaults: UserDefaults {
        // In the EXTENSION we MUST write to the App Group so the app can read it.
        UserDefaults(suiteName: groupID) ?? .standard
    }

    /// Extension side: stash the payload for the app to pick up on launch.
    static func save(text: String, kind: HandoffKind) {
        defaults.set(text, forKey: K_TEXT)
        defaults.set(kind.rawValue, forKey: K_KIND)
        defaults.set(true, forKey: K_PENDING)
    }
}
