//
//  Screen_ActionsApp.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import SwiftUI

@main
struct Screen_ActionsApp: App {
    @AppStorage(ShareOnboardingKeys.completed) private var hasCompletedShareOnboarding = false
    @State private var showShareOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Show once after install/update until dismissed.
                    if !hasCompletedShareOnboarding {
                        showShareOnboarding = true
                    }
                }
                .sheet(isPresented: $showShareOnboarding) {
                    ShareOnboardingView(isPresented: $showShareOnboarding)
                }
        }
    }
}
