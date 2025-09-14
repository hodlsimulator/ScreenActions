//
//  Logger.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import Foundation
import OSLog

enum SALog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.conornolan.Screen-Actions"

    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let ext = Logger(subsystem: subsystem, category: "Extension")
    static let core = Logger(subsystem: subsystem, category: "Core")
}

// Example usage:
// SALog.ext.info("Share sheet loaded with selection length: \(self.selectedText.count)")
