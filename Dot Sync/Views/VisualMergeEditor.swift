//
//  VisualMergeEditor.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/6/26.
//

import SwiftUI

/// Advanced visual merge editor with line-by-line resolution
struct VisualMergeEditor: View {
    let conflict: ConflictInfo

    @Environment(\.dismiss) private var dismiss
    @State private var mergeLines: [MergeLine] = []
    @State private var isApplying = false
    @State private var selectedLineId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.merge")
                    .font(.largeTitle)
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text("Visual Merge Editor")
                        .font(.title)
                    Text(conflict.file.filename)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let attempt = conflict.mergeAttempt {
                    VStack(alignment: .trailing) {
                        Text(attempt.reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if !attempt.conflicts.isEmpty {
                            Text("\(attempt.conflicts.count) conflicts")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding()

            Divider()

            // Three-column view: Ancestor | Local | Remote
            if conflict.hasAncestor {
                HStack(spacing: 0) {
                    // Ancestor (common base)
                    VStack(spacing: 0) {
                        Text("Ancestor (Last Synced)")
                            .font(.headline)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.gray.opacity(0.1))

                        Divider()

                        ScrollView {
                            Text(conflict.ancestorContent ?? "")
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Divider()

                    // Local version
                    VStack(spacing: 0) {
                        Text("Local (This Mac)")
                            .font(.headline)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))

                        Divider()

                        ScrollView {
                            Text(conflict.localContent)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Divider()

                    // Remote version
                    VStack(spacing: 0) {
                        Text("Remote (Cloud)")
                            .font(.headline)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))

                        Divider()

                        ScrollView {
                            Text(conflict.remoteContent)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                // Two-column view if no ancestor
                HSplitView {
                    VStack(spacing: 0) {
                        Text("Local (This Mac)")
                            .font(.headline)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))

                        Divider()

                        DiffView(content: conflict.localContent, otherContent: conflict.remoteContent, title: "")
                    }

                    VStack(spacing: 0) {
                        Text("Remote (Cloud)")
                            .font(.headline)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))

                        Divider()

                        DiffView(content: conflict.remoteContent, otherContent: conflict.localContent, title: "")
                    }
                }
            }

            Divider()

            // Line-by-line merge view (if conflicts exist)
            if let attempt = conflict.mergeAttempt, !attempt.conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conflicting Lines (resolve individually)")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(attempt.conflicts) { conflict in
                                ConflictLineView(conflict: conflict)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.vertical, 8)

                Divider()
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: { selectResolution(.skip) }) {
                    Label("Skip", systemImage: "clock.arrow.circlepath")
                }

                Spacer()

                // Show auto-merge button if possible
                if let attempt = conflict.mergeAttempt, attempt.canAutoApply {
                    Button(action: applyAutoMerge) {
                        Label("Apply Auto-Merge", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .help("Automatically merged \(attempt.conflicts.count) conflicts")
                }

                Button(action: { selectResolution(.useLocal) }) {
                    Label("Keep Local", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(action: { selectResolution(.useRemote) }) {
                    Label("Use Remote", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button(action: openInEditor) {
                    Label("Edit Manually", systemImage: "pencil.and.list.clipboard")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .disabled(isApplying)

            if isApplying {
                ProgressView("Applying merge...")
                    .padding(.bottom)
            }
        }
        .frame(width: 1200, height: 800)
    }

    // MARK: - Actions

    private func applyAutoMerge() {
        guard let mergedContent = conflict.mergeAttempt?.mergedContent else { return }

        isApplying = true

        Task {
            do {
                // Write merged content to file
                try mergedContent.data(using: .utf8)?.write(to: URL(fileURLWithPath: conflict.file.path), options: .atomic)

                // Store as ancestor
                try SyncEngine.shared.storeAncestor(for: conflict.file, content: mergedContent)

                // Upload merged version
                try await SyncEngine.shared.sync(files: [conflict.file], direction: .upload)

                await MainActor.run {
                    isApplying = false
                    dismiss()
                }

                NotificationService.shared.notify(
                    title: "Auto-Merge Applied",
                    body: "\(conflict.file.filename) - merged and synced successfully"
                )
            } catch {
                await MainActor.run {
                    isApplying = false
                }
                print("[VisualMergeEditor] Error: \(error)")
            }
        }
    }

    private func selectResolution(_ resolution: ConflictResolution) {
        isApplying = true

        Task {
            do {
                try await SyncEngine.shared.resolveConflict(for: conflict.file, resolution: resolution)

                await MainActor.run {
                    isApplying = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                }
                print("[VisualMergeEditor] Error: \(error)")
            }
        }
    }

    private func openInEditor() {
        selectResolution(.merge)
    }
}

/// Line-level conflict view
struct ConflictLineView: View {
    let conflict: MergeConflict
    @State private var selectedVersion: ConflictVersion = .local

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Line \(conflict.lineNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Picker("", selection: $selectedVersion) {
                    Text("Local").tag(ConflictVersion.local)
                    Text("Remote").tag(ConflictVersion.remote)
                    Text("Both").tag(ConflictVersion.both)
                    Text("Neither").tag(ConflictVersion.neither)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }

            HStack(spacing: 8) {
                // Local version
                VStack(alignment: .leading) {
                    Text("Local:")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text(conflict.localLine.isEmpty ? "(deleted)" : conflict.localLine)
                        .font(.system(.caption, design: .monospaced))
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedVersion == .local || selectedVersion == .both ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                }

                // Remote version
                VStack(alignment: .leading) {
                    Text("Remote:")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(conflict.remoteLine.isEmpty ? "(deleted)" : conflict.remoteLine)
                        .font(.system(.caption, design: .monospaced))
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedVersion == .remote || selectedVersion == .both ? Color.orange.opacity(0.1) : Color.clear)
                        .cornerRadius(4)
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

enum ConflictVersion {
    case local
    case remote
    case both
    case neither
}

/// Simple merge line representation
struct MergeLine: Identifiable {
    let id = UUID()
    let lineNumber: Int
    let content: String
    let source: LineSource

    enum LineSource {
        case ancestor
        case local
        case remote
        case merged
        case conflict
    }
}
