//
//  AppEnvironment.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import Foundation

@inline(__always)
func isRunningInExtension() -> Bool {
    return Bundle.main.bundleURL.pathExtension == "appex"
}

/// Use this in any shared storage code.
func safeGroupDefaults(groupID: String) -> UserDefaults {
    if isRunningInExtension() { return .standard }
    return UserDefaults(suiteName: groupID) ?? .standard
}
