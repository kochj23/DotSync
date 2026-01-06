//
//  SyncOperation.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Represents a sync operation
struct SyncOperation: Identifiable {
    let id = UUID()
    let file: ConfigFile
    let direction: SyncDirection
    let timestamp: Date
    var status: OperationStatus

    init(file: ConfigFile, direction: SyncDirection) {
        self.file = file
        self.direction = direction
        self.timestamp = Date()
        self.status = .pending
    }
}

/// Direction of sync operation
enum SyncDirection: String, Codable {
    case upload = "Upload"
    case download = "Download"
    case skip = "Skip"

    var icon: String {
        switch self {
        case .upload: return "arrow.up.circle.fill"
        case .download: return "arrow.down.circle.fill"
        case .skip: return "minus.circle"
        }
    }
}

/// Status of sync operation
enum OperationStatus: String {
    case pending = "Pending"
    case inProgress = "In Progress"
    case completed = "Completed"
    case failed = "Failed"
    case skipped = "Skipped"

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }

    var color: String {
        switch self {
        case .pending: return "gray"
        case .inProgress: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .skipped: return "yellow"
        }
    }
}

/// Conflict resolution choice
enum ConflictResolution {
    case useLocal
    case useRemote
    case merge
    case skip

    var description: String {
        switch self {
        case .useLocal: return "Keep local version"
        case .useRemote: return "Use remote version"
        case .merge: return "Merge manually"
        case .skip: return "Skip for now"
        }
    }
}

/// Backup version information
struct BackupVersion: Identifiable {
    let id = UUID()
    let path: String
    let date: Date
    let size: Int64

    var sizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var dateFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Result of three-way merge attempt
struct ThreeWayMergeAttempt {
    let success: Bool
    let mergedContent: String?
    let conflicts: [MergeConflict]
    let reason: String

    var canAutoApply: Bool {
        success && mergedContent != nil
    }
}

/// Individual merge conflict (for three-way merge)
struct MergeConflict: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let ancestorLine: String
    let localLine: String
    let remoteLine: String

    var description: String {
        """
        Line \(lineNumber):
        Ancestor: \(ancestorLine.isEmpty ? "(empty)" : ancestorLine)
        Local:    \(localLine.isEmpty ? "(empty)" : localLine)
        Remote:   \(remoteLine.isEmpty ? "(empty)" : remoteLine)
        """
    }
}
