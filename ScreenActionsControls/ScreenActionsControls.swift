//
//  ScreenActionsControls.swift
//  ScreenActionsControls
//
//  Created by . . on 9/13/25.
//

//
//  ScreenActionsControls.swift
//  ScreenActionsControls
//

import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), emoji: "🙂")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        completion(SimpleEntry(date: Date(), emoji: "🙂"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        var entries: [SimpleEntry] = []
        let currentDate = Date()
        for hourOffset in 0..<5 {
            let entryDate = Calendar.current.date(byAdding: .hour, value: hourOffset, to: currentDate)!
            entries.append(SimpleEntry(date: entryDate, emoji: "🙂"))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let emoji: String
}

struct ScreenActionsControlsEntryView: View {
    var entry: Provider.Entry
    var body: some View {
        VStack {
            Text("Time:")
            Text(entry.date, style: .time)
            Text("Emoji:")
            Text(entry.emoji)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct ScreenActionsControls: Widget {
    let kind: String = "ScreenActionsControls"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ScreenActionsControlsEntryView(entry: entry)
        }
        .configurationDisplayName("Screen Actions")
        .description("A simple widget.")
    }
}

#Preview(as: .systemSmall) {
    ScreenActionsControls()
} timeline: {
    SimpleEntry(date: .now, emoji: "🙂")
}
