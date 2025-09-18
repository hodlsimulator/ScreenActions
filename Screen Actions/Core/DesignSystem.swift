//
//  DesignSystem.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//
//  Lightweight tokens + helpers for cards, spacing, fonts, gradients.
//  Keeps the system tab bar untouched.
//

import SwiftUI

enum SATheme {
    enum Spacing {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Corner {
        static let radius: CGFloat = 14
    }

    enum Font {
        static let title = SwiftUI.Font.title3.weight(.semibold)
        static let body  = SwiftUI.Font.body
        static let caption = SwiftUI.Font.caption
    }

    enum Gradient {
        // Background gradient that works in light/dark without clashing with the tab bar.
        static let background: [Color] = [
            Color(.secondarySystemBackground),
            Color(.systemBackground)
        ]
        // Brand accent used by the hero header.
        static let brand: [Color] = [Color.accentColor, Color.indigo]
    }
}

// Card background with frosted material
struct SACardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(SATheme.Spacing.m)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SATheme.Corner.radius, style: .continuous))
    }
}

extension View {
    func saCard() -> some View { modifier(SACardBackground()) }
}

// Prominent pill button (used for Auto Detect / Open editor). Does NOT alter tab bar styling.
struct SAPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .shadow(radius: configuration.isPressed ? 0 : 6, y: configuration.isPressed ? 0 : 4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
