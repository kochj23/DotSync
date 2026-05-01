//
//  SyncProgressTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
@testable import Dot_Sync

final class SyncProgressTests: XCTestCase {

    // MARK: - Progress Calculation

    func testProgressZeroFiles() {
        let progress = SyncProgress(
            currentFile: "test",
            currentIndex: 0,
            totalFiles: 0,
            bytesTransferred: 0,
            totalBytes: 0,
            operation: .uploading,
            startTime: Date()
        )

        XCTAssertEqual(progress.progress, 0)
        XCTAssertEqual(progress.progressPercentage, 0)
    }

    func testProgressHalfway() {
        let progress = SyncProgress(
            currentFile: "test",
            currentIndex: 5,
            totalFiles: 10,
            bytesTransferred: 500,
            totalBytes: 1000,
            operation: .uploading,
            startTime: Date()
        )

        XCTAssertEqual(progress.progress, 0.5, accuracy: 0.01)
        XCTAssertEqual(progress.progressPercentage, 50)
    }

    func testProgressComplete() {
        let progress = SyncProgress(
            currentFile: "test",
            currentIndex: 10,
            totalFiles: 10,
            bytesTransferred: 1000,
            totalBytes: 1000,
            operation: .downloading,
            startTime: Date()
        )

        XCTAssertEqual(progress.progress, 1.0, accuracy: 0.01)
        XCTAssertEqual(progress.progressPercentage, 100)
    }

    // MARK: - Speed Calculation

    func testSpeedCalculatingWhenNoData() {
        let progress = SyncProgress(
            currentFile: "test",
            currentIndex: 0,
            totalFiles: 5,
            bytesTransferred: 0,
            totalBytes: 5000,
            operation: .uploading,
            startTime: Date()
        )

        XCTAssertEqual(progress.speed, "Calculating...")
    }

    // MARK: - ETA

    func testETANilWhenNotStarted() {
        let progress = SyncProgress(
            currentFile: "test",
            currentIndex: 0,
            totalFiles: 10,
            bytesTransferred: 0,
            totalBytes: 10000,
            operation: .uploading,
            startTime: Date()
        )

        XCTAssertNil(progress.estimatedTimeRemaining)
    }

    func testETAFormattedWhenNotStarted() {
        let progress = SyncProgress(
            currentFile: "test",
            currentIndex: 0,
            totalFiles: 10,
            bytesTransferred: 0,
            totalBytes: 10000,
            operation: .uploading,
            startTime: Date()
        )

        XCTAssertEqual(progress.estimatedTimeRemainingFormatted, "Calculating...")
    }

    // MARK: - SyncProgress.SyncOperation

    func testSyncOperationRawValues() {
        XCTAssertEqual(SyncProgress.SyncOperation.uploading.rawValue, "Uploading")
        XCTAssertEqual(SyncProgress.SyncOperation.downloading.rawValue, "Downloading")
        XCTAssertEqual(SyncProgress.SyncOperation.scanning.rawValue, "Scanning")
        XCTAssertEqual(SyncProgress.SyncOperation.analyzing.rawValue, "Analyzing")
    }

    // MARK: - ToastType

    func testToastTypeIcons() {
        XCTAssertFalse(ToastType.success.icon.isEmpty)
        XCTAssertFalse(ToastType.error.icon.isEmpty)
        XCTAssertFalse(ToastType.info.icon.isEmpty)
        XCTAssertFalse(ToastType.warning.icon.isEmpty)
    }

    func testToastTypeColors() {
        XCTAssertEqual(ToastType.success.color, "green")
        XCTAssertEqual(ToastType.error.color, "red")
        XCTAssertEqual(ToastType.info.color, "blue")
        XCTAssertEqual(ToastType.warning.color, "orange")
    }

    // MARK: - ToastMessage

    func testToastMessageInit() {
        let toast = ToastMessage(type: .success, title: "Done", message: "Sync complete")

        XCTAssertEqual(toast.type, .success)
        XCTAssertEqual(toast.title, "Done")
        XCTAssertEqual(toast.message, "Sync complete")
        XCTAssertEqual(toast.duration, 5.0)
    }

    func testToastMessageCustomDuration() {
        let toast = ToastMessage(type: .error, title: "Error", message: "Failed", duration: 10.0)
        XCTAssertEqual(toast.duration, 10.0)
    }

    func testToastMessageEquality() {
        let toast1 = ToastMessage(type: .info, title: "A", message: "B")
        let toast2 = ToastMessage(type: .info, title: "A", message: "B")
        // Different instances should not be equal (different UUIDs)
        XCTAssertNotEqual(toast1, toast2)
    }

    func testToastMessageSelfEquality() {
        let toast = ToastMessage(type: .info, title: "A", message: "B")
        XCTAssertEqual(toast, toast)
    }

    // MARK: - DownloadFailure

    func testDownloadFailureInit() {
        let error = NSError(domain: "test", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Connection refused"
        ])

        let failure = DownloadFailure(filename: ".zshrc", filePath: "/home/.zshrc", error: error)

        XCTAssertEqual(failure.filename, ".zshrc")
        XCTAssertEqual(failure.filePath, "/home/.zshrc")
        XCTAssertTrue(failure.errorMessage.contains("Connection refused"))
        XCTAssertEqual(failure.errorCode, "test:42")
    }

    func testDownloadFailureWithCloudStorageError() {
        let error = CloudStorageError.notConfigured

        let failure = DownloadFailure(filename: ".gitconfig", filePath: "/home/.gitconfig", error: error)

        XCTAssertEqual(failure.errorCode, "CloudStorageError")
        XCTAssertTrue(failure.errorMessage.contains("not configured"))
    }

    func testDownloadFailureFormattedDescription() {
        let error = NSError(domain: "test", code: 1)
        let failure = DownloadFailure(filename: ".vimrc", filePath: "/home/.vimrc", error: error)

        let desc = failure.formattedDescription
        XCTAssertTrue(desc.contains("File: .vimrc"))
        XCTAssertTrue(desc.contains("Path: /home/.vimrc"))
        XCTAssertTrue(desc.contains("Error:"))
    }

    // MARK: - FailureSummary

    func testFailureSummaryInit() {
        let failures = [
            DownloadFailure(filename: "a", filePath: "/a", error: NSError(domain: "t", code: 1)),
            DownloadFailure(filename: "b", filePath: "/b", error: NSError(domain: "t", code: 2)),
        ]

        let summary = FailureSummary(totalFiles: 10, successCount: 8, failures: failures)

        XCTAssertEqual(summary.totalFiles, 10)
        XCTAssertEqual(summary.successCount, 8)
        XCTAssertEqual(summary.failureCount, 2)
        XCTAssertEqual(summary.failures.count, 2)
    }

    func testFailureSummaryCopyableText() {
        let failures = [
            DownloadFailure(filename: ".zshrc", filePath: "/home/.zshrc",
                          error: NSError(domain: "net", code: -1009))
        ]

        let summary = FailureSummary(totalFiles: 5, successCount: 4, failures: failures)
        let text = summary.copyableText

        XCTAssertTrue(text.contains("DotSync Download Failure Summary"))
        XCTAssertTrue(text.contains("Total Files: 5"))
        XCTAssertTrue(text.contains("Successful: 4"))
        XCTAssertTrue(text.contains("Failed: 1"))
        XCTAssertTrue(text.contains(".zshrc"))
    }
}
