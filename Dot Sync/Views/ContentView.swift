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

    @State private var selectedCategory: ConfigCategory? = nil
    @State private var selectedFiles: Set<UUID> = []
    @State private var showingSetup = false
    @State private var showingConflicts = false

    var body: some View {
        NavigationSplitView {
            // Left Sidebar - Categories
            List(selection: $selectedCategory) {
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
            }
        } detail: {
            // Right Panel - File List and Details
            if discoveryService.isScanning {
                ProgressView("Scanning configuration files...")
            } else if let category = selectedCategory {
                FileListView(files: filteredFiles, selectedFiles: $selectedFiles)
            } else {
                Text("Select a category to view config files")
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            Task {
                await discoveryService.scanHomeDirectory()
            }
        }
        .sheet(isPresented: $showingSetup) {
            SetupView()
        }
        .sheet(isPresented: $showingConflicts) {
            ConflictResolutionView()
        }
    }

    private var filteredFiles: [ConfigFile] {
        if let category = selectedCategory {
            return discoveryService.files(for: category)
        }
        return discoveryService.discoveredFiles
    }

    private func fileCount(for category: ConfigCategory) -> Int {
        discoveryService.files(for: category).count
    }

    private func priorityCount(for priority: SyncPriority) -> Int {
        discoveryService.files(for: priority).count
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
            List(files, selection: $selectedFiles) {
 file in
                FileRow(file: file)
                    .tag(file.id)
            }

            Divider()

            // Sync toolbar
            HStack {
                Button(action: { /* Sync */ }) {
                    Label("Sync Selected", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(selectedFiles.isEmpty)

                Spacer()

                Button(action: { /* Setup */ }) {
                    Label("Cloud Setup", systemImage: "cloud.fill")
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

// MARK: - Setup View

struct SetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Cloud Provider Setup")
                .font(.title)
            Text("Configure your cloud storage provider")
                .foregroundColor(.secondary)

            Spacer()

            Text("Setup coming soon...")

            Spacer()

            Button("Close") {
                dismiss()
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

// MARK: - Conflict Resolution View

struct ConflictResolutionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Resolve Conflicts")
                .font(.title)

            Spacer()

            Text("Conflict resolution coming soon...")

            Spacer()

            Button("Close") {
                dismiss()
            }
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}
