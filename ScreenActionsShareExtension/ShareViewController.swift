//
//  ShareViewController.swift
//  ScreenActionsShareExtension
//
//  Created by . . on 13/09/2025.
//
//  Real Share extension (SLComposeServiceViewController) so it appears in the big app row.
//

import UIKit
import Social
import UniformTypeIdentifiers
import Vision
import ImageIO
import AppIntents

enum ScreenAction: String, CaseIterable {
    case createReminder = "Create Reminder"
    case addEvent       = "Add Calendar Event"
    case extractContact = "Extract Contact"
    case receiptCSV     = "Receipt → CSV"
}

@MainActor
final class ShareViewController: SLComposeServiceViewController {

    private var selectedText: String = ""
    private var pageTitle: String = ""
    private var pageURL: String = ""
    private var pendingImageData: Data?

    private var chosenAction: ScreenAction = .createReminder
    private var actionConfigItem: SLComposeSheetConfigurationItem?
    private var previewConfigItem: SLComposeSheetConfigurationItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        gatherInputsFromContext()
    }

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        Task { [inputText] in
            do {
                let message: String
                switch chosenAction {
                case .createReminder:
                    message = try await CreateReminderIntent.runStandalone(text: inputText)
                case .addEvent:
                    message = try await AddToCalendarIntent.runStandalone(text: inputText)
                case .extractContact:
                    message = try await ExtractContactIntent.runStandalone(text: inputText)
                case .receiptCSV:
                    let (msg, url) = try await ReceiptToCSVIntent.runStandalone(text: inputText)
                    UIPasteboard.general.url = url
                    message = "\(msg) (\(url.lastPathComponent))"
                }
                let out = NSExtensionItem()
                out.userInfo = ["ScreenActionsResult": message]
                extensionContext?.completeRequest(returningItems: [out], completionHandler: nil)
            } catch {
                let out = NSExtensionItem()
                out.userInfo = ["ScreenActionsError": error.localizedDescription]
                extensionContext?.completeRequest(returningItems: [out], completionHandler: nil)
            }
        }
    }

    override func configurationItems() -> [Any]! {
        let actionItem = SLComposeSheetConfigurationItem()
        actionItem?.title = "Action"
        actionItem?.value = chosenAction.rawValue
        actionItem?.tapHandler = { [weak self] in
            guard let self else { return }
            let vc = ActionPickerViewController(current: self.chosenAction) { newAction in
                self.chosenAction = newAction
                self.reloadConfigurationItems()
                self.popConfigurationViewController()
            }
            self.pushConfigurationViewController(vc)
        }
        self.actionConfigItem = actionItem

        let preview = SLComposeSheetConfigurationItem()
        preview?.title = "Preview"
        preview?.value = inputTextPreview
        preview?.tapHandler = { [weak self] in
            guard let self else { return }
            let vc = PreviewViewController(text: self.inputText)
            self.pushConfigurationViewController(vc)
        }
        self.previewConfigItem = preview

        return [actionItem, preview].compactMap { $0 }
    }

    // MARK: Input assembly

    private var inputText: String {
        var t = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty, !pageTitle.isEmpty { t = pageTitle }
        if !pageURL.isEmpty { t += (t.isEmpty ? "" : "\n") + pageURL }

        let userTyped = (self.contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !userTyped.isEmpty { t += (t.isEmpty ? "" : "\n\n") + userTyped }
        return t
    }

    private var inputTextPreview: String {
        let s = inputText
        return s.count <= 60 ? (s.isEmpty ? "(No text)" : s) : String(s.prefix(60)) + "…"
    }

    // MARK: Read from NSItemProvider only (no JavaScript preprocessor here)
    private func gatherInputsFromContext() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        let group = DispatchGroup()

        for item in items {
            for provider in item.attachments ?? [] {

                // Text
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

                // URL (never fetch it here)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self, let url = item as? URL else { return }
                        Task { @MainActor in self.pageURL = url.absoluteString }
                    }
                }

                // Image (Data / UIImage / file URLs only — no network reads)
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
               let cg = SA_makeCGImage(from: data),
               let text = try? SA_recognizeText(from: cg),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.selectedText = text
            }
            self.reloadConfigurationItems()
        }
    }
}

// MARK: - Config sub-views

final class ActionPickerViewController: UITableViewController {
    private var current: ScreenAction
    private let onPick: (ScreenAction) -> Void

    init(current: ScreenAction, onPick: @escaping (ScreenAction) -> Void) {
        self.current = current
        self.onPick = onPick
        super.init(style: .insetGrouped)
        self.title = "Choose Action"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { ScreenAction.allCases.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let a = ScreenAction.allCases[indexPath.row]
        cell.textLabel?.text = a.rawValue
        cell.accessoryType = (a == current) ? .checkmark : .none
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let a = ScreenAction.allCases[indexPath.row]
        current = a
        onPick(a)
        if let host = self.parent as? SLComposeServiceViewController {
            host.popConfigurationViewController()
        } else {
            self.dismiss(animated: true)
        }
    }
}

final class PreviewViewController: UIViewController {
    private let text: String
    init(text: String) { self.text = text; super.init(nibName: nil, bundle: nil); self.title = "Preview" }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        let tv = UITextView(frame: .zero, textContainer: nil)
        tv.isEditable = false
        tv.font = .preferredFont(forTextStyle: .body)
        tv.text = text.isEmpty ? "(No text)" : text
        self.view = tv
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
    let strings: [String] = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
    return strings.joined(separator: "\n")
}
