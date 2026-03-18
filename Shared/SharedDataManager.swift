//
//  SharedDataManager.swift
//  Dot Sync
//
//  Shared between main app and widget extension
//  Created by Jordan Koch on 2/4/26.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

/// Manages shared data between the main app and widget using App Groups
final class SharedDataManager {
    static let shared = SharedDataManager()

    /// App Group identifier for data sharing
    private let appGroupIdentifier = "group.com.jkoch.dotsync"

    /// Key for storing sync data in UserDefaults
    private let syncDataKey = "widgetSyncData"

    /// Shared UserDefaults container
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    private init() {}

    // MARK: - Writing Data (Main App)

    /// Save sync data for widget consumption
    func saveSyncData(_ data: WidgetSyncData) {
        guard let defaults = sharedDefaults else {
            print("[SharedDataManager] Failed to access shared UserDefaults")
            return
        }

        do {
            let encoded = try JSONEncoder().encode(data)
            defaults.set(encoded, forKey: syncDataKey)
            defaults.synchronize()
            print("[SharedDataManager] Saved sync data to app group")

            // Request widget refresh
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: "DotSyncWidget")
            #endif
        } catch {
            print("[SharedDataManager] Failed to encode sync data: \(error)")
        }
    }

    /// Update sync status from main app state
    func updateFromSyncEngine(
        isSyncing: Bool,
        lastSyncDate: Date?,
        syncStatuses: [(state: String, count: Int)],
        totalFiles: Int
    ) {
        // Calculate status
        let status: WidgetSyncStatus
        var conflictCount = 0
        var pendingCount = 0

        for statusItem in syncStatuses {
            switch statusItem.state {
            case "conflict":
                conflictCount += statusItem.count
            case "localNewer", "remoteNewer", "notOnRemote":
                pendingCount += statusItem.count
            default:
                break
            }
        }

        if isSyncing {
            status = .syncing
        } else if conflictCount > 0 {
            status = .conflicts
        } else if pendingCount > 0 {
            status = .pending
        } else if lastSyncDate != nil {
            status = .synced
        } else {
            status = .unknown
        }

        let data = WidgetSyncData(
            lastSyncDate: lastSyncDate,
            status: status,
            filesNeedingSync: pendingCount,
            conflictCount: conflictCount,
            totalTrackedFiles: totalFiles
        )

        saveSyncData(data)
    }

    // MARK: - Reading Data (Widget)

    /// Load sync data for widget display
    func loadSyncData() -> WidgetSyncData {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: syncDataKey) else {
            print("[SharedDataManager] No sync data found, returning empty")
            return .empty
        }

        do {
            let decoded = try JSONDecoder().decode(WidgetSyncData.self, from: data)
            return decoded
        } catch {
            print("[SharedDataManager] Failed to decode sync data: \(error)")
            return .empty
        }
    }

    // MARK: - Widget Actions

    /// URL scheme for triggering sync from widget
    static let syncNowURL = URL(string: "dotsync://sync-now")!

    /// URL scheme for opening the app
    static let openAppURL = URL(string: "dotsync://open")!

    /// Check if data is stale (older than 1 hour)
    func isDataStale() -> Bool {
        let data = loadSyncData()
        let staleThreshold: TimeInterval = 3600 // 1 hour
        return Date().timeIntervalSince(data.lastUpdated) > staleThreshold
    }
}

// MARK: - Main App Integration Extension

extension SharedDataManager {
    /// Convenience method to update widget from SyncEngine state
    /// Call this from the main app whenever sync state changes
    func updateWidget(
        isSyncing: Bool,
        lastSyncDate: Date?,
        conflictCount: Int,
        localNewerCount: Int,
        remoteNewerCount: Int,
        notOnRemoteCount: Int,
        totalFiles: Int
    ) {
        let status: WidgetSyncStatus
        let pendingCount = localNewerCount + remoteNewerCount + notOnRemoteCount

        if isSyncing {
            status = .syncing
        } else if conflictCount > 0 {
            status = .conflicts
        } else if pendingCount > 0 {
            status = .pending
        } else if lastSyncDate != nil {
            status = .synced
        } else {
            status = .unknown
        }

        let data = WidgetSyncData(
            lastSyncDate: lastSyncDate,
            status: status,
            filesNeedingSync: pendingCount,
            conflictCount: conflictCount,
            totalTrackedFiles: totalFiles
        )

        saveSyncData(data)
    }
}
