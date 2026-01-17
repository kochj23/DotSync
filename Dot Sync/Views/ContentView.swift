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
        ZStack {
            // Glassmorphic background
            GlassmorphicBackground()

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
                        .foregroundColor(ModernColors.textSecondary)
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

                Section(categoryHeader) {
                    ForEach(categoriesForCurrentRole, id: \.self) { category in
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
                    Button(action: {
                        Task {
                            if syncEngine.machineRole == .master {
                                await discoveryService.scanHomeDirectory()
                            } else {
                                try? await syncEngine.fetchRemoteFiles()
                            }
                        }
                    }) {
                        Label(scanButtonLabel, systemImage: scanButtonIcon)
                    }
                    .disabled(discoveryService.isScanning || syncEngine.isLoadingRemoteFiles)
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
                ProgressView("Scanning local configuration files...")
            } else if syncEngine.isLoadingRemoteFiles {
                ProgressView("Loading files from cloud storage...")
            } else if let category = selectedCategory {
                FileListView(
                    files: filteredFiles,
                    selectedFiles: $selectedFiles,
                    dryRunEnabled: $dryRunEnabled,
                    machineRole: syncEngine.machineRole,
                    onPush: performPush,
                    onPull: performPull,
                    onPreview: showPreview
                )
            } else {
                EmptyStateView(
                    machineRole: syncEngine.machineRole,
                    isCloudConfigured: syncEngine.currentProvider != nil,
                    onConfigureCloud: { showingPreferences = true },
                    onFetchCloud: {
                        Task {
                            try? await syncEngine.fetchRemoteFiles()
                        }
                    }
                )
            }
            }
            .onAppear {
                Task {
                    // Load appropriate files based on machine role
                    if syncEngine.machineRole == .master {
                        await discoveryService.scanHomeDirectory()
                    } else {
                        try? await syncEngine.fetchRemoteFiles()
                    }

                    // Check for conflicts on startup
                    try? await syncEngine.checkForConflicts()
                }
            }
            .onChange(of: syncEngine.machineRole) { newRole in
                // Reload files when role changes
                Task {
                    if newRole == .master {
                        await discoveryService.scanHomeDirectory()
                    } else {
                        try? await syncEngine.fetchRemoteFiles()
                    }
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
            .sheet(isPresented: $syncEngine.showingFailureSummary) {
                if let summary = syncEngine.currentFailureSummary {
                    FailureSummaryView(summary: summary)
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
    }

    private var filteredFiles: [ConfigFile] {
        // Master mode: show local files
        // Client mode: show remote files
        let sourceFiles = (syncEngine.machineRole == .master) ? discoveryService.discoveredFiles : syncEngine.remoteFiles

        let allFiles = if let category = selectedCategory {
            // If "everything" category, show all files
            if category == .everything {
                sourceFiles
            } else {
                sourceFiles.filter { $0.category == category }
            }
        } else {
            sourceFiles
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

    private var categoryHeader: String {
        switch syncEngine.machineRole {
        case .master:
            return "Local Files by Category"
        case .client:
            return "Cloud Files by Category"
        }
    }

    private var categoriesForCurrentRole: [ConfigCategory] {
        // Always show "Everything" first, then actual categories (not "everything" again)
        var categories: [ConfigCategory] = [.everything]
        categories.append(contentsOf: ConfigCategory.allCases.filter { !$0.isFilterCategory })
        return categories
    }

    private var scanButtonLabel: String {
        switch syncEngine.machineRole {
        case .master:
            return "Scan Local"
        case .client:
            return "Fetch Cloud"
        }
    }

    private var scanButtonIcon: String {
        switch syncEngine.machineRole {
        case .master:
            return "arrow.clockwise"
        case .client:
            return "cloud.fill"
        }
    }

    private func fileCount(for category: ConfigCategory) -> Int {
        // Use local or remote files based on machine role
        let sourceFiles = (syncEngine.machineRole == .master) ? discoveryService.discoveredFiles : syncEngine.remoteFiles

        let files = if category == .everything {
            sourceFiles
        } else {
            sourceFiles.filter { $0.category == category }
        }

        return profileManager.filteredFiles(from: files).count
    }

    private func priorityCount(for priority: SyncPriority) -> Int {
        // Use local or remote files based on machine role
        let sourceFiles = (syncEngine.machineRole == .master) ? discoveryService.discoveredFiles : syncEngine.remoteFiles
        let files = sourceFiles.filter { $0.syncPriority == priority }
        return profileManager.filteredFiles(from: files).count
    }

    private func performPush() {
        Task {
            let sourceFiles = (syncEngine.machineRole == .master) ? discoveryService.discoveredFiles : syncEngine.remoteFiles

            let filesToPush = selectedFiles.compactMap { id in
                sourceFiles.first { $0.id == id }
            }

            do {
                try await syncEngine.sync(files: filesToPush, direction: .upload, dryRun: dryRunEnabled)

                if dryRunEnabled {
                    showingPreview = true
                }
            } catch {
                print("[ContentView] Push error: \(error)")
            }
        }
    }

    private func performPull() {
        Task {
            let sourceFiles = (syncEngine.machineRole == .master) ? discoveryService.discoveredFiles : syncEngine.remoteFiles

            let filesToPull = selectedFiles.compactMap { id in
                sourceFiles.first { $0.id == id }
            }

            do {
                try await syncEngine.pullOnly(files: filesToPull)
                print("[ContentView] ✅ Pull completed for \(filesToPull.count) files")
            } catch {
                print("[ContentView] ❌ Pull error: \(error)")
            }
        }
    }

    private func showPreview() {
        Task {
            let sourceFiles = (syncEngine.machineRole == .master) ? discoveryService.discoveredFiles : syncEngine.remoteFiles

            let filesToSync = selectedFiles.compactMap { id in
                sourceFiles.first { $0.id == id }
            }

            do {
                _ = try await syncEngine.previewSync(files: filesToSync)
                showingPreview = true
            } catch {
                print("[ContentView] Preview error: \(error)")
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let machineRole: MachineRole
    let isCloudConfigured: Bool
    let onConfigureCloud: () -> Void
    let onFetchCloud: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: iconName)
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Text(headerText)
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text(descriptionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Show action buttons based on state
            if machineRole == .client && !isCloudConfigured {
                VStack(spacing: 12) {
                    Button(action: onConfigureCloud) {
                        Label("Configure Cloud Storage", systemImage: "cloud.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Set up AWS, Azure, GCP, or iCloud to sync your configurations")

                    Text("You need to configure cloud storage before you can view or download files")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.top, 8)
            } else if machineRole == .client && isCloudConfigured {
                Button(action: onFetchCloud) {
                    Label("Fetch Cloud Files", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .help("Load configuration files from cloud storage")
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconName: String {
        if machineRole == .client && !isCloudConfigured {
            return "exclamationmark.cloud"
        }

        switch machineRole {
        case .master:
            return "folder.badge.gearshape"
        case .client:
            return "cloud.fill"
        }
    }

    private var headerText: String {
        if machineRole == .client && !isCloudConfigured {
            return "Cloud Storage Not Configured"
        }

        switch machineRole {
        case .master:
            return "Select a category to view local files"
        case .client:
            return "Ready to fetch cloud files"
        }
    }

    private var descriptionText: String {
        if machineRole == .client && !isCloudConfigured {
            return "To view and download configuration files from the cloud, you first need to set up your cloud storage provider"
        }

        switch machineRole {
        case .master:
            return "Master mode: Manage local configuration files and push changes to cloud"
        case .client:
            return "Client mode: Click 'Fetch Cloud Files' above or select 'Everything' on the left, then click the fetch button in the toolbar"
        }
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
    let machineRole: MachineRole
    let onPush: () -> Void
    let onPull: () -> Void
    let onPreview: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(files.count) config files")
                    .font(.headline)
                Spacer()

                // Client mode: Add refresh cloud button
                if machineRole == .client {
                    Button(action: {
                        Task {
                            try? await SyncEngine.shared.fetchRemoteFiles()
                        }
                    }) {
                        Label("Refresh Cloud", systemImage: "arrow.clockwise.cloud.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Reload files from cloud storage")
                }

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

                // Role-based action button
                if dryRunEnabled {
                    Button(action: onPreview) {
                        Label("Preview", systemImage: "eye")
                    }
                    .disabled(selectedFiles.isEmpty)
                } else {
                    // Master mode: Only show Push button
                    if machineRole == .master {
                        Button(action: onPush) {
                            Label("Push to Cloud", systemImage: "arrow.up.circle.fill")
                        }
                        .disabled(selectedFiles.isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .help("Upload selected files to cloud storage")
                    }
                    // Client mode: Only show Pull button
                    else {
                        Button(action: onPull) {
                            Label("Pull from Cloud", systemImage: "arrow.down.circle.fill")
                        }
                        .disabled(selectedFiles.isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .help("Download selected files from cloud storage")
                    }
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
