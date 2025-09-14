//
//  DesignSystem.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import SwiftUI

enum SATheme {
    enum Spacing {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }
    enum Corner {
        static let radius: CGFloat = 12
    }
    enum Font {
        static let title = SwiftUI.Font.title3.weight(.semibold)
        static let body = SwiftUI.Font.body
        static let caption = SwiftUI.Font.caption
    }
}

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
