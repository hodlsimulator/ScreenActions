//
//  OnboardingProgress.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import Foundation

public enum OnboardingProgress {
    public static let appGroupID = "group.com.conornolan.screenactions"

    /// Use App Group when available; otherwise fall back so the share sheet never dies.
    private static var defaults: UserDefaults {
        if let d = UserDefaults(suiteName: appGroupID) {
            return d
        }
        return .standard
    }

    private enum K {
        static let step1DidOpenInAppShare = "SA.step1DidOpenInAppShare"
        static let step2DidOpenMoreAndEdit = "SA.step2DidOpenMoreAndEdit"
        static let step3DidAddToFavourites = "SA.step3DidAddToFavourites"
        static let step5DidMoveToFront = "SA.step5DidMoveToFront"
        static let expectedPing = "SA.onboarding.expectedPing"
        static let lastPingTime = "SA.onboarding.lastPingTime"
    }

    public static var step1DidOpenInAppShare: Bool {
        get { defaults.bool(forKey: K.step1DidOpenInAppShare) }
        set { defaults.set(newValue, forKey: K.step1DidOpenInAppShare) }
    }

    public static var step2DidOpenMoreAndEdit: Bool {
        get { defaults.bool(forKey: K.step2DidOpenMoreAndEdit) }
        set { defaults.set(newValue, forKey: K.step2DidOpenMoreAndEdit) }
    }

    public static var step3DidAddToFavourites: Bool {
        get { defaults.bool(forKey: K.step3DidAddToFavourites) }
        set { defaults.set(newValue, forKey: K.step3DidAddToFavourites) }
    }

    public static var step5DidMoveToFront: Bool {
        get { defaults.bool(forKey: K.step5DidMoveToFront) }
        set { defaults.set(newValue, forKey: K.step5DidMoveToFront) }
    }

    public static func beginExpectedPingWindow() {
        defaults.set(true, forKey: K.expectedPing)
        defaults.removeObject(forKey: K.lastPingTime)
    }

    public static func pingFromShareExtension() {
        guard defaults.bool(forKey: K.expectedPing) else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: K.lastPingTime)
        defaults.set(false, forKey: K.expectedPing)
    }

    public static func wasPingedRecently(within seconds: TimeInterval = 15 * 60) -> Bool {
        let t = defaults.double(forKey: K.lastPingTime)
        guard t > 0 else { return false }
        return (Date().timeIntervalSince1970 - t) < seconds
    }

    public static func resetAll() {
        step1DidOpenInAppShare = false
        step2DidOpenMoreAndEdit = false
        step3DidAddToFavourites = false
        step5DidMoveToFront = false
        defaults.removeObject(forKey: K.expectedPing)
        defaults.removeObject(forKey: K.lastPingTime)
    }
}
