//
//  FailureSummaryView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/14/26.
//

import SwiftUI

/// Persistent dialog showing download failures with copyable text
struct FailureSummaryView: View {
    let summary: FailureSummary
    @Environment(\.dismiss) private var dismiss
    @State private var showingCopyConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Download Failures")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("\(summary.failureCount) of \(summary.totalFiles) files failed to download")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(summary.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .background(Color.red.opacity(0.05))

            Divider()

            // Statistics
            HStack(spacing: 40) {
                StatView(title: "Total", value: "\(summary.totalFiles)", color: .primary)
                StatView(title: "Success", value: "\(summary.successCount)", color: .green)
                StatView(title: "Failed", value: "\(summary.failureCount)", color: .red)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))

            Divider()

            // Failed files list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(summary.failures.enumerated()), id: \.element.id) { index, failure in
                        FailureRowView(failure: failure, index: index + 1)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 400)

            Divider()

            // Copy button and full details
            VStack(spacing: 12) {
                HStack {
                    Text("Copyable Details:")
                        .font(.headline)
                    Spacer()
                }

                TextEditor(text: .constant(summary.copyableText))
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 120)
                    .border(Color.secondary.opacity(0.3))
                    .textSelection(.enabled)

                HStack {
                    Button(action: {
                        copyToClipboard(summary.copyableText)
                    }) {
                        Label("Copy All to Clipboard", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    if showingCopyConfirmation {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Copied!")
                                .foregroundColor(.green)
                        }
                        .transition(.scale)
                    }

                    Spacer()

                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
        }
        .frame(width: 800, height: 700)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation {
            showingCopyConfirmation = true
        }

        // Hide confirmation after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation {
                showingCopyConfirmation = false
            }
        }
    }
}

// MARK: - Stat View

struct StatView: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Failure Row

struct FailureRowView: View {
    let failure: DownloadFailure
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Index badge
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 32, height: 32)

                Text("\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Filename
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.red)
                    Text(failure.filename)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }

                // Path
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(failure.filePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Error message
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(failure.errorMessage)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)

                // Error code
                if let code = failure.errorCode {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text("Error Code: \(code)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Timestamp
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(failure.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    let testFailures = [
        DownloadFailure(
            filename: ".zshrc",
            filePath: "configs/shell/.zshrc",
            error: NSError(
                domain: "CloudStorageError",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "File not found at: /path/to/file"]
            )
        ),
        DownloadFailure(
            filename: ".gitconfig",
            filePath: "configs/development/.gitconfig",
            error: NSError(
                domain: "NetworkError",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Connection timeout while downloading file"]
            )
        ),
        DownloadFailure(
            filename: ".bash_profile",
            filePath: "configs/shell/.bash_profile",
            error: NSError(
                domain: "PermissionError",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Permission denied: Cannot write to destination"]
            )
        )
    ]

    let summary = FailureSummary(
        totalFiles: 15,
        successCount: 12,
        failures: testFailures
    )

    return FailureSummaryView(summary: summary)
}
