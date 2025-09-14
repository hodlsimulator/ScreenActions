//
//  AppStorageService.swift
//  Screen Actions
//
//  Created by . . on 13/09/2025.
//

import Foundation

/// Shared app storage via App Group, with SAFE fallbacks in extensions.
enum AppStorageService {
    static let appGroupID = "group.com.conornolan.screenactions"

    @MainActor
    static let shared = AppStorageServiceImpl()

    struct Keys {
        static let firstRun = "firstRun"
        static let exportCounter = "exportCounter"
    }

    @MainActor
    final class AppStorageServiceImpl {
        let defaults: UserDefaults

        init() {
            if let d = UserDefaults(suiteName: appGroupID) {
                self.defaults = d
            } else {
                // Fallback so extensions never crash if the group isn't ready yet
                self.defaults = .standard
            }
        }

        func bootstrap() {
            if defaults.object(forKey: Keys.firstRun) == nil {
                defaults.set(true, forKey: Keys.firstRun)
                defaults.set(0, forKey: Keys.exportCounter)
            }
        }

        func nextExportFilename(prefix: String, ext: String) -> String {
            let n = defaults.integer(forKey: Keys.exportCounter) + 1
            defaults.set(n, forKey: Keys.exportCounter)
            let ts = ISO8601DateFormatter().string(from: Date())
            return "\(prefix)_\(n)_\(ts).\(ext)"
        }

        /// App Group container when available; otherwise a private temp dir.
        func containerURL() -> URL {
            if let url = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: AppStorageService.appGroupID) {
                return url
            }
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScreenActionsFallback", isDirectory: true)
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
    }
}
