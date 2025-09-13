//
//  Screen_ActionsApp.swift
//  Screen Actions
//
//  Created by . . on 9/13/25.
//

import SwiftUI

@main
struct Screen_ActionsApp: App {
    init() {
        AppStorageService.shared.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
