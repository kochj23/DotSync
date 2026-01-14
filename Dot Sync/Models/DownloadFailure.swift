//
//  DownloadFailure.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/14/26.
//

import Foundation

/// Represents a file download failure with detailed error information
struct DownloadFailure: Identifiable, Codable {
    let id: UUID
    let filename: String
    let filePath: String
    let errorMessage: String
    let errorCode: String?
    let timestamp: Date

    init(filename: String, filePath: String, error: Error) {
        self.id = UUID()
        self.filename = filename
        self.filePath = filePath
        self.timestamp = Date()

        // Extract detailed error information
        if let cloudError = error as? CloudStorageError {
            self.errorMessage = cloudError.errorDescription ?? "Unknown cloud storage error"
            self.errorCode = "CloudStorageError"
        } else {
            let nsError = error as NSError
            self.errorMessage = nsError.localizedDescription
            self.errorCode = "\(nsError.domain):\(nsError.code)"
        }
    }

    /// Formatted error description for display
    var formattedDescription: String {
        var result = "File: \(filename)\n"
        result += "Path: \(filePath)\n"
        result += "Error: \(errorMessage)\n"
        if let code = errorCode {
            result += "Code: \(code)\n"
        }
        result += "Time: \(timestamp.formatted(date: .abbreviated, time: .shortened))\n"
        return result
    }
}

/// Collection of download failures for a sync operation
struct FailureSummary: Identifiable {
    let id: UUID
    let timestamp: Date
    let totalFiles: Int
    let successCount: Int
    let failureCount: Int
    let failures: [DownloadFailure]

    init(totalFiles: Int, successCount: Int, failures: [DownloadFailure]) {
        self.id = UUID()
        self.timestamp = Date()
        self.totalFiles = totalFiles
        self.successCount = successCount
        self.failureCount = failures.count
        self.failures = failures
    }

    /// Generate copyable text summary
    var copyableText: String {
        var text = "=== DotSync Download Failure Summary ===\n"
        text += "Timestamp: \(timestamp.formatted(date: .long, time: .complete))\n"
        text += "Total Files: \(totalFiles)\n"
        text += "Successful: \(successCount)\n"
        text += "Failed: \(failureCount)\n"
        text += "\n=== Failed Files ===\n\n"

        for (index, failure) in failures.enumerated() {
            text += "[\(index + 1)] \(failure.formattedDescription)\n"
        }

        text += "\n=== End of Report ===\n"
        return text
    }
}
