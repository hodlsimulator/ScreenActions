//
//  OnboardingProgress.swift
//  Screen Actions
//
//  Created by . . on 9/14/25.
//

import Foundation

/// Shared onboarding state in the App Group so the app and the Share extension can talk.
public enum OnboardingProgress {
    // Your existing App Group from entitlements.
    public static let appGroupID = "group.com.conornolan.screenactions"

    private static var defaults: UserDefaults {
        guard let d = UserDefaults(suiteName: appGroupID) else {
            fatalError("UserDefaults(suiteName:) failed. Check App Group entitlement: \(appGroupID)")
        }
        return d
    }

    // Keys
    private enum K {
        static let step1DidOpenInAppShare   = "SA.step1DidOpenInAppShare"
        static let step2DidOpenMoreAndEdit  = "SA.step2DidOpenMoreAndEdit"   // manual
        static let step3DidAddToFavourites  = "SA.step3DidAddToFavourites"   // manual
        static let step5DidMoveToFront      = "SA.step5DidMoveToFront"       // manual

        static let expectedPing             = "SA.onboarding.expectedPing"   // set by app before sending user to Safari
        static let lastPingTime             = "SA.onboarding.lastPingTime"   // set by extension when it launches
    }

    // MARK: Step flags (persisted)
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

    // MARK: Ping flow (auto-detected "Launched Screen Actions once from share sheet")
    /// Call in the app just before opening Safari for the user to try sharing.
    public static func beginExpectedPingWindow() {
        defaults.set(true, forKey: K.expectedPing)
        defaults.removeObject(forKey: K.lastPingTime)
    }

    /// Call in the Share extension (e.g. viewDidAppear). Marks the ping if the app asked for it.
    public static func pingFromShareExtension() {
        guard defaults.bool(forKey: K.expectedPing) else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: K.lastPingTime)
        defaults.set(false, forKey: K.expectedPing)
    }

    /// True if the extension pinged back recently (within `seconds`).
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
