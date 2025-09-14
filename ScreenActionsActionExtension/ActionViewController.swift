//
//  ActionViewController.swift
//  ScreenActionsActionExtension
//
//  Created by . . on 9/13/25.
//
//  Matches main app design via the shared action panel.
//
//  Hosts the shared SwiftUI panel and preloads selection/title/url
//  via the JavaScript preprocessing result (GetSelection.js).
//

import UIKit
import SwiftUI
import MobileCoreServices

@MainActor
final class ActionViewController: UIViewController {

    private var selectedText: String = ""
    private var pageTitle: String = ""
    private var pageURL: String = ""
    private var host: UIHostingController<SAActionPanelView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadFromJavaScriptPayload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredContentSize()
    }

    // MARK: - Read JS preprocessing results

    private func loadFromJavaScriptPayload() {
        guard let item = (extensionContext?.inputItems.first as? NSExtensionItem),
              let dict = item.userInfo?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
        else {
            attachUI()
            return
        }

        if let s = dict["selection"] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedText = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let t = dict["title"] as? String {
            pageTitle = t
        }
        if let u = dict["url"] as? String {
            pageURL = u
        }

        attachUI()
    }

    // MARK: - Host SwiftUI

    private func attachUI() {
        let root = SAActionPanelView(
            selection: selectedText,
            pageTitle: pageTitle,
            pageURL: pageURL
        ) { [weak self] message in
            let out = NSExtensionItem()
            out.userInfo = ["ScreenActionsResult": message]
            self?.extensionContext?.completeRequest(returningItems: [out], completionHandler: nil)
        }

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        self.host = host
        updatePreferredContentSize()
    }

    private func updatePreferredContentSize() {
        guard let host else { return }
        let w = max(320, view.bounds.width)
        let target = CGSize(width: w, height: UIView.layoutFittingCompressedSize.height)
        let size = host.sizeThatFits(in: target)
        let h = max(360, min(680, size.height + 20))
        preferredContentSize = CGSize(width: w, height: h)
    }
}
