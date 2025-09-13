//
//  ActionViewController.swift
//  ScreenActionsActionExtension
//
//  Created by . . on 9/13/25.
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
    private var host: UIHostingController<RootView>?

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
                            if !newSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self.selectedText = newSelection }
                            if !newTitle.isEmpty { self.pageTitle = newTitle }
                            if !newURL.isEmpty { self.pageURL = newURL }
                        }
                    }
                }

                // 2) Plain text (prefer this over selection if present)
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

                // 3) URL (when no JS preprocessing ran)
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

// MARK: - SwiftUI (refined design)

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
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("Selected Text")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(selection.isEmpty ? "No selection found." : selection)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .frame(maxHeight: 160)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if !pageURL.isEmpty || !pageTitle.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if !pageTitle.isEmpty {
                            Text(pageTitle).font(.subheadline).bold()
                        }
                        if !pageURL.isEmpty {
                            Text(pageURL)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.top, 2)
                }

                Divider().padding(.vertical, 2)

                VStack(spacing: 10) {
                    Button { run { try await CreateReminderIntent.runStandalone(text: inputText) } } label: {
                        rowLabel("Create Reminder", "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button { run { try await AddToCalendarIntent.runStandalone(text: inputText) } } label: {
                        rowLabel("Add Calendar Event", "calendar.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    Button { run { try await ExtractContactIntent.runStandalone(text: inputText) } } label: {
                        rowLabel("Extract Contact", "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    Button { runReceipt() } label: {
                        rowLabel("Receipt → CSV", "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }

                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(ok ? .green : .red)
                        .padding(.top, 6)
                        .accessibilityLabel("Status")
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Screen Actions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ok ? "Done" : "Cancel") {
                        onDone(status ?? (ok ? "Done" : "Cancelled"))
                    }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView().scaleEffect(1.15)
                }
            }
        }
    }

    private var inputText: String {
        var t = selection
        if !pageTitle.isEmpty { t = t.isEmpty ? pageTitle : t }
        if !pageURL.isEmpty { t += "\n\(pageURL)" }
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
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(title)
            Spacer()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}
