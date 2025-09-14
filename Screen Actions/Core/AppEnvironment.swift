//
//  AppEnvironment.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import Foundation

@inline(__always)
func isRunningInExtension() -> Bool {
    Bundle.main.bundleURL.pathExtension == "appex"
}

/// Use this in shared storage code so extensions never depend on App Groups.
@inline(__always)
func safeGroupDefaults(groupID: String) -> UserDefaults {
    if isRunningInExtension() { return .standard }
    return UserDefaults(suiteName: groupID) ?? .standard
}
