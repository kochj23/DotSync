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

    private var cloudProvider: CloudStorageProtocol?

    // MARK: - Configuration

    /// Set cloud provider
    func configure(provider: CloudProviderConfig, credentials: CloudCredentials?) {
        currentProvider = provider

        switch provider.type {
        case .awsS3, .s3Compatible:
            cloudProvider = S3Provider(config: provider, credentials: credentials)
        case .azureBlob:
            // cloudProvider = AzureProvider(config: provider, credentials: credentials)
            cloudProvider = nil // Placeholder
        case .googleCloud:
            // cloudProvider = GCPProvider(config: provider, credentials: credentials)
            cloudProvider = nil // Placeholder
        case .iCloud:
            // cloudProvider = iCloudProvider(config: provider, credentials: nil)
            cloudProvider = nil // Placeholder
        }
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
    func sync(files: [ConfigFile], direction: SyncDirection) async throws {
        guard let provider = cloudProvider else {
            throw CloudStorageError.notConfigured
        }

        isSyncing = true
        defer { isSyncing = false }

        for file in files {
            do {
                switch direction {
                case .upload:
                    try await uploadFile(file, using: provider)
                case .download:
                    try await downloadFile(file, using: provider)
                case .skip:
                    continue
                }
            } catch {
                print("[SyncEngine] Error syncing \(file.filename): \(error)")
                // Continue with other files
            }
        }

        lastSyncDate = Date()

        // Re-analyze after sync
        try await analyzeSyncStatus(for: files)
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
        case .useRemote:
            try await sync(files: [file], direction: .download)
        case .skip:
            return
        case .merge:
            // Manual merge - user must handle externally
            throw NSError(domain: "SyncEngine", code: 1002,
                         userInfo: [NSLocalizedDescriptionKey: "Manual merge not yet implemented"])
        }
    }
}
