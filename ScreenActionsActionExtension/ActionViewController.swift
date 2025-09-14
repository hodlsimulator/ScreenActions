//
//  ActionViewController.swift
//  ScreenActionsActionExtension
//
//  Created by . . on 9/13/25.
//
//  Matches main app design via the shared action panel.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import AppIntents

@MainActor
final class ActionViewController: UIViewController {

    private var selectedText: String = ""
    private var pageTitle: String = ""
    private var pageURL: String = ""

    private var host: UIHostingController<SAActionPanelView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadFromContext()
    }

    private func loadFromContext() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            attachUI()
            return
        }

        let group = DispatchGroup()

        for item in items {
            for provider in item.attachments ?? [] {

                // 1) JS preprocessing dictionary (selection/title/url)
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard
                            let self,
                            let dict = item as? NSDictionary,
                            let results = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
                        else { return }

                        let newSelection = (results["selection"] as? String) ?? ""
                        let newTitle = (results["title"] as? String) ?? ""
                        let newURL = (results["url"] as? String) ?? ""

                        Task { @MainActor in
                            if !newSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                self.selectedText = newSelection
                            }
                            if !newTitle.isEmpty { self.pageTitle = newTitle }
                            if !newURL.isEmpty { self.pageURL = newURL }
                        }
                    }
                }

                // 2) Plain text
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self, let s = item as? String else { return }
                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        Task { @MainActor in self.selectedText = trimmed }
                    }
                }

                // 3) URL
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self, let url = item as? URL else { return }
                        Task { @MainActor in self.pageURL = url.absoluteString }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.attachUI()
        }
    }

    private func attachUI() {
        let root = SAActionPanelView(
            selection: selectedText.trimmingCharacters(in: .whitespacesAndNewlines),
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
    }
}
