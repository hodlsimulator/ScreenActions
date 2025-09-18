//
//  Screen_ActionsApp.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import SwiftUI

@main
struct Screen_ActionsApp: App {
    @StateObject private var pro: ProStore

    init() {
        // Set up shared storage defaults (sync, safe in init)
        AppStorageService.shared.bootstrap()
        // Create the StateObject without capturing self in an escaping closure
        _pro = StateObject(wrappedValue: ProStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(pro)
                // Run async bootstrap after the view appears (no escaping-capture issue)
                .task {
                    await pro.bootstrap()
                }
        }
    }
}
