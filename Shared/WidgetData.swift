//
//  WidgetData.swift
//  Dot Sync
//
//  Shared between main app and widget extension
//  Created by Jordan Koch on 2/4/26.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

/// Sync status that can be displayed in the widget
enum WidgetSyncStatus: String, Codable {
    case synced = "Synced"
    case pending = "Pending"
    case conflicts = "Conflicts"
    case syncing = "Syncing"
    case error = "Error"
    case unknown = "Unknown"

    var iconName: String {
        switch self {
        case .synced: return "checkmark.circle.fill"
        case .pending: return "arrow.triangle.2.circlepath.circle.fill"
        case .conflicts: return "exclamationmark.triangle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .error: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    var colorName: String {
        switch self {
        case .synced: return "green"
        case .pending: return "orange"
        case .conflicts: return "red"
        case .syncing: return "blue"
        case .error: return "red"
        case .unknown: return "gray"
        }
    }

    var description: String {
        switch self {
        case .synced: return "All files synchronized"
        case .pending: return "Files waiting to sync"
        case .conflicts: return "Conflicts need resolution"
        case .syncing: return "Sync in progress..."
        case .error: return "Sync error occurred"
        case .unknown: return "Status unknown"
        }
    }
}

/// Data model for widget display
struct WidgetSyncData: Codable {
    let lastSyncDate: Date?
    let status: WidgetSyncStatus
    let filesNeedingSync: Int
    let conflictCount: Int
    let totalTrackedFiles: Int
    let lastUpdated: Date

    init(
        lastSyncDate: Date? = nil,
        status: WidgetSyncStatus = .unknown,
        filesNeedingSync: Int = 0,
        conflictCount: Int = 0,
        totalTrackedFiles: Int = 0
    ) {
        self.lastSyncDate = lastSyncDate
        self.status = status
        self.filesNeedingSync = filesNeedingSync
        self.conflictCount = conflictCount
        self.totalTrackedFiles = totalTrackedFiles
        self.lastUpdated = Date()
    }

    /// Formatted last sync time for display
    var formattedLastSync: String {
        guard let date = lastSyncDate else {
            return "Never"
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    /// Summary text for widget display
    var summaryText: String {
        if conflictCount > 0 {
            return "\(conflictCount) conflict\(conflictCount == 1 ? "" : "s")"
        } else if filesNeedingSync > 0 {
            return "\(filesNeedingSync) file\(filesNeedingSync == 1 ? "" : "s") pending"
        } else if totalTrackedFiles > 0 {
            return "\(totalTrackedFiles) file\(totalTrackedFiles == 1 ? "" : "s") tracked"
        } else {
            return "No files configured"
        }
    }

    /// Default/placeholder data
    static var placeholder: WidgetSyncData {
        WidgetSyncData(
            lastSyncDate: Date().addingTimeInterval(-3600),
            status: .synced,
            filesNeedingSync: 0,
            conflictCount: 0,
            totalTrackedFiles: 12
        )
    }

    /// Empty state data
    static var empty: WidgetSyncData {
        WidgetSyncData()
    }
}

#if canImport(WidgetKit)
/// Timeline entry for the widget
struct DotSyncWidgetEntry: TimelineEntry {
    let date: Date
    let syncData: WidgetSyncData

    static var placeholder: DotSyncWidgetEntry {
        DotSyncWidgetEntry(date: Date(), syncData: .placeholder)
    }

    static var empty: DotSyncWidgetEntry {
        DotSyncWidgetEntry(date: Date(), syncData: .empty)
    }
}
#endif
