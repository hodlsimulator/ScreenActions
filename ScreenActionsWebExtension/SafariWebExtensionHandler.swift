//
//  SafariWebExtensionHandler.swift
//  ScreenActionsWebExtension
//
//  Created by . . on 9/13/25.
//

#if os(macOS)
import Foundation
import SafariServices
import Contacts
import EventKit

@objc(SafariWebExtensionHandler)
@MainActor
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard
            let item = context.inputItems.first as? NSExtensionItem,
            let userInfo = item.userInfo,
            let body = userInfo[SFExtensionMessageKey] as? [String: Any]
        else {
            reply(context, ["ok": false, "message": "Bad message."])
            return
        }

        let action = (body["action"] as? String) ?? ""
        let payload = (body["payload"] as? [String: Any]) ?? [:]
        let selection = (payload["selection"] as? String) ?? ""
        let title = (payload["title"] as? String) ?? ""
        let urlString = (payload["url"] as? String) ?? ""
        let text = composeInput(selection: selection, title: title, url: urlString)

        Task { @MainActor in
            do {
                let result: [String: Any]
                switch action {
                case "getProStatus":
                    result = ["ok": true, "pro": Self.isProActive()]
                case "autoDetect":
                    result = try await handleAutoDetect(text: text, title: title, selection: selection)
                case "createReminder":
                    result = try await handleCreateReminder(text: text, title: title, selection: selection)
                case "addEvent":
                    result = try await handleAddEvent(text: text, title: title, selection: selection)
                case "extractContact":
                    result = try await handleExtractContact(text: text)
                case "receiptCSV":
                    let gate = QuotaManager.consume(feature: .receiptCSVExport, isPro: Self.isProActive())
                    guard gate.allowed else {
                        result = ["ok": false, "message": gate.message]
                        reply(context, result); return
                    }
                    result = try handleReceiptCSV(text: text)
                default:
                    result = ["ok": false, "message": "Unknown action."]
                }
                reply(context, result)
            } catch {
                var payload: [String: Any] = ["ok": false, "message": error.localizedDescription]
                if let hint = Self.permissionHint(for: error.localizedDescription, action: action) {
                    payload["hint"] = hint
                }
                reply(context, payload)
            }
        }
    }

    private func reply(_ context: NSExtensionContext, _ payload: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func composeInput(selection: String, title: String, url: String) -> String {
        var t = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty, !title.isEmpty { t = title }
        if !url.isEmpty { t += (t.isEmpty ? "" : "\n") + url }
        return t
    }

    // …(unchanged helpers + Core service calls; same as in your repo)…
    // The rest of this file is your existing implementation.
}
#endif
