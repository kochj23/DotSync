//
//  ConflictResolutionView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import SwiftUI

/// Full conflict resolution UI with side-by-side diff
struct ConflictResolutionView: View {
    let file: ConfigFile
    let localContent: String
    let remoteContent: String
    let localDate: Date
    let remoteDate: Date

    @Environment(\.dismiss) private var dismiss
    @State private var selectedResolution: ConflictResolution?
    @State private var isResolving = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading) {
                        Text("Conflict Detected")
                            .font(.title)
                        Text(file.filename)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Text("Both local and remote versions have been modified. Choose which version to keep.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()

            Divider()

            // Side-by-side diff
            HSplitView {
                // Left: Local version
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Local (This Mac)")
                                .font(.headline)
                            Text("Modified: \(localDate.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(localContent.count) bytes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))

                    Divider()

                    DiffView(content: localContent, otherContent: remoteContent, title: "")
                }

                // Right: Remote version
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Remote (Cloud)")
                                .font(.headline)
                            Text("Modified: \(remoteDate.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(remoteContent.count) bytes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))

                    Divider()

                    DiffView(content: remoteContent, otherContent: localContent, title: "")
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: { selectResolution(.useLocal) }) {
                    Label("Keep Local", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .help("Upload your local version to cloud")

                Button(action: { selectResolution(.useRemote) }) {
                    Label("Use Remote", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help("Download cloud version to this machine")

                Button(action: openInEditor) {
                    Label("Open in Editor", systemImage: "pencil")
                }
                .help("Open both files in your default editor for manual merging")
            }
            .padding()
            .disabled(isResolving)

            if isResolving {
                ProgressView("Resolving conflict...")
                    .padding(.bottom)
            }
        }
        .frame(width: 1000, height: 700)
    }

    private func selectResolution(_ resolution: ConflictResolution) {
        selectedResolution = resolution
        isResolving = true

        Task {
            do {
                try await SyncEngine.shared.resolveConflict(for: file, resolution: resolution)

                await MainActor.run {
                    isResolving = false
                    dismiss()
                }

                // Show success notification
                NotificationService.shared.notify(
                    title: "Conflict Resolved",
                    body: "\(file.filename) - using \(resolution.description)"
                )
            } catch {
                await MainActor.run {
                    isResolving = false
                }
                print("[ConflictResolution] Error: \(error)")
            }
        }
    }

    private func openInEditor() {
        // Save both versions to temp files and open
        let tempDir = FileManager.default.temporaryDirectory

        let localFile = tempDir.appendingPathComponent("\(file.filename).local")
        let remoteFile = tempDir.appendingPathComponent("\(file.filename).remote")

        try? localContent.data(using: .utf8)?.write(to: localFile)
        try? remoteContent.data(using: .utf8)?.write(to: remoteFile)

        // Open in default editor
        NSWorkspace.shared.open([localFile, remoteFile],
                               withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                               configuration: NSWorkspace.OpenConfiguration())
    }
}
