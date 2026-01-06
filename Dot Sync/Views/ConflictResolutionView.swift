//
//  ConflictResolutionView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import SwiftUI

/// Full conflict resolution UI with side-by-side diff
struct ConflictResolutionView: View {
    let conflict: ConflictInfo

    @Environment(\.dismiss) private var dismiss
    @State private var selectedResolution: ConflictResolution?
    @State private var isResolving = false
    @State private var showingVisualEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: conflict.hasAncestor ? "arrow.triangle.branch" : "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(conflict.hasAncestor ? .blue : .orange)

                    VStack(alignment: .leading) {
                        Text(conflict.hasAncestor ? "Smart Merge Available" : "Conflict Detected")
                            .font(.title)
                        Text(conflict.file.filename)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                if let attempt = conflict.mergeAttempt {
                    HStack {
                        if attempt.canAutoApply {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.purple)
                            Text("Auto-merge available: \(attempt.reason)")
                                .font(.subheadline)
                                .foregroundColor(.purple)
                        } else {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                            Text(attempt.reason)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    Text("Both local and remote versions have been modified. Choose which version to keep.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                            Text("Modified: \(conflict.localDate.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(conflict.localContent.count) bytes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))

                    Divider()

                    DiffView(content: conflict.localContent, otherContent: conflict.remoteContent, title: "")
                }

                // Right: Remote version
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Remote (Cloud)")
                                .font(.headline)
                            Text("Modified: \(conflict.remoteDate.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(conflict.remoteContent.count) bytes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))

                    Divider()

                    DiffView(content: conflict.remoteContent, otherContent: conflict.localContent, title: "")
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

                // Auto-merge button (if available)
                if let attempt = conflict.mergeAttempt, attempt.canAutoApply {
                    Button(action: applyAutoMerge) {
                        Label("Apply Auto-Merge", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .help(attempt.reason)
                }

                // Visual merge editor button (if conflicts exist but some can be auto-merged)
                if conflict.hasAncestor {
                    Button(action: { showingVisualEditor = true }) {
                        Label("Visual Editor", systemImage: "arrow.triangle.merge")
                    }
                    .buttonStyle(.bordered)
                    .help("Open advanced merge editor with three-way view")
                }

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
                    Label("Edit in TextEdit", systemImage: "pencil.and.list.clipboard")
                }
                .buttonStyle(.bordered)
                .help("Open both files in TextEdit for manual merging")
            }
            .padding()
            .disabled(isResolving)

            if isResolving {
                ProgressView("Resolving conflict...")
                    .padding(.bottom)
            }
        }
        .frame(width: 1000, height: 700)
        .sheet(isPresented: $showingVisualEditor) {
            VisualMergeEditor(conflict: conflict)
        }
    }

    private func applyAutoMerge() {
        guard let mergedContent = conflict.mergeAttempt?.mergedContent else { return }

        isResolving = true

        Task {
            do {
                // Write merged content to file
                try mergedContent.data(using: .utf8)?.write(to: URL(fileURLWithPath: conflict.file.path), options: .atomic)

                // Upload merged version
                try await SyncEngine.shared.sync(files: [conflict.file], direction: .upload)

                await MainActor.run {
                    isResolving = false
                    dismiss()
                }

                NotificationService.shared.notify(
                    title: "Auto-Merge Applied",
                    body: "\(conflict.file.filename) merged successfully"
                )
            } catch {
                await MainActor.run {
                    isResolving = false
                }
                print("[ConflictResolution] Error: \(error)")
            }
        }
    }

    private func selectResolution(_ resolution: ConflictResolution) {
        selectedResolution = resolution
        isResolving = true

        Task {
            do {
                try await SyncEngine.shared.resolveConflict(for: conflict.file, resolution: resolution)

                await MainActor.run {
                    isResolving = false
                    dismiss()
                }

                // Show success notification
                NotificationService.shared.notify(
                    title: "Conflict Resolved",
                    body: "\(conflict.file.filename) - using \(resolution.description)"
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

        let localFile = tempDir.appendingPathComponent("\(conflict.file.filename).local.\(timestamp)")
        let remoteFile = tempDir.appendingPathComponent("\(conflict.file.filename).remote.\(timestamp)")
        let mergedFile = tempDir.appendingPathComponent("\(conflict.file.filename).merged.\(timestamp)")

        // Write all files including ancestor if available
        try? conflict.localContent.data(using: .utf8)?.write(to: localFile)
        try? conflict.remoteContent.data(using: .utf8)?.write(to: remoteFile)

        // Create merged template with markers
        var mergedTemplate = """
        <<<<<<< LOCAL (This Mac) - Modified: \(DateFormatter.localizedString(from: conflict.localDate, dateStyle: .short, timeStyle: .short))
        \(conflict.localContent)
        =======
        >>>>>>> REMOTE (Cloud) - Modified: \(DateFormatter.localizedString(from: conflict.remoteDate, dateStyle: .short, timeStyle: .short))
        \(conflict.remoteContent)
        <<<<<<< END

        """

        if conflict.hasAncestor {
            mergedTemplate += """

            ANCESTOR VERSION (Last Synced):
            \(conflict.ancestorContent ?? "")

            """
        }

        mergedTemplate += """
        INSTRUCTIONS:
        1. Remove the conflict markers (<<<<<<, =======, >>>>>>>)
        2. Merge the changes as needed
        3. Save this file
        4. Copy the merged content to: \(conflict.file.path)
        5. Run sync again to upload the merged version
        """

        try? mergedTemplate.data(using: .utf8)?.write(to: mergedFile)

        // Open all files
        NSWorkspace.shared.open([localFile, remoteFile, mergedFile],
                               withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                               configuration: NSWorkspace.OpenConfiguration())

        // Trigger merge resolution (keeps conflict in list but closes dialog)
        Task {
            try? await SyncEngine.shared.resolveConflict(for: conflict.file, resolution: .merge)
        }

        // Show instructions to user
        NotificationService.shared.notify(
            title: "Manual Merge Started",
            body: """
            Files opened in TextEdit:
            • \(conflict.file.filename).local - Your version
            • \(conflict.file.filename).remote - Cloud version
            • \(conflict.file.filename).merged - Template for merging

            Merge the files, save to your home directory, and sync again.
            """
        )
    }
}
