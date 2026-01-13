//
//  ContentView.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var discoveryService = FileDiscoveryService.shared
    @StateObject private var syncEngine = SyncEngine.shared
    @StateObject private var profileManager = ProfileManager.shared

    @State private var selectedCategory: ConfigCategory? = nil
    @State private var selectedFiles: Set<UUID> = []
    @State private var showingPreferences = false
    @State private var showingPreview = false
    @State private var showingConflicts = false
    @State private var dryRunEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
            // Left Sidebar - Categories
            List(selection: $selectedCategory) {
                Section("Machine Configuration") {
                    Picker("Machine Role", selection: $syncEngine.machineRole) {
                        ForEach(MachineRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: syncEngine.machineRole) { newRole in
                        syncEngine.setMachineRole(newRole)
                    }
                    .help(syncEngine.machineRole.description)

                    Text(roleDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }

                Section("Profiles") {
                    Picker("Active Profile", selection: $profileManager.activeProfile) {
                        ForEach(profileManager.profiles) { profile in
                            Text(profile.name).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: profileManager.activeProfile) { _ in
                        profileManager.saveActiveProfile()
                    }
                }

                if !syncEngine.conflictedFiles.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("\(syncEngine.conflictedFiles.count) Conflicts")
                                .font(.headline)
                                .foregroundColor(.red)
                            Spacer()
                            Button("Resolve") {
                                Task {
                                    try? await syncEngine.checkForConflicts()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("ATTENTION REQUIRED")
                            .foregroundColor(.red)
                    }
                }

                Section("Categories") {
                    ForEach(ConfigCategory.allCases, id: \.self) { category in
                        CategoryRow(category: category, fileCount: fileCount(for: category))
                            .tag(category)
                    }
                }

                Section("Priority") {
                    ForEach(SyncPriority.allCases, id: \.self) { priority in
                        PriorityRow(priority: priority, fileCount: priorityCount(for: priority))
                    }
                }
            }
            .navigationTitle("Dot Sync")
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { Task { await discoveryService.scanHomeDirectory() } }) {
                        Label("Scan", systemImage: "arrow.clockwise")
                    }
                    .disabled(discoveryService.isScanning)
                }

                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        Task {
                            try? await syncEngine.checkForConflicts()
                        }
                    }) {
                        Label("Check Conflicts", systemImage: "exclamationmark.triangle")
                    }
                    .disabled(syncEngine.isSyncing)
                    .overlay(alignment: .topTrailing) {
                        if !syncEngine.conflictedFiles.isEmpty {
                            Text("\(syncEngine.conflictedFiles.count)")
                                .font(.caption2)
                                .padding(4)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                                .offset(x: 8, y: -8)
                        }
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button(action: { showingPreferences = true }) {
                        Label("Preferences", systemImage: "gear")
                    }
                }
            }
        } detail: {
            // Right Panel - File List and Details
            if discoveryService.isScanning {
                ProgressView("Scanning configuration files...")
            } else if let category = selectedCategory {
                FileListView(
                    files: filteredFiles,
                    selectedFiles: $selectedFiles,
                    dryRunEnabled: $dryRunEnabled,
                    onSync: performSync,
                    onPreview: showPreview,
                    onPullOnly: performPullOnly
                )
            } else {
                EmptyStateView()
            }
            }
            .onAppear {
                Task {
                    await discoveryService.scanHomeDirectory()
                    // Check for conflicts on startup
                    try? await syncEngine.checkForConflicts()
                }
            }
            .sheet(isPresented: $showingPreferences) {
                PreferencesView()
            }
            .sheet(isPresented: $showingPreview) {
                PreviewOperationsView(operations: syncEngine.previewOperations)
            }
            .sheet(isPresented: $syncEngine.showingConflictDialog) {
                if let conflict = syncEngine.currentConflict {
                    ConflictResolutionView(conflict: conflict)
                }
            }

            // Status bar at bottom
            StatusBarView(
                syncEngine: syncEngine,
                discoveryService: discoveryService
            )
        }
        .overlay(alignment: .top) {
            // Toast notifications at top
            ToastContainerView(
                toasts: syncEngine.toastMessages,
                onDismiss: { toast in
                    syncEngine.dismissToast(toast)
                }
            )
            .padding(.top, 8)
        }
        .overlay {
            // Sync progress overlay (full screen)
            SyncProgressFullScreenOverlay(
                progress: syncEngine.syncProgress,
                onCancel: nil // TODO: Implement cancel functionality
            )
        }
    }

    private var filteredFiles: [ConfigFile] {
        let allFiles = if let category = selectedCategory {
            discoveryService.files(for: category)
        } else {
            discoveryService.discoveredFiles
        }

        // Filter by active profile
        return profileManager.filteredFiles(from: allFiles)
    }

    private var roleDescription: String {
        switch syncEngine.machineRole {
        case .master:
            return "✓ Can upload and download configurations"
        case .client:
            return "⬇ Download only (read-only mode)"
        }
    }

    private func fileCount(for category: ConfigCategory) -> Int {
        let files = discoveryService.files(for: category)
        return profileManager.filteredFiles(from: files).count
    }

    private func priorityCount(for priority: SyncPriority) -> Int {
        let files = discoveryService.files(for: priority)
        return profileManager.filteredFiles(from: files).count
    }

    private func performSync() {
        Task {
            let filesToSync = selectedFiles.compactMap { id in
                discoveryService.discoveredFiles.first { $0.id == id }
            }

            do {
                try await syncEngine.sync(files: filesToSync, direction: .upload, dryRun: dryRunEnabled)

                if dryRunEnabled {
                    showingPreview = true
                }
            } catch {
                print("[ContentView] Sync error: \(error)")
            }
        }
    }

    private func showPreview() {
        Task {
            let filesToSync = selectedFiles.compactMap { id in
                discoveryService.discoveredFiles.first { $0.id == id }
            }

            do {
                _ = try await syncEngine.previewSync(files: filesToSync)
                showingPreview = true
            } catch {
                print("[ContentView] Preview error: \(error)")
            }
        }
    }

    private func performPullOnly() {
        Task {
            let filesToPull = selectedFiles.compactMap { id in
                discoveryService.discoveredFiles.first { $0.id == id }
            }

            do {
                try await syncEngine.pullOnly(files: filesToPull)
                print("[ContentView] ✅ Pull-only sync completed for \(filesToPull.count) files")
            } catch {
                print("[ContentView] ❌ Pull-only error: \(error)")
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("Select a category to view config files")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Dot Sync has scanned your home directory for configuration files")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Category Row

struct CategoryRow: View {
    let category: ConfigCategory
    let fileCount: Int

    var body: some View {
        HStack {
            Image(systemName: category.icon)
                .foregroundColor(.accentColor)
            Text(category.rawValue)
            Spacer()
            if fileCount > 0 {
                Text("\(fileCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Priority Row

struct PriorityRow: View {
    let priority: SyncPriority
    let fileCount: Int

    var body: some View {
        HStack {
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)
            Text(priority.rawValue)
            Spacer()
            if fileCount > 0 {
                Text("\(fileCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var priorityColor: Color {
        switch priority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}

// MARK: - File List View

struct FileListView: View {
    let files: [ConfigFile]
    @Binding var selectedFiles: Set<UUID>
    @Binding var dryRunEnabled: Bool
    let onSync: () -> Void
    let onPreview: () -> Void
    let onPullOnly: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(files.count) config files")
                    .font(.headline)
                Spacer()
                Button("Select All") {
                    selectedFiles = Set(files.filter(\.isSafeToSync).map(\.id))
                }
                Button("Select None") {
                    selectedFiles.removeAll()
                }
            }
            .padding()

            Divider()

            // File list
            List(files, selection: $selectedFiles) { file in
                FileRow(file: file)
                    .tag(file.id)
            }

            Divider()

            // Sync toolbar
            HStack {
                Toggle("Dry Run (Preview Only)", isOn: $dryRunEnabled)
                    .help("Preview sync operations without executing them")

                Spacer()

                Button(action: {
                    Task {
                        let filesToAnalyze = selectedFiles.compactMap { id in
                            files.first { $0.id == id }
                        }
                        try? await SyncEngine.shared.analyzeSyncStatus(for: filesToAnalyze)
                    }
                }) {
                    Label("Scan Status", systemImage: "magnifyingglass")
                }
                .disabled(selectedFiles.isEmpty)
                .help("Check sync status for selected files")

                Button(action: onPullOnly) {
                    Label("Pull Only", systemImage: "arrow.down.circle.fill")
                }
                .disabled(selectedFiles.isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .help("Download selected files from cloud (overwrite local)")

                if dryRunEnabled {
                    Button(action: onPreview) {
                        Label("Preview Sync", systemImage: "eye")
                    }
                    .disabled(selectedFiles.isEmpty)
                } else {
                    Button(action: onSync) {
                        Label("Sync Selected", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(selectedFiles.isEmpty)
                }

                Button(action: { /* Open preferences */ }) {
                    Label("Settings", systemImage: "gear")
                }
            }
            .padding()
        }
    }
}

// MARK: - File Row

struct FileRow: View {
    let file: ConfigFile
    @StateObject private var syncEngine = SyncEngine.shared

    var body: some View {
        HStack {
            Image(systemName: file.category.icon)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(file.filename)
                        .font(.system(.body, design: .monospaced))
                    if !file.isSafeToSync {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.red)
                            .help("Contains credentials - not safe to sync")
                    }
                    if isConflicted {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .help("Conflict detected - needs resolution")
                    }
                }

                Text(file.relativePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(file.sizeFormatted)
                    .font(.caption)
                Text(file.lastModifiedFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let syncStatus = syncStatus {
                    syncStatusBadge(status: syncStatus.state)
                }
            }

            priorityBadge
        }
        .padding(.vertical, 4)
    }

    private var isConflicted: Bool {
        syncEngine.conflictedFiles.contains { $0.id == file.id }
    }

    private var syncStatus: SyncStatus? {
        syncEngine.syncStatuses.first { $0.file.id == file.id }
    }

    private func syncStatusBadge(status: SyncState) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
            Text(status.rawValue)
                .font(.caption2)
        }
        .foregroundColor(statusColor(status))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor(status).opacity(0.1))
        .cornerRadius(4)
    }

    private func statusColor(_ status: SyncState) -> Color {
        switch status {
        case .synced: return .green
        case .localNewer: return .blue
        case .remoteNewer: return .orange
        case .conflict: return .red
        case .notOnRemote: return .purple
        case .notOnLocal: return .cyan
        case .error: return .red
        }
    }

    private var priorityBadge: some View {
        Circle()
            .fill(priorityColor)
            .frame(width: 10, height: 10)
            .help(file.syncPriority.rawValue)
    }

    private var priorityColor: Color {
        switch file.syncPriority {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }
}

// MARK: - Preview Operations View

struct PreviewOperationsView: View {
    let operations: [SyncOperation]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "eye")
                    .font(.largeTitle)
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text("Sync Preview (Dry Run)")
                        .font(.title)
                    Text("These operations would be performed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            // Operations list
            if operations.isEmpty {
                Text("No sync operations needed - all files are up to date")
                    .foregroundColor(.secondary)
            } else {
                List(operations) { operation in
                    HStack {
                        Image(systemName: operation.direction.icon)
                            .foregroundColor(directionColor(operation.direction))

                        VStack(alignment: .leading) {
                            Text(operation.file.filename)
                                .font(.system(.body, design: .monospaced))
                            Text(operation.direction.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(operation.file.sizeFormatted)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Summary
            HStack {
                Text("Total: \(operations.count) operations")
                    .font(.headline)

                Spacer()

                Text("\(uploadCount) uploads, \(downloadCount) downloads")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Execute Sync") {
                    // Would trigger actual sync
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(operations.isEmpty)
            }
        }
        .padding()
        .frame(width: 700, height: 500)
    }

    private var uploadCount: Int {
        operations.filter { $0.direction == .upload }.count
    }

    private var downloadCount: Int {
        operations.filter { $0.direction == .download }.count
    }

    private func directionColor(_ direction: SyncDirection) -> Color {
        switch direction {
        case .upload: return .blue
        case .download: return .orange
        case .skip: return .gray
        }
    }
}
