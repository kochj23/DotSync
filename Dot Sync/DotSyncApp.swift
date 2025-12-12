//
//  DotSyncApp.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import SwiftUI

@main
struct DotSyncApp: App {
    @StateObject private var syncEngine = SyncEngine.shared
    @StateObject private var fileWatcher = FileWatcher.shared

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .onAppear {
                    // Start file watcher if auto-sync is enabled
                    if UserDefaults.standard.bool(forKey: "autoSyncEnabled") {
                        Task {
                            await FileDiscoveryService.shared.scanHomeDirectory()
                            let files = FileDiscoveryService.shared.discoveredFiles.filter(\.isSafeToSync)
                            await fileWatcher.startWatching(files: files)
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .appInfo) {
                Button("About Dot Sync") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }

            CommandGroup(after: .appSettings) {
                Button("Sync Now") {
                    syncNow()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Start Watching Files") {
                    startWatching()
                }
                .disabled(fileWatcher.isWatching)

                Button("Stop Watching Files") {
                    Task { await fileWatcher.stopWatching() }
                }
                .disabled(!fileWatcher.isWatching)
            }
        }

        // Menu bar extra
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }

        // Settings window
        Settings {
            PreferencesView()
        }
    }

    // MARK: - Actions

    private func syncNow() {
        Task {
            let files = FileDiscoveryService.shared.discoveredFiles.filter(\.isSafeToSync)
            let filteredFiles = ProfileManager.shared.filteredFiles(from: files)

            do {
                try await syncEngine.sync(files: filteredFiles, direction: .upload, dryRun: false)
            } catch {
                print("[App] Sync error: \(error)")
            }
        }
    }

    private func startWatching() {
        Task {
            let files = FileDiscoveryService.shared.discoveredFiles.filter(\.isSafeToSync)
            let filteredFiles = ProfileManager.shared.filteredFiles(from: files)
            await fileWatcher.startWatching(files: filteredFiles)
        }
    }
}

/// Menu bar icon label
struct MenuBarLabel: View {
    @StateObject private var syncEngine = SyncEngine.shared

    var body: some View {
        Image(systemName: statusIcon)
            .foregroundColor(statusColor)
    }

    private var statusIcon: String {
        if syncEngine.isSyncing {
            return "arrow.triangle.2.circlepath"
        }

        let conflictCount = syncEngine.syncStatuses.filter { $0.state == .conflict }.count
        if conflictCount > 0 {
            return "exclamationmark.triangle.fill"
        }

        let needsSyncCount = syncEngine.syncStatuses.filter {
            $0.state == .localNewer || $0.state == .remoteNewer
        }.count

        if needsSyncCount > 0 {
            return "arrow.up.arrow.down.circle.fill"
        }

        if syncEngine.lastSyncDate != nil {
            return "checkmark.circle.fill"
        }

        return "cloud"
    }

    private var statusColor: Color {
        if syncEngine.isSyncing {
            return .blue
        }

        let conflictCount = syncEngine.syncStatuses.filter { $0.state == .conflict }.count
        if conflictCount > 0 {
            return .red
        }

        let needsSyncCount = syncEngine.syncStatuses.filter {
            $0.state == .localNewer || $0.state == .remoteNewer
        }.count

        if needsSyncCount > 0 {
            return .yellow
        }

        if syncEngine.lastSyncDate != nil {
            return .green
        }

        return .gray
    }
}
