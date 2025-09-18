//
//  ShareViewController.swift
//  ScreenActionsShareExtension
//
//  Created by . . on 13/09/2025.
//
//  ShareViewController.swift — Share Extension
//  Hosts the SwiftUI panel + injects a ProStore stub so editor sheets work.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private var selectedText: String = ""
    private var pageTitle: String = ""
    private var pageURL: String = ""
    private var imageData: Data? = nil
    private var host: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        AppStorageService.shared.bootstrap() // safe no-op if already done
        loadFromContext()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredContentSize()
    }

    private func loadFromContext() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            attachUI(); return
        }

        let group = DispatchGroup()

        for item in items {
            for provider in item.attachments ?? [] {

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self, let s = item as? String else { return }
                        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        Task { @MainActor in self.selectedText = t }
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self, let url = item as? URL else { return }
                        Task { @MainActor in self.pageURL = url.absoluteString }
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self else { return }
                        if let data = item as? Data {
                            Task { @MainActor in self.imageData = data }
                        } else if let image = item as? UIImage, let data = image.pngData() {
                            Task { @MainActor in self.imageData = data }
                        } else if let url = item as? URL, url.isFileURL, let data = try? Data(contentsOf: url) {
                            Task { @MainActor in self.imageData = data }
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.attachUI()
        }
    }

    private func attachUI() {
        // Pro status is mirrored by the app into the App Group.
        let pro = ProStore()
        Task { await pro.refreshEntitlement() } // reads mirror; no StoreKit in extension

        let root = SAActionPanelView(
            selection: selectedText,
            pageTitle: pageTitle,
            pageURL: pageURL,
            imageData: imageData
        ) { [weak self] (message: String) in
            let out = NSExtensionItem()
            out.userInfo = ["ScreenActionsResult": message]
            self?.extensionContext?.completeRequest(returningItems: [out], completionHandler: nil)
        }
        .environmentObject(pro) // needed by the editor sheets/paywall

        let host = UIHostingController(rootView: AnyView(root))
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
        let h = max(320, min(640, size.height + 20))
        preferredContentSize = CGSize(width: w, height: h)
    }
}
