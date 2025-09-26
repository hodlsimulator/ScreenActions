//
//  SafariWebExtensionHandler.swift
//  ScreenActionsWebExtension
//
//  Created by . . on 9/13/25.
//
//  Minimal, always-replying native bridge.
//  Replies within 15s so JS promises resolve (your background timeout is 15s).

import SafariServices
import os.log

@objc(SafariWebExtensionHandler)
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private let log = OSLog(subsystem: "com.conornolan.Screen-Actions.WebExt", category: "NativeBridge")

    func beginRequest(with context: NSExtensionContext) {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let userInfo = item.userInfo,
            let payload = userInfo[SFExtensionMessageKey]
        else {
            os_log("No SFExtensionMessageKey payload", log: log, type: .error)
            reply(context, body: ["ok": false, "message": "Missing SFExtensionMessageKey"])
            return
        }

        // Expected message shape from background.js: { action: String, payload: {…} }
        var action = ""
        var body: [String: Any] = [:]

        if let dict = payload as? [String: Any] {
            action = (dict["action"] as? String) ?? ""
            body   = (dict["payload"] as? [String: Any]) ?? [:]
        }

        // You can switch on `action` here if needed. For now, echo a success.
        let replyObj: [String: Any] = [
            "ok": true,
            "action": action,
            "echo": body,
            "platform": "iOS",
            "bundle": Bundle.main.bundleIdentifier ?? ""
        ]

        os_log("Replying to action '%{public}@'", log: log, type: .info, action)
        reply(context, body: replyObj)
    }

    private func reply(_ context: NSExtensionContext, body: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [ SFExtensionMessageKey: body ]   // <- required key
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
