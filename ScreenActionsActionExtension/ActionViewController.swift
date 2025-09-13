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
            attachUI(); return
        }
        let group = DispatchGroup()

        for item in items {
            for provider in item.attachments ?? [] {
                // JS preprocessing dictionary (preferred)
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self else { return }
                        if let dict = item as? NSDictionary,
                           let results = dict[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any] {
                            self.selectedText = (results["selection"] as? String) ?? self.selectedText
                            self.pageTitle = (results["title"] as? String) ?? self.pageTitle
                            self.pageURL = (results["url"] as? String) ?? self.pageURL
                        }
                    }
                }
                // Plain text fallback
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        guard let self, let s = item as? String else { return }
                        self.selectedText = s
                    }
                }
            }
        }
        group.notify(queue: .main) { [weak self] in self?.attachUI() }
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

// MARK: - SwiftUI
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
                    Button { run { try await CreateReminderIntent.runStandalone(text: inputText) } }
                    label: { rowLabel("Create Reminder", "checkmark.circle") }
                    .buttonStyle(.borderedProminent)

                    Button { run { try await AddToCalendarIntent.runStandalone(text: inputText) } }
                    label: { rowLabel("Add Calendar Event", "calendar.badge.plus") }
                    .buttonStyle(.bordered)

                    Button { run { try await ExtractContactIntent.runStandalone(text: inputText) } }
                    label: { rowLabel("Extract Contact", "person.crop.circle.badge.plus") }
                    .buttonStyle(.bordered)

                    Button { runReceipt() }
                    label: { rowLabel("Receipt → CSV", "doc.badge.plus") }
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
                    Button(ok ? "Done" : "Cancel") { onDone(status ?? (ok ? "Done" : "Cancelled")) }
                }
            }
            .overlay { if isWorking { ProgressView().scaleEffect(1.2) } }
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
        HStack { Image(systemName: systemImage); Text(title); Spacer() }
            .frame(maxWidth: .infinity)
    }
}
