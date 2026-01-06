//
//  SyncEngine.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Core sync engine for managing file synchronization
@MainActor
class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published var syncStatuses: [SyncStatus] = []
    @Published var currentProvider: CloudProviderConfig?
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var previewOperations: [SyncOperation] = []
    @Published var isDryRun = false
    @Published var conflictedFiles: [ConfigFile] = []
    @Published var showingConflictDialog = false
    @Published var currentConflict: ConflictInfo?

    private var cloudProvider: CloudStorageProtocol?

    // MARK: - Configuration

    /// Set cloud provider
    func configure(provider: CloudProviderConfig, credentials: CloudCredentials?) {
        currentProvider = provider

        switch provider.type {
        case .awsS3, .s3Compatible:
            cloudProvider = S3Provider(config: provider, credentials: credentials)
        case .azureBlob:
            cloudProvider = AzureBlobProvider(config: provider, credentials: credentials)
        case .googleCloud:
            cloudProvider = GCPProvider(config: provider, credentials: credentials)
        case .iCloud:
            cloudProvider = iCloudProvider(config: provider, credentials: nil)
        case .nas:
            cloudProvider = NASProvider(config: provider, credentials: credentials)
        case .oneDrive:
            cloudProvider = OneDriveProvider(config: provider, credentials: credentials)
        case .googleDrive:
            cloudProvider = GoogleDriveProvider(config: provider, credentials: credentials)
        }
    }

    // MARK: - Dry Run / Preview

    /// Preview what sync would do without executing (Dry Run Mode)
    func previewSync(files: [ConfigFile]) async throws -> [SyncOperation] {
        guard let provider = cloudProvider else {
            throw CloudStorageError.notConfigured
        }

        var operations: [SyncOperation] = []

        // Get remote file list
        let remoteFiles = try await provider.listFiles()

        for file in files {
            let remoteFile = remoteFiles.first { $0.path.contains(file.filename) }

            let direction: SyncDirection
            if let remote = remoteFile {
                // Compare timestamps
                if file.lastModified > remote.lastModified {
                    direction = .upload
                } else if file.lastModified < remote.lastModified {
                    direction = .download
                } else {
                    // Files match, skip
                    direction = .skip
                }
            } else {
                // Not on remote, upload
                direction = .upload
            }

            if direction != .skip {
                var operation = SyncOperation(file: file, direction: direction)
                operation.status = .pending
                operations.append(operation)
            }
        }

        self.previewOperations = operations
        return operations
    }

    // MARK: - Sync Operations

    /// Analyze files and determine sync status
    func analyzeSyncStatus(for files: [ConfigFile]) async throws {
        guard let provider = cloudProvider else {
            throw CloudStorageError.notConfigured
        }

        var statuses: [SyncStatus] = []

        // Get remote file list
        let remoteFiles = try await provider.listFiles()

        for file in files {
            let remoteFile = remoteFiles.first { $0.path.contains(file.filename) }

            let state: SyncState
            if let remote = remoteFile {
                // Compare timestamps
                if file.lastModified > remote.lastModified {
                    state = .localNewer
                } else if file.lastModified < remote.lastModified {
                    state = .remoteNewer
                } else {
                    // Check checksums if available
                    if let remoteChecksum = remote.checksum, remoteChecksum != file.checksum {
                        state = .conflict
                    } else {
                        state = .synced
                    }
                }
            } else {
                state = .notOnRemote
            }

            let status = SyncStatus(
                file: file,
                localVersion: file.lastModified,
                remoteVersion: remoteFile?.lastModified,
                state: state
            )

            statuses.append(status)
        }

        self.syncStatuses = statuses
    }

    /// Execute sync for selected files
    func sync(files: [ConfigFile], direction: SyncDirection, dryRun: Bool = false) async throws {
        guard let provider = cloudProvider else {
            throw CloudStorageError.notConfigured
        }

        // If dry run, just preview
        if dryRun {
            isDryRun = true
            _ = try await previewSync(files: files)
            isDryRun = false
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        var successCount = 0
        var errorCount = 0

        for file in files {
            do {
                switch direction {
                case .upload:
                    try await uploadFile(file, using: provider)
                    successCount += 1
                case .download:
                    try await downloadFile(file, using: provider)
                    successCount += 1
                case .skip:
                    continue
                }
            } catch {
                print("[SyncEngine] Error syncing \(file.filename): \(error)")
                errorCount += 1
                // Continue with other files
            }
        }

        lastSyncDate = Date()

        // Send notification
        if successCount > 0 {
            NotificationService.shared.notifySyncCompleted(fileCount: successCount)
        }
        if errorCount > 0 {
            NotificationService.shared.notifySyncFailed(error: "\(errorCount) files failed to sync")
        }

        // Re-analyze after sync
        try await analyzeSyncStatus(for: files)

        // Check for conflicts across all files
        try await checkForConflicts()
    }

    /// Upload individual file
    private func uploadFile(_ file: ConfigFile, using provider: CloudStorageProtocol) async throws {
        let url = URL(fileURLWithPath: file.path)
        let data = try Data(contentsOf: url)

        // Security check
        if await SecurityScanner.shared.containsCredentials(at: url) {
            print("[SyncEngine] ⚠️ Skipping \(file.filename) - contains credentials")
            throw CloudStorageError.uploadFailed(
                NSError(domain: "SyncEngine", code: 1001,
                       userInfo: [NSLocalizedDescriptionKey: "File contains credentials"])
            )
        }

        try await provider.upload(file: file, data: data)
        print("[SyncEngine] ✅ Uploaded \(file.filename)")
    }

    /// Download individual file
    private func downloadFile(_ file: ConfigFile, using provider: CloudStorageProtocol) async throws {
        let data = try await provider.download(file: file)

        // Backup existing file
        let url = URL(fileURLWithPath: file.path)
        if FileManager.default.fileExists(atPath: file.path) {
            let backupPath = file.path + ".backup"
            try? FileManager.default.copyItem(atPath: file.path, toPath: backupPath)
        }

        // Write downloaded data
        try data.write(to: url, options: .atomic)
        print("[SyncEngine] ✅ Downloaded \(file.filename)")
    }

    // MARK: - Conflict Resolution

    /// Resolve conflict for a file
    func resolveConflict(for file: ConfigFile, resolution: ConflictResolution) async throws {
        switch resolution {
        case .useLocal:
            try await sync(files: [file], direction: .upload)
            removeFromConflicts(file)
        case .useRemote:
            try await sync(files: [file], direction: .download)
            removeFromConflicts(file)
        case .skip:
            // Keep in conflicted list for later resolution
            NotificationService.shared.notify(
                title: "Conflict Skipped",
                body: "\(file.filename) - conflict will be shown again next sync"
            )
            return
        case .merge:
            // User will manually merge - mark as in-progress
            currentConflict = nil
            showingConflictDialog = false
            NotificationService.shared.notify(
                title: "Manual Merge Required",
                body: "\(file.filename) - merge the files and run sync again"
            )
            return
        }

        // Close dialog after resolution
        currentConflict = nil
        showingConflictDialog = false
    }

    /// Check for conflicts after sync/scan
    func checkForConflicts() async throws {
        guard let provider = cloudProvider else { return }

        // Get remote file list
        let remoteFiles = try await provider.listFiles()
        let discoveredFiles = FileDiscoveryService.shared.discoveredFiles

        var conflicts: [ConfigFile] = []
        var conflictInfos: [ConflictInfo] = []

        for file in discoveredFiles {
            guard let remoteFile = remoteFiles.first(where: { $0.path.contains(file.filename) }) else {
                continue
            }

            // Detect conflict: both modified since last sync
            let isConflict = file.lastModified > remoteFile.lastModified &&
                            remoteFile.lastModified > (lastSyncDate ?? .distantPast)

            // Or same timestamp but different checksums
            let sameTimeConflict = file.lastModified == remoteFile.lastModified &&
                                  remoteFile.checksum != nil &&
                                  remoteFile.checksum != file.checksum

            if isConflict || sameTimeConflict {
                conflicts.append(file)

                // Load file contents for diff
                if let localContent = try? String(contentsOfFile: file.path, encoding: .utf8),
                   let remoteData = try? await provider.download(file: file),
                   let remoteContent = String(data: remoteData, encoding: .utf8) {

                    let info = ConflictInfo(
                        file: file,
                        localContent: localContent,
                        remoteContent: remoteContent,
                        localDate: file.lastModified,
                        remoteDate: remoteFile.lastModified
                    )
                    conflictInfos.append(info)
                }
            }
        }

        conflictedFiles = conflicts

        // Show first conflict if any found
        if let firstConflict = conflictInfos.first {
            currentConflict = firstConflict
            showingConflictDialog = true

            // Notify user
            NotificationService.shared.notifyConflictDetected(
                fileCount: conflicts.count,
                fileName: firstConflict.file.filename
            )
        }
    }

    /// Remove file from conflict list
    private func removeFromConflicts(_ file: ConfigFile) {
        conflictedFiles.removeAll { $0.id == file.id }

        // If more conflicts remain, show next one
        if !conflictedFiles.isEmpty, let nextFile = conflictedFiles.first {
            Task {
                // Load next conflict
                guard let provider = cloudProvider,
                      let remoteFiles = try? await provider.listFiles(),
                      let remoteFile = remoteFiles.first(where: { $0.path.contains(nextFile.filename) }),
                      let localContent = try? String(contentsOfFile: nextFile.path, encoding: .utf8),
                      let remoteData = try? await provider.download(file: nextFile),
                      let remoteContent = String(data: remoteData, encoding: .utf8) else {
                    return
                }

                currentConflict = ConflictInfo(
                    file: nextFile,
                    localContent: localContent,
                    remoteContent: remoteContent,
                    localDate: nextFile.lastModified,
                    remoteDate: remoteFile.lastModified
                )
                showingConflictDialog = true
            }
        }
    }
}

/// Information about a file conflict
struct ConflictInfo: Identifiable {
    let id = UUID()
    let file: ConfigFile
    let localContent: String
    let remoteContent: String
    let localDate: Date
    let remoteDate: Date
}
