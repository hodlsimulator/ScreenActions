//
//  ActivityView.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import SwiftUI
import UIKit

/// Simple UIActivityViewController wrapper for SwiftUI.
struct ActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    @MainActor
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // No popover sourceView needed when presented via SwiftUI `.sheet`.
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    @MainActor
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
