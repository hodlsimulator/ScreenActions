//
//  Handoff.swift
//  Screen Actions
//
//  Created by . . on 9/23/25.
//
//  WebExtension-side handoff writer (to the app)
//

import Foundation

enum WebExtHandoff {
    // Mirror the app’s keys so ContentView.consumeHandoffIfAny() sees it.
    private static let groupID = AppStorageService.appGroupID
    private static let K_TEXT    = "handoff.text"
    private static let K_KIND    = "handoff.kind"
    private static let K_PENDING = "handoff.pending"

    /// Queue a handoff for the app to consume on launch/activation.
    /// NOTE: Write directly to the App Group UserDefaults. Do NOT use AppStorageService.shared.defaults
    /// here because the extension intentionally uses `.standard`.
    static func queue(text: String, kind: String) {
        let defaults = UserDefaults(suiteName: groupID) ?? .standard
        defaults.set(text, forKey: K_TEXT)
        defaults.set(kind, forKey: K_KIND)        // "event" | "reminder" | "contact" | "csv"
        defaults.set(true, forKey: K_PENDING)
        defaults.synchronize()
    }
}
