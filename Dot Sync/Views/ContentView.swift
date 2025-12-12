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
        NavigationSplitView {
            // Left Sidebar - Categories
            List(selection: $selectedCategory) {
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
                    onPreview: showPreview
                )
            } else {
                EmptyStateView()
            }
        }
        .onAppear {
            Task {
                await discoveryService.scanHomeDirectory()
            }
        }
        .sheet(isPresented: $showingPreferences) {
            PreferencesView()
        }
        .sheet(isPresented: $showingPreview) {
            PreviewOperationsView(operations: syncEngine.previewOperations)
        }
        // Conflict resolution triggered during sync when conflicts detected
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
            }

            priorityBadge
        }
        .padding(.vertical, 4)
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
