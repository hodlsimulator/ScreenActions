//
//  SEQuotaManager.swift
//  Screen Actions
//
//  Created by . . on 9/18/25.
//

import Foundation

enum SAFeature: String, CaseIterable {
    case receiptCSVExport           // Free: up to 3/day
    case createContactFromImage     // Free: up to 5/day
    case geofencedEventCreation     // Free: up to 1/day (not used in Share ext, kept for parity)
}

struct QuotaResult {
    let allowed: Bool
    let remaining: Int
    let limit: Int
    let message: String
}

enum QuotaManager {
    private static let limits: [SAFeature: Int] = [
        .receiptCSVExport: 3,
        .createContactFromImage: 5,
        .geofencedEventCreation: 1
    ]

    // Use App Group so quotas share with the app/web extension
    private static let groupID = AppStorageService.appGroupID
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: groupID) ?? .standard
    }

    static func remainingToday(for feature: SAFeature, isPro: Bool) -> (remaining: Int, limit: Int) {
        guard !isPro else { return (Int.max, Int.max) }
        let limit = limits[feature] ?? 0
        return (max(0, limit - countToday(feature)), limit)
    }

    static func consume(feature: SAFeature, isPro: Bool) -> QuotaResult {
        if isPro {
            return .init(allowed: true, remaining: .max, limit: .max, message: "Pro – unlimited.")
        }
        let limit = limits[feature] ?? 0
        let used = countToday(feature)
        if used >= limit {
            let msg: String = {
                switch feature {
                case .receiptCSVExport:       return "You’ve hit today’s free limit (3 CSV exports). Go Pro for unlimited."
                case .createContactFromImage: return "You’ve hit today’s free limit (5 contact saves from images). Go Pro for unlimited."
                case .geofencedEventCreation: return "You’ve hit today’s free limit (1 geofenced event). Go Pro for unlimited."
                }
            }()
            return .init(allowed: false, remaining: 0, limit: limit, message: msg)
        }
        setCountToday(feature, used + 1)
        return .init(allowed: true, remaining: max(0, limit - (used + 1)), limit: limit, message: "")
    }

    // MARK: storage helpers

    private static func todayKey(_ feature: SAFeature) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        let y = comps.year ?? 2000
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return "quota.v1.\(feature.rawValue).\(y)-\(m)-\(d)"
    }
    private static func countToday(_ feature: SAFeature) -> Int {
        defaults.integer(forKey: todayKey(feature))
    }
    private static func setCountToday(_ feature: SAFeature, _ v: Int) {
        defaults.set(v, forKey: todayKey(feature))
        defaults.synchronize()
    }
}
