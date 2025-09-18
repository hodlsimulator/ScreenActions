//
//  ShareOnboardingView.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//  Reworked: 18/09/2025 – Instruction-first, system toolbar, brand icon diagrams.
//

import SwiftUI
import UIKit

// MARK: - Keys
struct ShareOnboardingKeys {
    static let completed = "SAHasCompletedShareOnboarding"
}

// MARK: - App icon loader (uses real bundle icon, with safe fallback)
enum AppIconProvider {
    static func primaryUIImage() -> UIImage? {
        // Try CFBundleIcons (works when icon names are exported)
        if
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String]
        {
            // Prefer the largest name in the list
            for name in files.reversed() {
                if let ui = UIImage(named: name) { return ui }
            }
        }
        // Fallback: if you've added Icon-1024.png to the target as a resource
        if
            let url = Bundle.main.url(forResource: "Icon-1024", withExtension: "png"),
            let data = try? Data(contentsOf: url),
            let ui = UIImage(data: data)
        {
            return ui
        }
        return nil
    }
}

struct ShareOnboardingView: View {
    @Binding var isPresented: Bool
    @AppStorage(ShareOnboardingKeys.completed) private var hasCompleted = false
    @Environment(\.openURL) private var openURL

    @State private var page = 0
    @State private var showShareSheetHere = false

    private let sampleURL = URL(string: "https://www.apple.com/")!
    private let lastPage = 5

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                // 0 — Welcome / Overview
                GuidePage(
                    title: "Pin Screen Actions to the Share Sheet",
                    subtitle: "Add it once and it’s always handy in Safari (and other apps)."
                ) {
                    DiagramShareOverview()
                    BulletList(items: [
                        "Top row = your Favourites",
                        "Put Screen Actions there for quick access",
                        "Works for links, selected text and images"
                    ])
                }
                .tag(0)

                // 1 — Learn Tapping
                GuidePage(
                    title: "How the top row works",
                    subtitle: "Tap an icon to run it. Press-and-hold to reorder. “More” lets you edit the list."
                ) {
                    DiagramTapToRun()
                    BulletList(items: [
                        "Tap once to run the selected app",
                        "Long-press and drag to reorder",
                        "Use “More” → “Edit” to enable apps"
                    ])
                }
                .tag(1)

                // 2 — Open the Share Sheet (explain first)
                GuidePage(
                    title: "Open the Share Sheet",
                    subtitle: "In Safari, tap the share button (the square with an upward arrow)."
                ) {
                    DiagramShareButton()
                }
                .tag(2)

                // 3 — More → Edit
                GuidePage(
                    title: "Go to More → Edit",
                    subtitle: "Swipe the top row to the end, tap “More”, then “Edit”."
                ) {
                    DiagramMoreEdit()
                    BulletList(items: [
                        "Scroll the list to find “Screen Actions”",
                        "Enable it so it appears in the top row"
                    ])
                }
                .tag(3)

                // 4 — Add to Favourites & reorder
                GuidePage(
                    title: "Add to Favourites, then drag to the front",
                    subtitle: "Enable Screen Actions, add to Favourites, long-press and drag it to the far left."
                ) {
                    DiagramAddToFavourites()
                    DiagramReorderToFront()
                }
                .tag(4)

                // 5 — Try it
                GuidePage(
                    title: "Try it out",
                    subtitle: "Share any page and tap “Screen Actions”. That’s it."
                ) {
                    DiagramSafariRun()

                    // Keep actions tasteful and system-styled
                    VStack(spacing: 12) {
                        Button {
                            openURL(sampleURL)
                        } label: {
                            Label("Open Safari (apple.com)", systemImage: "safari")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            showShareSheetHere = true
                        } label: {
                            Label("Open Share Sheet here", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.top, 8)

                    BulletList(items: [
                        "If you don’t see it, tap More → Edit and enable Screen Actions",
                        "Reorder any time via More → Edit"
                    ])
                }
                .tag(5)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            .navigationTitle("Share Sheet Guide")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showShareSheetHere) {
                ActivityView(activityItems: [sampleURL])
            }
            // System toolbar (bottom) — adopts iOS 26 styling automatically
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Back") { withAnimation { page = max(0, page - 1) } }
                        .disabled(page == 0)

                    Spacer()

                    Button(page == lastPage ? "Done" : "Next") {
                        if page == lastPage {
                            hasCompleted = true
                            isPresented = false
                        } else {
                            withAnimation { page = min(lastPage, page + 1) }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

// MARK: - Page wrapper

private struct GuidePage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                content
            }
            // Slightly larger margins prevent any bubble clipping on compact widths
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Bulleted list

private struct BulletList: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                    Text(item)
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Simple diagrams (system-safe, no Canvas)

/// Overview: favourites row with the real app icon highlighted.
private struct DiagramShareOverview: View {
    var body: some View {
        FavouriteRow {
            ForEach(0..<3) { _ in AppBubble() }
            HighlightedAppBubble(label: "Screen Actions")
            ForEach(0..<2) { _ in AppBubble() }
        }
        Caption("The top row is your Favourites. Put Screen Actions here.")
    }
}

/// Teach “tap to run”.
private struct DiagramTapToRun: View {
    var body: some View {
        ZStack {
            FavouriteRow {
                ForEach(0..<2) { _ in AppBubble() }
                HighlightedAppBubble(label: "Screen Actions")
                ForEach(0..<3) { _ in AppBubble() }
            }
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .offset(x: -60, y: -6)
                .accessibilityHidden(true)
        }
        Caption("Tap an icon to run it. Long-press to reorder.")
    }
}

/// Share button shape.
private struct DiagramShareButton: View {
    var body: some View {
        CardRow {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 36, weight: .semibold))
            Text("Tap this in Safari to open the Share Sheet.")
        }
    }
}

/// “More → Edit” hint on the right end of the apps row.
private struct DiagramMoreEdit: View {
    var body: some View {
        FavouriteRow {
            ForEach(0..<5) { _ in AppBubble() }
            Spacer(minLength: 0)
            MoreBubble()
        }
    }
}

/// “Add to Favourites” visual with a star badge.
private struct DiagramAddToFavourites: View {
    var body: some View {
        FavouriteRow(taller: true) {
            ForEach(0..<2) { _ in AppBubble() }
            HighlightedAppBubble(label: "Screen Actions", showStar: true)
            ForEach(0..<2) { _ in AppBubble() }
        }
        Caption("Enable it and add to Favourites.")
    }
}

/// Reorder hint with a left arrow.
private struct DiagramReorderToFront: View {
    var body: some View {
        VStack(spacing: 10) {
            FavouriteRow {
                HighlightedAppBubble(label: "Screen Actions")
                ForEach(0..<4) { _ in AppBubble() }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.left")
                Text("Press-and-hold, then drag left")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }
}

/// Final confirmation with Safari icon.
private struct DiagramSafariRun: View {
    var body: some View {
        CardRow {
            Image(systemName: "safari")
                .font(.system(size: 36, weight: .semibold))
            Text("Share any page and pick “Screen Actions”.")
        }
    }
}

// MARK: - Diagram primitives

/// A rounded “row” container that prevents edge clipping.
private struct FavouriteRow<Content: View>: View {
    var taller: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .frame(height: taller ? 120 : 98)
            .overlay(
                HStack(spacing: 14) {
                    content
                }
                .padding(.horizontal, 18) // extra to avoid leftmost clipping
                .frame(maxWidth: .infinity, alignment: .leading)
            )
    }
}

/// Simple card row (icon + text).
private struct CardRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct Caption: View {
    let text: String
    init(_ t: String) { self.text = t }
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }
}

private struct AppBubble: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemFill))
            Image(systemName: "app.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

private struct MoreBubble: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 44, height: 44)
        .overlay(alignment: .topTrailing) {
            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 52)
        }
        .accessibilityHidden(true)
    }
}

/// Uses the **real app icon** if available.
private struct HighlightedAppBubble: View {
    var label: String
    var showStar: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // Background highlight ring
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                    )
                    .overlay {
                        // Real icon (or fallback symbol)
                        if let ui = AppIconProvider.primaryUIImage() {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .padding(4)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                if showStar {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(3)
                }
            }
            .frame(width: 44, height: 44)

            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 80) // a touch wider so text never clips
        .accessibilityLabel(label)
    }
}
