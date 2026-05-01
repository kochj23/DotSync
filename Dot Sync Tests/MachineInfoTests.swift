//
//  MachineInfoTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
@testable import Dot_Sync

final class MachineInfoTests: XCTestCase {

    // MARK: - MachineRole

    func testMasterCanUpload() {
        XCTAssertTrue(MachineRole.master.canUpload)
    }

    func testClientCannotUpload() {
        XCTAssertFalse(MachineRole.client.canUpload)
    }

    func testBothRolesCanDownload() {
        XCTAssertTrue(MachineRole.master.canDownload)
        XCTAssertTrue(MachineRole.client.canDownload)
    }

    func testMachineRoleDescriptions() {
        XCTAssertFalse(MachineRole.master.description.isEmpty)
        XCTAssertFalse(MachineRole.client.description.isEmpty)
        XCTAssertTrue(MachineRole.master.description.lowercased().contains("upload"))
        XCTAssertTrue(MachineRole.client.description.lowercased().contains("download"))
    }

    func testMachineRoleCodable() throws {
        for role in MachineRole.allCases {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(MachineRole.self, from: data)
            XCTAssertEqual(decoded, role)
        }
    }

    // MARK: - MachineInfo

    func testCurrentMachineInfo() {
        let info = MachineInfo.current
        XCTAssertFalse(info.id.isEmpty)
        XCTAssertFalse(info.hostname.isEmpty)
        XCTAssertFalse(info.username.isEmpty)
        XCTAssertFalse(info.osVersion.isEmpty)
        XCTAssertFalse(info.displayName.isEmpty)
    }

    func testCurrentMachineInfoContainsUsername() {
        let info = MachineInfo.current
        XCTAssertTrue(info.displayName.contains(info.username) || info.displayName.contains(info.hostname))
    }

    func testShortDisplayName() {
        let info = MachineInfo.current
        XCTAssertEqual(info.shortDisplayName, info.hostname)
    }

    func testFormattedLastSeen() {
        let info = MachineInfo.current
        XCTAssertFalse(info.formattedLastSeen.isEmpty)
    }

    // MARK: - SyncMetadata

    func testSyncMetadataCreate() {
        let file = ConfigFile(
            path: "/Users/test/.zshrc",
            relativePath: ".zshrc",
            filename: ".zshrc",
            category: .shell,
            size: 1024,
            lastModified: Date(),
            checksum: "abc123",
            isSafeToSync: true,
            syncPriority: .critical
        )

        let metadata = SyncMetadata.create(for: file)

        XCTAssertEqual(metadata.fileChecksum, "abc123")
        XCTAssertEqual(metadata.fileSize, 1024)
        XCTAssertFalse(metadata.machineInfo.id.isEmpty)
    }

    func testSyncMetadataCodable() throws {
        let file = ConfigFile(
            path: "/Users/test/.zshrc",
            relativePath: ".zshrc",
            filename: ".zshrc",
            category: .shell,
            size: 512,
            lastModified: Date(),
            checksum: "def",
            isSafeToSync: true,
            syncPriority: .critical
        )

        let original = SyncMetadata.create(for: file)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncMetadata.self, from: data)

        XCTAssertEqual(decoded.fileChecksum, original.fileChecksum)
        XCTAssertEqual(decoded.fileSize, original.fileSize)
        XCTAssertEqual(decoded.machineInfo.id, original.machineInfo.id)
    }
}
