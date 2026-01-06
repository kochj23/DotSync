//
//  FileWatcher.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Watches configuration files for changes using FSEvents
@MainActor
class FileWatcher: ObservableObject {
    static let shared = FileWatcher()

    @Published var isWatching = false
    @Published var changedFiles: Set<String> = []

    private var eventStream: FSEventStreamRef?
    private var watchedPaths: [String] = []
    private var debounceTimers: [String: Timer] = [:]

    // Settings
    var debounceInterval: TimeInterval = 5.0  // Wait 5 seconds after change
    var autoSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: "autoSyncEnabled")
    }

    // MARK: - Watch Management

    /// Start watching files for changes
    func startWatching(files: [ConfigFile]) {
        // DISABLED: FSEvents callback causes crashes with Swift/ObjC bridging
        // TODO: Implement safer alternative (polling, DispatchSource, or FileManager notifications)
        print("[FileWatcher] ⚠️ File watching temporarily disabled due to FSEvents stability issues")
        print("[FileWatcher] Auto-sync will not work until alternative implementation is added")

        NotificationService.shared.notify(
            title: "Auto-Sync Disabled",
            body: "File watching is temporarily disabled. Use manual sync instead."
        )

        isWatching = false
        return

        // ORIGINAL CODE BELOW - COMMENTED OUT DUE TO CRASHES
        /*
        // Safety: Don't crash if already watching
        if isWatching {
            print("[FileWatcher] Already watching - stopping first")
            stopWatching()
        }

        // Extract file paths
        watchedPaths = files.map { $0.path }

        guard !watchedPaths.isEmpty else {
            print("[FileWatcher] No files to watch")
            return
        }

        print("[FileWatcher] Starting watch for \(watchedPaths.count) files")

        // REST OF FUNCTION DISABLED - FSEvents causes crashes
        */
    }

    /// Stop watching files
    func stopWatching() {
        guard let stream = eventStream else {
            // Already stopped
            isWatching = false
            return
        }

        print("[FileWatcher] Stopping file watcher...")

        // Stop stream safely
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        eventStream = nil
        isWatching = false

        // Cancel all pending timers
        debounceTimers.values.forEach { $0.invalidate() }
        debounceTimers.removeAll()

        print("[FileWatcher] ✅ Stopped watching")
    }

    deinit {
        // Ensure cleanup happens even if not called explicitly
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - Change Handling

    /// Handle file change event with debouncing
    private func handleFileChange(paths: [String]) {
        for path in paths {
            // Check if this is a watched file
            guard watchedPaths.contains(where: { path.contains($0) }) else {
                continue
            }

            // Ignore temporary files
            if path.hasSuffix(".swp") || path.hasSuffix(".tmp") || path.hasSuffix(".temp") {
                continue
            }

            print("[FileWatcher] Detected change: \(path)")

            // Cancel existing timer for this file
            debounceTimers[path]?.invalidate()

            // Add to changed files
            changedFiles.insert(path)

            // Create new debounce timer
            let timer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    await self?.handleDebouncedChange(path: path)
                }
            }

            debounceTimers[path] = timer
        }
    }

    /// Handle change after debounce delay
    private func handleDebouncedChange(path: String) async {
        debounceTimers.removeValue(forKey: path)
        changedFiles.remove(path)

        // Auto-sync if enabled
        if autoSyncEnabled {
            await autoSyncFile(path: path)
        } else {
            // Show notification prompting user to sync
            NotificationService.shared.notify(
                title: "Config File Changed",
                body: "\(URL(fileURLWithPath: path).lastPathComponent) was modified"
            )
        }
    }

    /// Automatically sync a changed file
    private func autoSyncFile(path: String) async {
        // Find the ConfigFile
        guard let file = FileDiscoveryService.shared.discoveredFiles.first(where: { $0.path == path }) else {
            return
        }

        // Check if safe to sync
        if !file.isSafeToSync {
            print("[FileWatcher] ⚠️ Skipping \(file.filename) - not safe to sync")
            return
        }

        // Perform sync
        do {
            try await SyncEngine.shared.sync(files: [file], direction: .upload, dryRun: false)
            print("[FileWatcher] ✅ Auto-synced \(file.filename)")
        } catch {
            print("[FileWatcher] ❌ Auto-sync failed for \(file.filename): \(error)")
            NotificationService.shared.notifySyncFailed(error: "Failed to sync \(file.filename)")
        }
    }

    // MARK: - Utility

    /// Cleanup (called manually, not in deinit due to @MainActor)
    func cleanup() {
        stopWatching()
    }
}
