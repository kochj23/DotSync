//
//  MenuBarView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import SwiftUI

/// Menu bar dropdown content
struct MenuBarView: View {
    @StateObject private var syncEngine = SyncEngine.shared
    @StateObject private var fileWatcher = FileWatcher.shared
    @StateObject private var profileManager = ProfileManager.shared

    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.headline)
                    if let lastSync = syncEngine.lastSyncDate {
                        Text("Last synced: \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never synced")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(12)

            Divider()

            // Quick actions
            Button(action: syncNow) {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(syncEngine.isSyncing)
            .keyboardShortcut("s", modifiers: [.command])

            Button(action: openMainWindow) {
                Label("Open Dot Sync", systemImage: "square.grid.2x2")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button(action: openPreferences) {
                Label("Preferences...", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            // Profile switcher
            Menu {
                ForEach(profileManager.profiles) { profile in
                    Button(action: { switchProfile(to: profile) }) {
                        HStack {
                            Text(profile.name)
                            if profile.id == profileManager.activeProfile.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Profile: \(profileManager.activeProfile.name)", systemImage: "folder.badge.gearshape")
            }

            Divider()

            // Stats
            HStack {
                Text("Files: \(FileDiscoveryService.shared.discoveredFiles.count)")
                Spacer()
                if !syncEngine.syncStatuses.isEmpty {
                    let conflicts = syncEngine.syncStatuses.filter { $0.state == .conflict }.count
                    if conflicts > 0 {
                        Text("\(conflicts) conflicts")
                            .foregroundColor(.red)
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Auto-sync toggle
            Toggle("Auto-sync", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "autoSyncEnabled") },
                set: { UserDefaults.standard.set($0, forKey: "autoSyncEnabled") }
            ))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onChange(of: UserDefaults.standard.bool(forKey: "autoSyncEnabled")) { enabled in
                if enabled {
                    startWatching()
                } else {
                    fileWatcher.stopWatching()
                }
            }

            Divider()

            // Quit
            Button("Quit Dot Sync") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .frame(width: 280)
    }

    // MARK: - Status

    private var statusIcon: some View {
        Image(systemName: syncStatusIcon)
            .font(.title2)
            .foregroundColor(syncStatusColor)
    }

    private var statusText: String {
        if syncEngine.isSyncing {
            return "Syncing..."
        } else if !syncEngine.syncStatuses.isEmpty {
            let conflicts = syncEngine.syncStatuses.filter { $0.state == .conflict }.count
            if conflicts > 0 {
                return "Conflicts Detected"
            }
            let needsSync = syncEngine.syncStatuses.filter {
                $0.state == .localNewer || $0.state == .remoteNewer
            }.count
            if needsSync > 0 {
                return "Sync Needed"
            }
            return "Everything Synced"
        } else {
            return "Dot Sync"
        }
    }

    private var syncStatusIcon: String {
        if syncEngine.isSyncing {
            return "arrow.triangle.2.circlepath"
        } else if !syncEngine.syncStatuses.isEmpty {
            let conflicts = syncEngine.syncStatuses.filter { $0.state == .conflict }.count
            if conflicts > 0 {
                return "exclamationmark.triangle.fill"
            }
            let needsSync = syncEngine.syncStatuses.filter {
                $0.state == .localNewer || $0.state == .remoteNewer
            }.count
            if needsSync > 0 {
                return "arrow.up.arrow.down.circle.fill"
            }
            return "checkmark.circle.fill"
        }
        return "cloud"
    }

    private var syncStatusColor: Color {
        if syncEngine.isSyncing {
            return .blue
        } else if !syncEngine.syncStatuses.isEmpty {
            let conflicts = syncEngine.syncStatuses.filter { $0.state == .conflict }.count
            if conflicts > 0 {
                return .red
            }
            let needsSync = syncEngine.syncStatuses.filter {
                $0.state == .localNewer || $0.state == .remoteNewer
            }.count
            if needsSync > 0 {
                return .yellow
            }
            return .green
        }
        return .gray
    }

    // MARK: - Actions

    private func syncNow() {
        Task {
            let files = FileDiscoveryService.shared.discoveredFiles.filter(\.isSafeToSync)
            let filteredFiles = profileManager.filteredFiles(from: files)

            do {
                try await syncEngine.sync(files: filteredFiles, direction: .upload, dryRun: false)
            } catch {
                print("[MenuBar] Sync error: \(error)")
            }
        }
    }

    private func openMainWindow() {
        // Activate app and show window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Find and show main window
        if let window = NSApp.windows.first(where: { $0.title.contains("Dot Sync") || $0.title.isEmpty }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openPreferences() {
        openMainWindow()
        // User can open preferences from main window menu or ⌘,
    }

    private func switchProfile(to profile: SyncProfile) {
        profileManager.setActiveProfile(profile)

        // Re-scan to update file list
        Task {
            await FileDiscoveryService.shared.scanHomeDirectory()
        }
    }

    private func startWatching() {
        let files = FileDiscoveryService.shared.discoveredFiles.filter(\.isSafeToSync)
        let filteredFiles = profileManager.filteredFiles(from: files)
        fileWatcher.startWatching(files: filteredFiles)
    }
}
