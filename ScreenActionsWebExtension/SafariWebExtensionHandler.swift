//
//  SafariWebExtensionHandler.swift
//  ScreenActionsWebExtension
//
//  Created by . . on 9/13/25.
//
//  Minimal native bridge that always replies synchronously.
//  Expected message shape from background.js: { action: String, payload: {…} }
//

import SafariServices
import os.log

@objc(SafariWebExtensionHandler)
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private let log = OSLog(subsystem: "com.conornolan.Screen-Actions.WebExt", category: "NativeBridge")

    func beginRequest(with context: NSExtensionContext) {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let userInfo = item.userInfo,
            let payload = userInfo[SFExtensionMessageKey] as? [String: Any]
        else {
            os_log("Missing SFExtensionMessageKey payload", log: log, type: .error)
            reply(context, body: ["ok": false, "message": "Missing SFExtensionMessageKey"])
            return
        }

        // Extract action + body (tolerant to shape)
        let action = (payload["action"] as? String) ?? ""
        let body   = (payload["payload"] as? [String: Any]) ?? [:]

        os_log("Replying to action '%{public}@'", log: log, type: .info, action)

        // Known-good echo reply
        reply(context, body: [
            "ok": true,
            "action": action,
            "echo": body,
            "platform": "iOS",
            "bundle": Bundle.main.bundleIdentifier ?? ""
        ])
    }

    private func reply(_ context: NSExtensionContext, body: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [ SFExtensionMessageKey: body ]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
