//
//  ShareViewController.swift
//  ScreenActionsShareExtension
//
//  Created by . . on 13/09/2025.
//
//  Real Share extension (SLComposeServiceViewController) so it appears in the big app row.
//

import Social

@MainActor
final class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool { true }
    override func didSelectPost() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
    override func configurationItems() -> [Any]! { [] }
}
