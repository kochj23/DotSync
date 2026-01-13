//
//  SyncProgress.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/12/26.
//

import Foundation

/// Real-time sync progress tracking
struct SyncProgress: Identifiable {
    let id = UUID()
    let currentFile: String
    let currentIndex: Int
    let totalFiles: Int
    let bytesTransferred: Int64
    let totalBytes: Int64
    let operation: SyncOperation
    let startTime: Date

    enum SyncOperation: String {
        case uploading = "Uploading"
        case downloading = "Downloading"
        case scanning = "Scanning"
        case analyzing = "Analyzing"
    }

    var progress: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(currentIndex) / Double(totalFiles)
    }

    var progressPercentage: Int {
        Int(progress * 100)
    }

    var speed: String {
        let elapsed = Date().timeIntervalSince(startTime)
        guard elapsed > 0, bytesTransferred > 0 else { return "Calculating..." }

        let bytesPerSecond = Double(bytesTransferred) / elapsed
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    var estimatedTimeRemaining: TimeInterval? {
        let elapsed = Date().timeIntervalSince(startTime)
        guard elapsed > 0, currentIndex > 0, totalFiles > currentIndex else { return nil }

        let averageTimePerFile = elapsed / Double(currentIndex)
        let remainingFiles = totalFiles - currentIndex
        return averageTimePerFile * Double(remainingFiles)
    }

    var estimatedTimeRemainingFormatted: String {
        guard let timeRemaining = estimatedTimeRemaining else { return "Calculating..." }

        if timeRemaining < 60 {
            return "\(Int(timeRemaining))s remaining"
        } else if timeRemaining < 3600 {
            let minutes = Int(timeRemaining / 60)
            return "\(minutes)m remaining"
        } else {
            let hours = Int(timeRemaining / 3600)
            let minutes = Int((timeRemaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m remaining"
        }
    }
}

/// Toast notification types
enum ToastType {
    case success
    case error
    case info
    case warning

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .success: return "green"
        case .error: return "red"
        case .info: return "blue"
        case .warning: return "orange"
        }
    }
}

/// Toast notification message
struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    let message: String
    let duration: TimeInterval

    init(type: ToastType, title: String, message: String, duration: TimeInterval = 5.0) {
        self.type = type
        self.title = title
        self.message = message
        self.duration = duration
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}
