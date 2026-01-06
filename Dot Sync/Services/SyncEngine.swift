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
        // Execute pre-sync hooks
        let preHookResults = await HookManager.shared.executePreSyncHooks(for: file)
        for result in preHookResults where !result.success {
            let hook = HookManager.shared.hooks.preSyncHooks.first { !$0.continueOnError }
            if hook != nil {
                print("[SyncEngine] ❌ Pre-sync hook failed for \(file.filename)")
                throw CloudStorageError.uploadFailed(
                    NSError(domain: "SyncEngine", code: 1003,
                           userInfo: [NSLocalizedDescriptionKey: "Pre-sync validation failed: \(result.output)"])
                )
            }
        }

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

        // Create metadata with machine info
        let metadata = SyncMetadata.create(for: file)
        try await uploadMetadata(metadata, for: file, using: provider)

        try await provider.upload(file: file, data: data)
        print("[SyncEngine] ✅ Uploaded \(file.filename) from \(metadata.machineInfo.shortDisplayName)")

        // Execute post-sync hooks
        let postHookResults = await HookManager.shared.executePostSyncHooks(for: file)
        for result in postHookResults where result.success {
            print("[SyncEngine] ✅ Post-sync hook: \(result.output.prefix(50))...")
        }
    }

    /// Download individual file
    private func downloadFile(_ file: ConfigFile, using provider: CloudStorageProtocol) async throws {
        // Try to get metadata first
        let metadata = try? await downloadMetadata(for: file, using: provider)
        let sourceMachine = metadata?.machineInfo.shortDisplayName ?? "unknown"

        let data = try await provider.download(file: file)

        // Execute pre-sync hooks (downloads can also have validation)
        let preHookResults = await HookManager.shared.executePreSyncHooks(for: file)
        for result in preHookResults where !result.success {
            let hook = HookManager.shared.hooks.preSyncHooks.first { !$0.continueOnError }
            if hook != nil {
                print("[SyncEngine] ❌ Pre-download hook failed for \(file.filename)")
                throw CloudStorageError.downloadFailed(
                    NSError(domain: "SyncEngine", code: 1004,
                           userInfo: [NSLocalizedDescriptionKey: "Pre-download validation failed"])
                )
            }
        }

        // Create versioned backup (keep last 5)
        let url = URL(fileURLWithPath: file.path)
        if FileManager.default.fileExists(atPath: file.path) {
            try createVersionedBackup(for: file.path)
        }

        // Write downloaded data
        try data.write(to: url, options: .atomic)
        print("[SyncEngine] ✅ Downloaded \(file.filename) from \(sourceMachine)")

        // Execute post-sync hooks
        let postHookResults = await HookManager.shared.executePostSyncHooks(for: file)
        for result in postHookResults where result.success {
            print("[SyncEngine] ✅ Post-sync hook completed")
        }
    }

    /// Upload metadata alongside file
    private func uploadMetadata(_ metadata: SyncMetadata, for file: ConfigFile, using provider: CloudStorageProtocol) async throws {
        guard let metadataJSON = try? JSONEncoder().encode(metadata),
              let metadataData = try? JSONSerialization.data(withJSONObject: try JSONSerialization.jsonObject(with: metadataJSON), options: .prettyPrinted) else {
            return
        }

        // Create metadata file with modified path
        let metadataPath = file.path + ".metadata.json"
        let metadataFile = ConfigFile(
            path: metadataPath,
            relativePath: file.relativePath + ".metadata.json",
            filename: file.filename + ".metadata.json",
            category: file.category,
            size: Int64(metadataData.count),
            lastModified: Date(),
            checksum: "",
            isSafeToSync: true,
            syncPriority: file.syncPriority,
            isDirectory: false
        )

        try? await provider.upload(file: metadataFile, data: metadataData)
    }

    /// Download metadata for file
    private func downloadMetadata(for file: ConfigFile, using provider: CloudStorageProtocol) async throws -> SyncMetadata {
        let metadataPath = file.path + ".metadata.json"
        let metadataFile = ConfigFile(
            path: metadataPath,
            relativePath: file.relativePath + ".metadata.json",
            filename: file.filename + ".metadata.json",
            category: file.category,
            size: 0,
            lastModified: Date(),
            checksum: "",
            isSafeToSync: true,
            syncPriority: file.syncPriority,
            isDirectory: false
        )

        let data = try await provider.download(file: metadataFile)
        let metadata = try JSONDecoder().decode(SyncMetadata.self, from: data)
        return metadata
    }

    /// Store ancestor version for three-way merge
    func storeAncestor(for file: ConfigFile, content: String) throws {
        let ancestorPath = file.path + ".ancestor"
        try content.data(using: .utf8)?.write(to: URL(fileURLWithPath: ancestorPath), options: .atomic)
        print("[SyncEngine] 📝 Stored ancestor version for \(file.filename)")
    }

    /// Get ancestor version for three-way merge
    func getAncestor(for file: ConfigFile) -> String? {
        let ancestorPath = file.path + ".ancestor"
        return try? String(contentsOfFile: ancestorPath, encoding: .utf8)
    }

    /// Attempt automatic three-way merge
    func attemptThreeWayMerge(for file: ConfigFile, localContent: String, remoteContent: String) async -> ThreeWayMergeAttempt {
        // Get ancestor version
        guard let ancestorContent = getAncestor(for: file) else {
            return ThreeWayMergeAttempt(
                success: false,
                mergedContent: nil,
                conflicts: [],
                reason: "No ancestor version found - using two-way comparison"
            )
        }

        // Perform three-way merge
        let mergeResult = ThreeWayMerge.merge(
            ancestor: ancestorContent,
            local: localContent,
            remote: remoteContent
        )

        if mergeResult.hasConflicts {
            return ThreeWayMergeAttempt(
                success: false,
                mergedContent: mergeResult.mergedContent,
                conflicts: mergeResult.conflicts,
                reason: "Found \(mergeResult.conflicts.count) conflicting lines, but auto-merged \(mergeResult.autoMergedLines) lines"
            )
        } else {
            return ThreeWayMergeAttempt(
                success: true,
                mergedContent: mergeResult.mergedContent,
                conflicts: [],
                reason: "Successfully auto-merged \(mergeResult.autoMergedLines) lines with no conflicts"
            )
        }
    }

    /// Create versioned backup and maintain history (keep last 5)
    private func createVersionedBackup(for filePath: String) throws {
        let fileManager = FileManager.default
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")

        let backupPath = "\(filePath).backup.\(timestamp)"

        // Create new backup
        try fileManager.copyItem(atPath: filePath, toPath: backupPath)
        print("[SyncEngine] 💾 Created backup: \(URL(fileURLWithPath: backupPath).lastPathComponent)")

        // Clean up old backups (keep last 5)
        let parentDir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let filename = URL(fileURLWithPath: filePath).lastPathComponent

        guard let files = try? fileManager.contentsOfDirectory(atPath: parentDir.path) else {
            return
        }

        // Find all backups for this file
        let backupFiles = files
            .filter { $0.hasPrefix("\(filename).backup.") }
            .map { parentDir.appendingPathComponent($0).path }
            .sorted { path1, path2 in
                let date1 = (try? fileManager.attributesOfItem(atPath: path1)[.modificationDate] as? Date) ?? .distantPast
                let date2 = (try? fileManager.attributesOfItem(atPath: path2)[.modificationDate] as? Date) ?? .distantPast
                return date1 > date2 // Newest first
            }

        // Keep only the 5 most recent backups
        if backupFiles.count > 5 {
            for oldBackup in backupFiles.dropFirst(5) {
                try? fileManager.removeItem(atPath: oldBackup)
                print("[SyncEngine] 🗑️ Removed old backup: \(URL(fileURLWithPath: oldBackup).lastPathComponent)")
            }
        }
    }

    /// Get backup history for a file
    func getBackupHistory(for file: ConfigFile) -> [BackupVersion] {
        let fileManager = FileManager.default
        let parentDir = URL(fileURLWithPath: file.path).deletingLastPathComponent()
        let filename = file.filename

        guard let files = try? fileManager.contentsOfDirectory(atPath: parentDir.path) else {
            return []
        }

        let backups = files
            .filter { $0.hasPrefix("\(filename).backup.") }
            .compactMap { backupFile -> BackupVersion? in
                let backupPath = parentDir.appendingPathComponent(backupFile).path
                guard let attrs = try? fileManager.attributesOfItem(atPath: backupPath),
                      let modDate = attrs[.modificationDate] as? Date,
                      let size = attrs[.size] as? Int64 else {
                    return nil
                }
                return BackupVersion(path: backupPath, date: modDate, size: size)
            }
            .sorted { $0.date > $1.date }

        return backups
    }

    /// Restore from backup
    func restoreFromBackup(_ backup: BackupVersion, to file: ConfigFile) throws {
        let fileManager = FileManager.default

        // Backup current version first
        if fileManager.fileExists(atPath: file.path) {
            try createVersionedBackup(for: file.path)
        }

        // Restore from backup
        try fileManager.copyItem(atPath: backup.path, toPath: file.path)
        print("[SyncEngine] ♻️ Restored from backup: \(URL(fileURLWithPath: backup.path).lastPathComponent)")

        NotificationService.shared.notify(
            title: "Backup Restored",
            body: "\(file.filename) restored from \(DateFormatter.localizedString(from: backup.date, dateStyle: .short, timeStyle: .short))"
        )
    }

    // MARK: - Conflict Resolution

    /// Resolve conflict for a file
    func resolveConflict(for file: ConfigFile, resolution: ConflictResolution) async throws {
        switch resolution {
        case .useLocal:
            // Store current local version as ancestor for future merges
            if let localContent = try? String(contentsOfFile: file.path, encoding: .utf8) {
                try? storeAncestor(for: file, content: localContent)
            }
            try await sync(files: [file], direction: .upload)
            removeFromConflicts(file)
        case .useRemote:
            // Store remote version as ancestor for future merges
            if let provider = cloudProvider,
               let remoteData = try? await provider.download(file: file),
               let remoteContent = String(data: remoteData, encoding: .utf8) {
                try? storeAncestor(for: file, content: remoteContent)
            }
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
                // Load file contents for potential merge
                guard let localContent = try? String(contentsOfFile: file.path, encoding: .utf8),
                      let remoteData = try? await provider.download(file: file),
                      let remoteContent = String(data: remoteData, encoding: .utf8) else {
                    continue
                }

                // Try three-way merge first
                let mergeAttempt = await attemptThreeWayMerge(
                    for: file,
                    localContent: localContent,
                    remoteContent: remoteContent
                )

                if mergeAttempt.canAutoApply {
                    // Auto-merge successful!
                    print("[SyncEngine] ✅ Auto-merged \(file.filename) - \(mergeAttempt.reason)")

                    // Apply merged content
                    if let mergedContent = mergeAttempt.mergedContent {
                        try? mergedContent.data(using: .utf8)?.write(to: URL(fileURLWithPath: file.path), options: .atomic)
                        try? await uploadFile(file, using: provider)

                        NotificationService.shared.notify(
                            title: "Auto-Merge Successful",
                            body: "\(file.filename) - \(mergeAttempt.reason)"
                        )
                    }
                } else {
                    // Manual resolution needed
                    conflicts.append(file)

                    let info = ConflictInfo(
                        file: file,
                        localContent: localContent,
                        remoteContent: remoteContent,
                        localDate: file.lastModified,
                        remoteDate: remoteFile.lastModified,
                        ancestorContent: getAncestor(for: file),
                        mergeAttempt: mergeAttempt
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

                // Try three-way merge
                let mergeAttempt = await attemptThreeWayMerge(
                    for: nextFile,
                    localContent: localContent,
                    remoteContent: remoteContent
                )

                currentConflict = ConflictInfo(
                    file: nextFile,
                    localContent: localContent,
                    remoteContent: remoteContent,
                    localDate: nextFile.lastModified,
                    remoteDate: remoteFile.lastModified,
                    ancestorContent: getAncestor(for: nextFile),
                    mergeAttempt: mergeAttempt
                )
                showingConflictDialog = true
            }
        }
    }
}

/// Information about a file conflict
struct ConflictInfo: Identifiable {
    let id: UUID
    let file: ConfigFile
    let localContent: String
    let remoteContent: String
    let localDate: Date
    let remoteDate: Date
    let ancestorContent: String?
    let mergeAttempt: ThreeWayMergeAttempt?

    init(file: ConfigFile, localContent: String, remoteContent: String,
         localDate: Date, remoteDate: Date,
         ancestorContent: String? = nil, mergeAttempt: ThreeWayMergeAttempt? = nil) {
        self.id = UUID()
        self.file = file
        self.localContent = localContent
        self.remoteContent = remoteContent
        self.localDate = localDate
        self.remoteDate = remoteDate
        self.ancestorContent = ancestorContent
        self.mergeAttempt = mergeAttempt
    }

    var hasAncestor: Bool {
        ancestorContent != nil
    }

    var canAutoMerge: Bool {
        mergeAttempt?.canAutoApply ?? false
    }
}
