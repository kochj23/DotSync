//
//  FileWatcher.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Watches configuration files for changes using DispatchSource
/// Replaces FSEvents which caused crashes with Swift/ObjC bridging
@MainActor
class FileWatcher: ObservableObject {
    static let shared = FileWatcher()

    @Published var isWatching = false
    @Published var changedFiles: Set<String> = []

    private var dispatchSources: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: Int32] = [:]
    private var watchedPaths: [String] = []
    private var debounceTimers: [String: Timer] = [:]

    // Settings
    var debounceInterval: TimeInterval = 5.0  // Wait 5 seconds after change
    var autoSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: "autoSyncEnabled")
    }

    // MARK: - Watch Management

    /// Start watching files for changes using DispatchSource
    func startWatching(files: [ConfigFile]) {
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

        print("[FileWatcher] Starting watch for \(watchedPaths.count) files using DispatchSource")

        var successCount = 0
        for path in watchedPaths {
            if startWatchingFile(path: path) {
                successCount += 1
            }
        }

        if successCount > 0 {
            isWatching = true
            print("[FileWatcher] ✅ Now watching \(successCount)/\(watchedPaths.count) files")

            NotificationService.shared.notify(
                title: "Auto-Sync Enabled",
                body: "Watching \(successCount) config file(s) for changes"
            )
        } else {
            print("[FileWatcher] ⚠️ Failed to watch any files")
            NotificationService.shared.notify(
                title: "Auto-Sync Failed",
                body: "Could not start watching files. Check permissions."
            )
        }
    }

    /// Start watching a single file
    private func startWatchingFile(path: String) -> Bool {
        // Open file descriptor
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            print("[FileWatcher] ❌ Failed to open \(path): \(String(cString: strerror(errno)))")
            return false
        }

        // Create dispatch source to monitor writes and attribute changes
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .attrib],
            queue: DispatchQueue.main
        )

        // Store file descriptor for cleanup
        fileDescriptors[path] = fd

        // Handle file changes
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFileChange(paths: [path])
            }
        }

        // Cleanup on cancellation
        source.setCancelHandler {
            close(fd)
        }

        // Store and activate source
        dispatchSources[path] = source
        source.resume()

        print("[FileWatcher] Started watching: \(URL(fileURLWithPath: path).lastPathComponent)")
        return true
    }

    /// Stop watching files
    func stopWatching() {
        guard !dispatchSources.isEmpty else {
            // Already stopped
            isWatching = false
            return
        }

        print("[FileWatcher] Stopping file watcher...")

        // Cancel all dispatch sources (this will trigger cleanup handlers)
        for (path, source) in dispatchSources {
            source.cancel()
            print("[FileWatcher] Stopped watching: \(URL(fileURLWithPath: path).lastPathComponent)")
        }

        dispatchSources.removeAll()
        fileDescriptors.removeAll()
        isWatching = false

        // Cancel all pending timers
        debounceTimers.values.forEach { $0.invalidate() }
        debounceTimers.removeAll()

        print("[FileWatcher] ✅ Stopped watching all files")
    }

    deinit {
        // Ensure cleanup happens even if not called explicitly
        // Cancel all sources and close file descriptors
        for source in dispatchSources.values {
            source.cancel()
        }
        dispatchSources.removeAll()
        fileDescriptors.removeAll()
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
