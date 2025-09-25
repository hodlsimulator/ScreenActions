//
//  SAWebBridge.swift
//  Screen Actions
//
//  Created by . . on 9/22/25.
//

import Foundation
import os

@objc(SAWebBridge)
@MainActor
final class SAWebBridge: NSObject {
    static let log = Logger(subsystem: "com.conornolan.Screen-Actions.WebExtension", category: "native")

    /// Entry point called by the Obj‑C principal
    @objc
    class func handle(_ action: String, payload: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            do {
                log.info("[SA] handle action=\(action, privacy: .public)")
                let result = try await route(action: action, payload: payload)
                completion(result)
            } catch {
                log.error("[SA] error: \(error.localizedDescription, privacy: .public)")
                completion(["ok": false, "message": error.localizedDescription])
            }
        }
    }

    private class func route(action: String, payload: [String: Any]) async throws -> [String: Any] {
        if action == "ping" { return ["ok": true, "message": "pong"] }

        // Build one blob from selection/title/url
        let selection = (payload["selection"] as? String) ?? ""
        let title = (payload["title"] as? String) ?? ""
        let url = (payload["url"] as? String) ?? ""

        var text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, !title.isEmpty { text = title }
        if !url.isEmpty { text += (text.isEmpty ? "" : "\n") + url }

        switch action {
        case "addEvent":
            Handoff.save(text: text, kind: .event)
            return ["ok": true, "openURL": "screenactions://handoff?kind=event"]

        case "createReminder":
            Handoff.save(text: text, kind: .reminder)
            return ["ok": true, "openURL": "screenactions://handoff?kind=reminder"]

        case "extractContact":
            Handoff.save(text: text, kind: .contact)
            return ["ok": true, "openURL": "screenactions://handoff?kind=contact"]

        case "receiptCSV":
            Handoff.save(text: text, kind: .csv)
            return ["ok": true, "openURL": "screenactions://handoff?kind=csv"]

        case "autoDetect":
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return ["ok": false, "message": "No text selected."] }
            Handoff.save(text: t, kind: .event) // app will still choose the right editor
            return ["ok": true, "openURL": "screenactions://handoff?kind=auto"]

        default:
            return ["ok": false, "message": "Unknown action."]
        }
    }
}
