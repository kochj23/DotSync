//
//  ConfigFile.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Represents a configuration file that can be synced
struct ConfigFile: Identifiable, Codable, Hashable {
    let id: UUID
    let path: String
    let relativePath: String // Path relative to home directory
    let filename: String
    let category: ConfigCategory
    let size: Int64
    let lastModified: Date
    let checksum: String
    let isSafeToSync: Bool
    let syncPriority: SyncPriority
    let isDirectory: Bool

    init(path: String, relativePath: String, filename: String, category: ConfigCategory,
         size: Int64, lastModified: Date, checksum: String, isSafeToSync: Bool,
         syncPriority: SyncPriority, isDirectory: Bool = false) {
        self.id = UUID()
        self.path = path
        self.relativePath = relativePath
        self.filename = filename
        self.category = category
        self.size = size
        self.lastModified = lastModified
        self.checksum = checksum
        self.isSafeToSync = isSafeToSync
        self.syncPriority = syncPriority
        self.isDirectory = isDirectory
    }

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var lastModifiedFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastModified, relativeTo: Date())
    }
}

/// Category of configuration file
enum ConfigCategory: String, Codable, CaseIterable {
    case shell = "Shell"
    case git = "Git"
    case editor = "Editor"
    case cloud = "Cloud"
    case docker = "Docker"
    case language = "Language"
    case claude = "Claude"
    case custom = "Custom"
    case documentation = "Documentation"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .shell: return "terminal"
        case .git: return "arrow.triangle.branch"
        case .editor: return "doc.text"
        case .cloud: return "cloud"
        case .docker: return "shippingbox"
        case .language: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "brain"
        case .custom: return "gear"
        case .documentation: return "doc.plaintext"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: String {
        switch self {
        case .shell: return "blue"
        case .git: return "orange"
        case .editor: return "purple"
        case .cloud: return "cyan"
        case .docker: return "indigo"
        case .language: return "green"
        case .claude: return "pink"
        case .custom: return "gray"
        case .documentation: return "yellow"
        case .unknown: return "gray"
        }
    }
}

/// Priority level for syncing
enum SyncPriority: String, Codable, CaseIterable, Comparable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    static func < (lhs: SyncPriority, rhs: SyncPriority) -> Bool {
        let order: [SyncPriority] = [.critical, .high, .medium, .low]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }

    var color: String {
        switch self {
        case .critical: return "red"
        case .high: return "orange"
        case .medium: return "yellow"
        case .low: return "green"
        }
    }
}

/// Sync status for a file
enum SyncState: String, Codable {
    case synced = "Synced"
    case localNewer = "Local Newer"
    case remoteNewer = "Remote Newer"
    case conflict = "Conflict"
    case notOnRemote = "Not on Remote"
    case notOnLocal = "Not on Local"
    case error = "Error"

    var icon: String {
        switch self {
        case .synced: return "checkmark.circle.fill"
        case .localNewer: return "arrow.up.circle.fill"
        case .remoteNewer: return "arrow.down.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        case .notOnRemote: return "arrow.up.circle"
        case .notOnLocal: return "arrow.down.circle"
        case .error: return "xmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .synced: return "green"
        case .localNewer: return "blue"
        case .remoteNewer: return "orange"
        case .conflict: return "red"
        case .notOnRemote: return "purple"
        case .notOnLocal: return "cyan"
        case .error: return "red"
        }
    }
}

/// Sync status wrapper
struct SyncStatus: Identifiable {
    let id = UUID()
    let file: ConfigFile
    var localVersion: Date?
    var remoteVersion: Date?
    var state: SyncState
    var error: Error?
}
