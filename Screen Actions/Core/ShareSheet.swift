//
//  ShareSheet.swift
//  Screen Actions
//
//  Created by Conor on 18/09/2025.
//

import SwiftUI
import UIKit

/// Stable wrapper for UIActivityViewController.
/// Present this via `.sheet(isPresented:)` to avoid instant dismissal.
public struct ShareSheet: UIViewControllerRepresentable {
    public var items: [Any]
    public var activities: [UIActivity]? = nil

    public init(items: [Any], activities: [UIActivity]? = nil) {
        self.items = items
        self.activities = activities
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: activities)
        // Dismiss the sheet when sharing finishes/cancels
        vc.completionWithItemsHandler = { _, _, _, _ in
            context.coordinator.dismiss()
        }
        return vc
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        @Environment(\.dismiss) private var dismissEnv

        func dismiss() {
            // Call on next runloop to avoid UIKit/SwiftUI timing quirks
            DispatchQueue.main.async {
                self.dismissEnv()
            }
        }
    }
}
