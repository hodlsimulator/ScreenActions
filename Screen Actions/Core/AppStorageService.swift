//
//  AppStorageService.swift
//  Screen Actions
//
//  Created by . . on 13/09/2025.
//

import Foundation

/// Main app uses the App Group.  Extensions use standard defaults + a private temp dir.
enum AppStorageService {
    static let appGroupID = "group.com.conornolan.screenactions"

    @MainActor static let shared = AppStorageServiceImpl()

    struct Keys {
        static let firstRun = "firstRun"
        static let exportCounter = "exportCounter"
    }

    @MainActor
    final class AppStorageServiceImpl {
        private let isExtension: Bool = Bundle.main.bundleURL.pathExtension == "appex"
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
            }
        }

        func nextExportFilename(prefix: String, ext: String) -> String {
            let n = defaults.integer(forKey: Keys.exportCounter) + 1
            defaults.set(n, forKey: Keys.exportCounter)
            let ts = ISO8601DateFormatter().string(from: Date())
            return "\(prefix)_\(n)_\(ts).\(ext)"
        }

        /// App: App Group container; Extension: private temp dir (never crashes).
        func containerURL() -> URL {
            if isExtension {
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("ScreenActionsFallback", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir
            }
            if let url = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppStorageService.appGroupID
            ) {
                return url
            }
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScreenActionsFallback", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }
}
