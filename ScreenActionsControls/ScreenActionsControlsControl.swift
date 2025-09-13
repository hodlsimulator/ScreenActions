//
//  ScreenActionsControls.swift
//  ScreenActionsControls
//
//  Created by . . on 9/13/25.
//

import SwiftUI
import WidgetKit
import AppIntents

struct ScreenActionsControlsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.conornolan.Screen-Actions.ScreenActionsControls",
            provider: Provider18()
        ) { value in
            ControlWidgetToggle(
                "Start Timer",
                isOn: value,
                action: StartTimerIntent()
            ) { isRunning in
                Label(isRunning ? "On" : "Off", systemImage: "timer")
            }
        }
        .displayName("Timer")
        .description("An example control that runs a timer.")
    }
}

extension ScreenActionsControlsControl {
    struct Provider18: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool {
            // Check if the timer is running; mocked for demo
            true
        }
    }
}

struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start a timer"

    @Parameter(title: "Timer is running")
    var value: Bool

    func perform() async throws -> some IntentResult {
        // Start/stop a timer based on 'value' (no-op in demo).
        .result()
    }
}
