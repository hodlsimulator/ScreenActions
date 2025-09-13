//
//  AppStorageService.swift
//  Screen Actions
//
//  Created by . . on 13/09/2025.
//

import Foundation

/// Shared app storage in the App Group.
/// Update the `appGroupID` if you ever rename the group.
enum AppStorageService {

    static let appGroupID = "group.com.conornolan.screenactions"

    /// Main-actor isolated singleton to satisfy Swift concurrency checks.
    @MainActor
    static let shared = AppStorageServiceImpl()

    struct Keys {
        static let firstRun = "firstRun"
        static let exportCounter = "exportCounter"
    }

    /// Main-actor isolated implementation. All access funnels through the main actor.
    @MainActor
    final class AppStorageServiceImpl {

        /// UserDefaults for the App Group (constant reference; thread-safe per Apple).
        let defaults: UserDefaults

        init() {
            guard let d = UserDefaults(suiteName: appGroupID) else {
                fatalError("UserDefaults(suiteName:) failed. Check App Group entitlement: \(appGroupID)")
            }
            self.defaults = d
        }

        /// Sets up initial defaults on first run.
        func bootstrap() {
            if defaults.object(forKey: Keys.firstRun) == nil {
                defaults.set(true, forKey: Keys.firstRun)
                defaults.set(0, forKey: Keys.exportCounter)
            }
        }

        /// Returns a monotonically increasing export filename with timestamp.
        func nextExportFilename(prefix: String, ext: String) -> String {
            let n = defaults.integer(forKey: Keys.exportCounter) + 1
            defaults.set(n, forKey: Keys.exportCounter)
            let ts = ISO8601DateFormatter().string(from: Date())
            return "\(prefix)_\(n)_\(ts).\(ext)"
        }

        /// The App Group container URL (creates it if needed).
        func containerURL() -> URL {
            guard let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppStorageService.appGroupID
            ) else {
                fatalError("App Group container not found. Check entitlements.")
            }
            return url
        }
    }
}
