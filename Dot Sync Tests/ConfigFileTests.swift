//
//  ConfigFileTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
@testable import Dot_Sync

final class ConfigFileTests: XCTestCase {

    // MARK: - ConfigFile Init

    func testConfigFileInit() {
        let now = Date()
        let file = ConfigFile(
            path: "/Users/test/.zshrc",
            relativePath: ".zshrc",
            filename: ".zshrc",
            category: .shell,
            size: 1024,
            lastModified: now,
            checksum: "abc123",
            isSafeToSync: true,
            syncPriority: .critical
        )

        XCTAssertEqual(file.path, "/Users/test/.zshrc")
        XCTAssertEqual(file.relativePath, ".zshrc")
        XCTAssertEqual(file.filename, ".zshrc")
        XCTAssertEqual(file.category, .shell)
        XCTAssertEqual(file.size, 1024)
        XCTAssertEqual(file.lastModified, now)
        XCTAssertEqual(file.checksum, "abc123")
        XCTAssertTrue(file.isSafeToSync)
        XCTAssertEqual(file.syncPriority, .critical)
        XCTAssertFalse(file.isDirectory)
    }

    func testConfigFileDirectoryFlag() {
        let file = ConfigFile(
            path: "/Users/test/.vim",
            relativePath: ".vim",
            filename: ".vim",
            category: .editor,
            size: 0,
            lastModified: Date(),
            checksum: "",
            isSafeToSync: true,
            syncPriority: .high,
            isDirectory: true
        )

        XCTAssertTrue(file.isDirectory)
    }

    func testConfigFileUUIDUniqueness() {
        let file1 = ConfigFile(
            path: "/Users/test/.zshrc", relativePath: ".zshrc", filename: ".zshrc",
            category: .shell, size: 100, lastModified: Date(), checksum: "a",
            isSafeToSync: true, syncPriority: .critical
        )
        let file2 = ConfigFile(
            path: "/Users/test/.zshrc", relativePath: ".zshrc", filename: ".zshrc",
            category: .shell, size: 100, lastModified: Date(), checksum: "a",
            isSafeToSync: true, syncPriority: .critical
        )

        XCTAssertNotEqual(file1.id, file2.id, "Each ConfigFile instance should get a unique UUID")
    }

    // MARK: - Size Formatting

    func testSizeFormattedZeroBytes() {
        let file = makeConfigFile(size: 0)
        XCTAssertFalse(file.sizeFormatted.isEmpty)
    }

    func testSizeFormattedKilobytes() {
        let file = makeConfigFile(size: 1024)
        // ByteCountFormatter should produce a non-empty string
        XCTAssertFalse(file.sizeFormatted.isEmpty)
    }

    func testSizeFormattedMegabytes() {
        let file = makeConfigFile(size: 1_048_576)
        XCTAssertFalse(file.sizeFormatted.isEmpty)
    }

    // MARK: - ConfigCategory

    func testAllCategoriesHaveIcons() {
        for category in ConfigCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category.rawValue) should have an icon")
        }
    }

    func testAllCategoriesHaveColors() {
        for category in ConfigCategory.allCases {
            XCTAssertFalse(category.color.isEmpty, "\(category.rawValue) should have a color")
        }
    }

    func testFilterCategoryIsOnlyEverything() {
        for category in ConfigCategory.allCases {
            if category == .everything {
                XCTAssertTrue(category.isFilterCategory)
            } else {
                XCTAssertFalse(category.isFilterCategory,
                               "\(category.rawValue) should not be a filter category")
            }
        }
    }

    func testCategoryRawValues() {
        XCTAssertEqual(ConfigCategory.shell.rawValue, "Shell")
        XCTAssertEqual(ConfigCategory.git.rawValue, "Git")
        XCTAssertEqual(ConfigCategory.editor.rawValue, "Editor")
        XCTAssertEqual(ConfigCategory.cloud.rawValue, "Cloud")
        XCTAssertEqual(ConfigCategory.docker.rawValue, "Docker")
        XCTAssertEqual(ConfigCategory.claude.rawValue, "Claude")
        XCTAssertEqual(ConfigCategory.documentation.rawValue, "Documentation")
    }

    // MARK: - SyncPriority

    func testSyncPriorityOrdering() {
        XCTAssertTrue(SyncPriority.critical < SyncPriority.high)
        XCTAssertTrue(SyncPriority.high < SyncPriority.medium)
        XCTAssertTrue(SyncPriority.medium < SyncPriority.low)
        XCTAssertFalse(SyncPriority.low < SyncPriority.critical)
    }

    func testSyncPriorityEquality() {
        XCTAssertFalse(SyncPriority.critical < SyncPriority.critical)
        XCTAssertFalse(SyncPriority.high < SyncPriority.high)
    }

    func testAllPrioritiesHaveColors() {
        for priority in SyncPriority.allCases {
            XCTAssertFalse(priority.color.isEmpty, "\(priority.rawValue) should have a color")
        }
    }

    // MARK: - SyncState

    func testSyncStateIcons() {
        for state in [SyncState.synced, .localNewer, .remoteNewer, .conflict, .notOnRemote, .notOnLocal, .error] {
            XCTAssertFalse(state.icon.isEmpty, "\(state.rawValue) should have an icon")
        }
    }

    func testSyncStateColors() {
        for state in [SyncState.synced, .localNewer, .remoteNewer, .conflict, .notOnRemote, .notOnLocal, .error] {
            XCTAssertFalse(state.color.isEmpty, "\(state.rawValue) should have a color")
        }
    }

    func testSyncStateRoundTrip() {
        for state in [SyncState.synced, .localNewer, .remoteNewer, .conflict, .notOnRemote, .notOnLocal, .error] {
            let encoded = state.rawValue
            let decoded = SyncState(rawValue: encoded)
            XCTAssertEqual(decoded, state)
        }
    }

    // MARK: - SyncStatus

    func testSyncStatusInit() {
        let file = makeConfigFile()
        let status = SyncStatus(file: file, localVersion: Date(), remoteVersion: nil, state: .notOnRemote)
        XCTAssertEqual(status.state, .notOnRemote)
        XCTAssertNotNil(status.localVersion)
        XCTAssertNil(status.remoteVersion)
        XCTAssertNil(status.error)
    }

    // MARK: - Codable Conformance

    func testConfigFileCodable() throws {
        let original = makeConfigFile()
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ConfigFile.self, from: data)

        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.filename, original.filename)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.size, original.size)
        XCTAssertEqual(decoded.checksum, original.checksum)
        XCTAssertEqual(decoded.isSafeToSync, original.isSafeToSync)
        XCTAssertEqual(decoded.syncPriority, original.syncPriority)
    }

    func testConfigCategoryCodable() throws {
        for category in ConfigCategory.allCases {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(ConfigCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }

    // MARK: - Hashable Conformance

    func testConfigFileHashable() {
        let file1 = makeConfigFile()
        let file2 = makeConfigFile()
        var set: Set<ConfigFile> = []
        set.insert(file1)
        set.insert(file2)
        XCTAssertEqual(set.count, 2, "Different ConfigFile instances should be unique in a set")
    }

    // MARK: - Helpers

    private func makeConfigFile(
        path: String = "/Users/test/.zshrc",
        size: Int64 = 512
    ) -> ConfigFile {
        ConfigFile(
            path: path,
            relativePath: ".zshrc",
            filename: ".zshrc",
            category: .shell,
            size: size,
            lastModified: Date(),
            checksum: "deadbeef",
            isSafeToSync: true,
            syncPriority: .critical
        )
    }
}
