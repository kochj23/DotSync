//
//  SyncOperationTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
@testable import Dot_Sync

final class SyncOperationTests: XCTestCase {

    // MARK: - SyncDirection

    func testSyncDirectionIcons() {
        XCTAssertFalse(SyncDirection.upload.icon.isEmpty)
        XCTAssertFalse(SyncDirection.download.icon.isEmpty)
        XCTAssertFalse(SyncDirection.skip.icon.isEmpty)
    }

    func testSyncDirectionRawValues() {
        XCTAssertEqual(SyncDirection.upload.rawValue, "Upload")
        XCTAssertEqual(SyncDirection.download.rawValue, "Download")
        XCTAssertEqual(SyncDirection.skip.rawValue, "Skip")
    }

    func testSyncDirectionCodable() throws {
        for direction in [SyncDirection.upload, .download, .skip] {
            let data = try JSONEncoder().encode(direction)
            let decoded = try JSONDecoder().decode(SyncDirection.self, from: data)
            XCTAssertEqual(decoded, direction)
        }
    }

    // MARK: - OperationStatus

    func testOperationStatusIcons() {
        for status in [OperationStatus.pending, .inProgress, .completed, .failed, .skipped] {
            XCTAssertFalse(status.icon.isEmpty, "\(status.rawValue) should have an icon")
        }
    }

    func testOperationStatusColors() {
        for status in [OperationStatus.pending, .inProgress, .completed, .failed, .skipped] {
            XCTAssertFalse(status.color.isEmpty, "\(status.rawValue) should have a color")
        }
    }

    // MARK: - SyncOperation

    func testSyncOperationInit() {
        let file = makeConfigFile()
        let op = SyncOperation(file: file, direction: .upload)

        XCTAssertEqual(op.file.filename, ".zshrc")
        XCTAssertEqual(op.direction, .upload)
        XCTAssertEqual(op.status, .pending)
    }

    func testSyncOperationStatusMutable() {
        let file = makeConfigFile()
        var op = SyncOperation(file: file, direction: .download)
        op.status = .completed
        XCTAssertEqual(op.status, .completed)
    }

    // MARK: - ConflictResolution

    func testConflictResolutionDescriptions() {
        XCTAssertFalse(ConflictResolution.useLocal.description.isEmpty)
        XCTAssertFalse(ConflictResolution.useRemote.description.isEmpty)
        XCTAssertFalse(ConflictResolution.merge.description.isEmpty)
        XCTAssertFalse(ConflictResolution.skip.description.isEmpty)
    }

    // MARK: - BackupVersion

    func testBackupVersionFormatting() {
        let backup = BackupVersion(
            path: "/tmp/test.backup.2026-01-01",
            date: Date(),
            size: 2048
        )

        XCTAssertFalse(backup.sizeFormatted.isEmpty)
        XCTAssertFalse(backup.dateFormatted.isEmpty)
    }

    // MARK: - ThreeWayMergeAttempt

    func testMergeAttemptCanAutoApply() {
        let attempt = ThreeWayMergeAttempt(
            success: true,
            mergedContent: "merged content",
            conflicts: [],
            reason: "Auto-merge succeeded"
        )

        XCTAssertTrue(attempt.canAutoApply)
    }

    func testMergeAttemptCannotAutoApplyWhenFailed() {
        let attempt = ThreeWayMergeAttempt(
            success: false,
            mergedContent: "partial merge",
            conflicts: [MergeConflict(lineNumber: 1, ancestorLine: "a", localLine: "b", remoteLine: "c")],
            reason: "Has conflicts"
        )

        XCTAssertFalse(attempt.canAutoApply)
    }

    func testMergeAttemptCannotAutoApplyWhenNilContent() {
        let attempt = ThreeWayMergeAttempt(
            success: true,
            mergedContent: nil,
            conflicts: [],
            reason: "No ancestor"
        )

        XCTAssertFalse(attempt.canAutoApply)
    }

    // MARK: - Helpers

    private func makeConfigFile() -> ConfigFile {
        ConfigFile(
            path: "/Users/test/.zshrc",
            relativePath: ".zshrc",
            filename: ".zshrc",
            category: .shell,
            size: 512,
            lastModified: Date(),
            checksum: "deadbeef",
            isSafeToSync: true,
            syncPriority: .critical
        )
    }
}
