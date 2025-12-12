//
//  DotSyncApp.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import SwiftUI

@main
struct DotSyncApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("About Dot Sync") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }
        }
    }
}
