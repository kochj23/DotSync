//
//  SyncProgressView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/12/26.
//

import SwiftUI

/// Sync progress overlay with detailed progress information
struct SyncProgressOverlay: View {
    let progress: SyncProgress
    let onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // Header with operation type
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                    .padding(.trailing, 4)

                Text(progress.operation.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if let onCancel = onCancel {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            // Current file
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current File")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(progress.currentFile)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .help(progress.currentFile)
                }

                Spacer()

                Text("\(progress.currentIndex) of \(progress.totalFiles)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress.progress) {
                    HStack {
                        Text("Progress")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(progress.progressPercentage)%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .progressViewStyle(.linear)
            }

            // Speed and time remaining
            HStack {
                Label(progress.speed, systemImage: "speedometer")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Label(progress.estimatedTimeRemainingFormatted, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 400, maxWidth: 500)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Full-screen overlay that dims background during sync
struct SyncProgressFullScreenOverlay: View {
    let progress: SyncProgress?
    let onCancel: (() -> Void)?

    var body: some View {
        ZStack {
            if progress != nil {
                // Semi-transparent background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .transition(.opacity)

                // Progress view
                if let progress = progress {
                    SyncProgressOverlay(progress: progress, onCancel: onCancel)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress != nil)
    }
}
