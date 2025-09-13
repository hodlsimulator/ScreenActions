//
//  ScreenActionsControlsLiveActivity.swift
//  ScreenActionsControls
//
//  Created by . . on 9/13/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ScreenActionsControlsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var emoji: String
    }
    var name: String
}

struct ScreenActionsControlsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScreenActionsControlsAttributes.self) { context in
            VStack { Text("Hello \(context.state.emoji)") }
                .activityBackgroundTint(Color.cyan)
                .activitySystemActionForegroundColor(Color.black)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text("Leading") }
                DynamicIslandExpandedRegion(.trailing) { Text("Trailing") }
                DynamicIslandExpandedRegion(.bottom) { Text("Bottom \(context.state.emoji)") }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
        }
    }
}

#Preview("Notification", as: .content, using: ScreenActionsControlsAttributes(name: "World")) {
    ScreenActionsControlsLiveActivity()
} contentStates: {
    ScreenActionsControlsAttributes.ContentState(emoji: "🙂")
}
