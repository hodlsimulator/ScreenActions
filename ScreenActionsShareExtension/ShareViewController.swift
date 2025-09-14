//
//  ShareViewController.swift
//  ScreenActionsShareExtension
//
//  Created by . . on 13/09/2025.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Vision
import ImageIO
import AppIntents

@MainActor
final class ShareViewController: UIViewController {
    private var selectedText: String = ""
    private var pageTitle: String = ""
    private var pageURL: String = ""
    private var pendingImageData: Data?
    private var host: UIHostingController<RootView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadFromContext()
    }

    // MARK: - Load inputs from NSExtensionContext
    private func loadFromContext() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            attachUI()
            return
        }

        let group = DispatchGroup()

        for item in items {
            for provider in item.attachments ?? [] {

                // 1) JS preprocessing dictionary (preferred)
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
                        Task { @MainActor in
                            self.selectedText = trimmed
                        }
                    }
                }

                // 3) URL
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self, let url = item as? URL else { return }
                        Task { @MainActor in
                            self.pageURL = url.absoluteString
                        }
                    }
                }

                // 4) Image -> OCR text (optional)
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self else { return }
                        if let data = item as? Data {
                            Task { @MainActor in self.pendingImageData = data }
                        } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                            Task { @MainActor in self.pendingImageData = data }
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }

            // If we still have no text, try OCR off the main actor
            if self.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let data = self.pendingImageData,
               let cg = SA_makeCGImage(from: data) {

                DispatchQueue.global(qos: .userInitiated).async {
                    let text = (try? SA_recognizeText(from: cg))?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    // MARK: - Show SwiftUI UI
    private func attachUI() {
        let root = RootView(
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

// MARK: - SwiftUI UI (same UX as Action extension)

struct RootView: View {
    let selection: String
    let pageTitle: String
    let pageURL: String
    let onDone: (String) -> Void

    @State private var isWorking = false
    @State private var status: String?
    @State private var ok = false

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    Text("Selected Text")
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView {
                        Text(selection.isEmpty ? "No selection found." : selection)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                }

                Divider().padding(.vertical, 6)

                VStack(spacing: 10) {
                    Button {
                        run {
                            try await CreateReminderIntent.runStandalone(text: inputText)
                        }
                    } label: { rowLabel("Create Reminder", "checkmark.circle") }
                    .buttonStyle(.borderedProminent)

                    Button {
                        run {
                            try await AddToCalendarIntent.runStandalone(text: inputText)
                        }
                    } label: { rowLabel("Add Calendar Event", "calendar.badge.plus") }
                    .buttonStyle(.bordered)

                    Button {
                        run {
                            try await ExtractContactIntent.runStandalone(text: inputText)
                        }
                    } label: { rowLabel("Extract Contact", "person.crop.circle.badge.plus") }
                    .buttonStyle(.bordered)

                    Button {
                        runReceipt()
                    } label: { rowLabel("Receipt → CSV", "doc.badge.plus") }
                    .buttonStyle(.bordered)
                }

                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(ok ? .green : .red)
                        .padding(.top, 6)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Screen Actions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ok ? "Done" : "Cancel") {
                        onDone(status ?? (ok ? "Done" : "Cancelled"))
                    }
                }
            }
            .overlay {
                if isWorking { ProgressView().scaleEffect(1.2) }
            }
        }
    }

    private var inputText: String {
        var t = selection
        if !pageTitle.isEmpty {
            t = t.isEmpty ? pageTitle : t
        }
        if !pageURL.isEmpty {
            t += "\n\(pageURL)"
        }
        return t
    }

    private func run(_ op: @escaping () async throws -> String) {
        isWorking = true; status = nil; ok = false
        Task {
            do {
                let message = try await op()
                status = message; ok = true
            } catch {
                status = error.localizedDescription; ok = false
            }
            isWorking = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func runReceipt() {
        run {
            let (msg, url) = try await ReceiptToCSVIntent.runStandalone(text: inputText)
            UIPasteboard.general.url = url
            return "\(msg) (\(url.lastPathComponent))"
        }
    }

    @ViewBuilder
    private func rowLabel(_ title: String, _ systemImage: String) -> some View {
        HStack { Image(systemName: systemImage); Text(title); Spacer() }
            .frame(maxWidth: .infinity)
    }
}

// MARK: - OCR helpers (file-private, nonisolated)

fileprivate func SA_makeCGImage(from data: Data) -> CGImage? {
    let cfData = data as CFData
    guard
        let src = CGImageSourceCreateWithData(cfData, nil),
        let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { return nil }
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
