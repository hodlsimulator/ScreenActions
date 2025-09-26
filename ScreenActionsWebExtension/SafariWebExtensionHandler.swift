//
//  SafariWebExtensionHandler.swift
//  ScreenActionsWebExtension
//
//  Created by . . on 9/13/25.
//
//  SafariWebExtensionHandler.swift — non-isolated handler; safe MainActor hop with a Sendable box
// 

@preconcurrency import SafariServices
import Foundation
import os.log

// Wrap non-Sendable NSExtensionContext so we can move a handle across Task boundaries safely.
// We ONLY touch `context` on the main actor.
private struct SendableContext: @unchecked Sendable {
    let context: NSExtensionContext
}

@objc(SafariWebExtensionHandler)
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private let log = OSLog(subsystem: "com.conornolan.Screen-Actions.WebExt", category: "NativeBridge")

    func beginRequest(with context: NSExtensionContext) {
        let ctxBox = SendableContext(context: context)

        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let userInfo = item.userInfo,
            let payload = userInfo[SFExtensionMessageKey] as? [String: Any]
        else {
            respondOnMain(ctxBox, body: ["ok": false, "message": "Missing SFExtensionMessageKey"])
            return
        }

        let action   = (payload["action"] as? String) ?? ""
        let bodyDict = (payload["payload"] as? [String: Any]) ?? [:]

        // JSON-copy the body so we don't cross actors with [String: Any].
        let bodyData = (try? JSONSerialization.data(withJSONObject: bodyDict, options: [])) ?? Data()

        // Hop to MainActor (where SAWebBridge runs) without capturing self/context.
        Task { @MainActor in
            let body = (try? JSONSerialization.jsonObject(with: bodyData, options: [])) as? [String: Any] ?? [:]

            SAWebBridge.handle(action, payload: body) { out in
                respondNowOnMain(ctxBox.context, body: out)
            }
        }
    }
}

// MARK: - Reply helpers (no captures from non-isolated code)

/// Schedule a reply on the main actor without capturing non-Sendable values into a Task.
private func respondOnMain(_ ctxBox: SendableContext, body: [String: Any]) {
    // JSON round-trip to avoid sending [String: Any] across actors.
    let bodyData = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data()
    Task { @MainActor in
        let dict = (try? JSONSerialization.jsonObject(with: bodyData, options: [])) as? [String: Any] ?? [:]
        respondNowOnMain(ctxBox.context, body: dict)
    }
}

/// Must run on the main actor.
@MainActor
private func respondNowOnMain(_ context: NSExtensionContext, body: [String: Any]) {
    let response = NSExtensionItem()
    response.userInfo = [SFExtensionMessageKey: body]
    context.completeRequest(returningItems: [response], completionHandler: nil)
}
