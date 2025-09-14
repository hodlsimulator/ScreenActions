//
//  ShareViewController.swift
//  ScreenActionsShareExtension
//
//  Created by . . on 13/09/2025.
//
//  Hosts the shared SwiftUI panel. Includes a tiny onboarding bridge
//  so this file does not depend on OnboardingProgress being in target membership.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Vision
import ImageIO

@MainActor
final class ShareViewController: UIViewController {
    private var selectedText: String = ""
    private var pageTitle: String = ""
    private var pageURL: String = ""
    private var pendingImageData: Data?
    private var host: UIHostingController<SAActionPanelView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadFromContext()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        SAOnboardingBridge.pingFromShareExtensionIfExpected()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePreferredContentSize()
    }

    // MARK: - Read inputs from NSExtensionContext
    private func loadFromContext() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            attachUI()
            return
        }
        let group = DispatchGroup()

        for item in items {
            for provider in item.attachments ?? [] {

                // Plain text
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

                // URL (do not fetch it)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self, let url = item as? URL else { return }
                        Task { @MainActor in self.pageURL = url.absoluteString }
                    }
                }

                // Image -> OCR (Data / UIImage / *file* URL only)
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self else { return }
                        if let data = item as? Data {
                            Task { @MainActor in self.pendingImageData = data }
                        } else if let image = item as? UIImage, let data = image.pngData() {
                            Task { @MainActor in self.pendingImageData = data }
                        } else if let url = item as? URL, url.isFileURL, let data = try? Data(contentsOf: url) {
                            Task { @MainActor in self.pendingImageData = data }
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if self.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let data = self.pendingImageData,
               let cg = SA_makeCGImage(from: data) {
                DispatchQueue.global(qos: .userInitiated).async {
                    let text = (try? SA_recognizeText(from: cg))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    DispatchQueue.main.async {
                        if !text.isEmpty { self.selectedText = text }
                        self.attachUI()
                    }
                }
            } else {
                self.attachUI()
            }
        }
    }

    // MARK: - Host SwiftUI
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

// MARK: - OCR helpers
fileprivate func SA_makeCGImage(from data: Data) -> CGImage? {
    let cfData = data as CFData
    guard let src = CGImageSourceCreateWithData(cfData, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img
}

fileprivate func SA_recognizeText(from image: CGImage) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
    try handler.perform([request])
    let strings: [String] = request.results?
        .compactMap { $0.topCandidates(1).first?.string } ?? []
    return strings.joined(separator: "\n")
}

// MARK: - Onboarding bridge (local defaults only)
private enum SAOnboardingBridge {
    private static let expectedKey = "SA.onboarding.expectedPing"
    private static let lastPingKey = "SA.onboarding.lastPingTime"
    static func pingFromShareExtensionIfExpected() {
        let d = UserDefaults.standard
        guard d.bool(forKey: expectedKey) else { return }
        d.set(Date().timeIntervalSince1970, forKey: lastPingKey)
        d.set(false, forKey: expectedKey)
    }
}
