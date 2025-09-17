//
//  AppStorageService.swift
//  Screen Actions
//
//  Created by . . on 13/09/2025.
//
//  Shared storage.
//  - App: uses App Group if available (safe fallback to standard if not).
//  - Extensions: use .standard; files go to a private temp dir (no entitlements needed).
//

import Foundation

enum AppStorageService {

    static let appGroupID = "group.com.conornolan.screenactions"

    @MainActor
    static let shared = AppStorageServiceImpl()

    struct Keys {
        static let firstRun = "firstRun"
        static let exportCounter = "exportCounter"
        static let defaultAlertMinutes = "defaultAlertMinutes" // 0 = None
    }

    // MARK: - Convenience (alert minutes)
    @MainActor
    static func getDefaultAlertMinutes() -> Int {
        shared.defaults.integer(forKey: Keys.defaultAlertMinutes)
    }

    @MainActor
    static func setDefaultAlertMinutes(_ minutes: Int) {
        shared.defaults.set(minutes, forKey: Keys.defaultAlertMinutes)
    }

    @MainActor
    final class AppStorageServiceImpl {

        private let isExtension: Bool = (Bundle.main.bundleURL.pathExtension == "appex")
        let defaults: UserDefaults

        init() {
            if isExtension {
                self.defaults = .standard
            } else {
                self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
            }
        }

        func bootstrap() {
            if defaults.object(forKey: Keys.firstRun) == nil {
                defaults.set(true, forKey: Keys.firstRun)
                defaults.set(0, forKey: Keys.exportCounter)
                defaults.set(0, forKey: Keys.defaultAlertMinutes) // None by default
            }
        }

        func nextExportFilename(prefix: String, ext: String) -> String {
            let n = defaults.integer(forKey: Keys.exportCounter) + 1
            defaults.set(n, forKey: Keys.exportCounter)
            let ts = ISO8601DateFormatter().string(from: Date())
            return "\(prefix)_\(n)_\(ts).\(ext)"
        }

        /// App: App Group container when available; otherwise temp.
        /// Extensions: always temp (no sandbox extensions needed).
        func containerURL() -> URL {
            if !isExtension,
               let url = FileManager.default.containerURL(
                   forSecurityApplicationGroupIdentifier: AppStorageService.appGroupID
               ) {
                return url
            }
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScreenActionsTemp", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }
}
