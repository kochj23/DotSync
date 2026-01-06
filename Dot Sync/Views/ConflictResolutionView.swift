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
                Button(action: { selectResolution(.skip) }) {
                    Label("Skip", systemImage: "clock.arrow.circlepath")
                }
                .help("Skip this conflict and resolve it later")

                Spacer()

                Button(action: { selectResolution(.useLocal) }) {
                    Label("Keep Local", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .help("Upload your local version to cloud (overwrites remote)")

                Button(action: { selectResolution(.useRemote) }) {
                    Label("Use Remote", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help("Download cloud version to this machine (overwrites local)")

                Button(action: { openInEditorAndMarkForMerge() }) {
                    Label("Merge Manually", systemImage: "pencil.and.list.clipboard")
                }
                .buttonStyle(.bordered)
                .help("Open both files in editor for manual merging")
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

    private func openInEditorAndMarkForMerge() {
        // Save both versions to temp files with clear naming
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DotSync-Conflicts")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")

        let localFile = tempDir.appendingPathComponent("\(file.filename).local.\(timestamp)")
        let remoteFile = tempDir.appendingPathComponent("\(file.filename).remote.\(timestamp)")
        let mergedFile = tempDir.appendingPathComponent("\(file.filename).merged.\(timestamp)")

        // Write all three files
        try? localContent.data(using: .utf8)?.write(to: localFile)
        try? remoteContent.data(using: .utf8)?.write(to: remoteFile)

        // Create merged template with markers
        let mergedTemplate = """
        <<<<<<< LOCAL (This Mac) - Modified: \(DateFormatter.localizedString(from: localDate, dateStyle: .short, timeStyle: .short))
        \(localContent)
        =======
        >>>>>>> REMOTE (Cloud) - Modified: \(DateFormatter.localizedString(from: remoteDate, dateStyle: .short, timeStyle: .short))
        \(remoteContent)
        <<<<<<< END

        INSTRUCTIONS:
        1. Remove the conflict markers (<<<<<<, =======, >>>>>>>)
        2. Merge the changes as needed
        3. Save this file
        4. Copy the merged content to: \(file.path)
        5. Run sync again to upload the merged version
        """
        try? mergedTemplate.data(using: .utf8)?.write(to: mergedFile)

        // Open all three files
        NSWorkspace.shared.open([localFile, remoteFile, mergedFile],
                               withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                               configuration: NSWorkspace.OpenConfiguration())

        // Trigger merge resolution (keeps conflict in list but closes dialog)
        Task {
            try? await SyncEngine.shared.resolveConflict(for: file, resolution: .merge)
        }

        // Show instructions to user
        NotificationService.shared.notify(
            title: "Manual Merge Started",
            body: """
            Files opened in TextEdit:
            • \(file.filename).local - Your version
            • \(file.filename).remote - Cloud version
            • \(file.filename).merged - Template for merging

            Merge the files, save to your home directory, and sync again.
            """
        )
    }
}
