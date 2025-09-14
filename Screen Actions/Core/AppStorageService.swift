//
//  AppStorageService.swift
//  Screen Actions
//
//  Created by . . on 13/09/2025.
//

import Foundation

/// Crash-proof: no App Group anywhere (install-safe while signing is sorted).
enum AppStorageService {

    @MainActor static let shared = AppStorageServiceImpl()

    struct Keys {
        static let firstRun = "firstRun"
        static let exportCounter = "exportCounter"
    }

    @MainActor
    final class AppStorageServiceImpl {
        let defaults: UserDefaults = .standard

        init() { }

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

        /// Always a private temp dir — no group container required.
        func containerURL() -> URL {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("ScreenActionsTemp", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }
}
