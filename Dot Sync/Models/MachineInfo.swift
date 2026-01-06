//
//  MachineInfo.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/6/26.
//

import Foundation
import SystemConfiguration

/// Machine identification and tracking
struct MachineInfo: Codable, Identifiable {
    let id: String // Unique machine ID
    let hostname: String
    let username: String
    let osVersion: String
    let lastSeen: Date
    let displayName: String // User-friendly name

    static var current: MachineInfo {
        let host = Host.current()
        let hostname = host.localizedName ?? host.name ?? "Unknown"
        let username = NSUserName()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        // Generate stable machine ID from hardware UUID
        let machineID = getMachineUUID() ?? UUID().uuidString

        let displayName = "\(hostname) (\(username))"

        return MachineInfo(
            id: machineID,
            hostname: hostname,
            username: username,
            osVersion: osVersion,
            lastSeen: Date(),
            displayName: displayName
        )
    }

    /// Get hardware UUID for stable machine identification
    private static func getMachineUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        guard platformExpert != 0 else { return nil }

        defer { IOObjectRelease(platformExpert) }

        guard let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) else {
            return nil
        }

        guard let uuid = serialNumberAsCFString.takeRetainedValue() as? String else {
            return nil
        }

        return uuid
    }

    var shortDisplayName: String {
        hostname
    }

    var formattedLastSeen: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }
}

/// Metadata attached to synced files
struct SyncMetadata: Codable {
    let machineInfo: MachineInfo
    let syncDate: Date
    let fileChecksum: String
    let fileSize: Int64

    /// Create metadata for current upload
    static func create(for file: ConfigFile) -> SyncMetadata {
        SyncMetadata(
            machineInfo: MachineInfo.current,
            syncDate: Date(),
            fileChecksum: file.checksum,
            fileSize: file.size
        )
    }
}
