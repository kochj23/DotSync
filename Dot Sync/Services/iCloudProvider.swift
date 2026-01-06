//
//  iCloudProvider.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// iCloud Drive provider using standard file system access
class iCloudProvider: BaseCloudProvider, CloudStorageProtocol {

    private let fileManager = FileManager.default
    private var containerURL: URL?

    override init(config: CloudProviderConfig, credentials: CloudCredentials?) {
        super.init(config: config, credentials: credentials)

        // Use standard iCloud Drive path: ~/Library/Mobile Documents/com~apple~CloudDocs/
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let iCloudDriveBase = homeDir
            .appendingPathComponent("Library")
            .appendingPathComponent("Mobile Documents")
            .appendingPathComponent("com~apple~CloudDocs")

        // User specifies folder name in config.bucket (e.g., "DotFiles")
        let iCloudFolder = iCloudDriveBase.appendingPathComponent(config.bucket)

        // Verify iCloud Drive is accessible
        if fileManager.fileExists(atPath: iCloudDriveBase.path) {
            containerURL = iCloudFolder

            // Create folder structure if needed
            try? fileManager.createDirectory(at: containerURL!, withIntermediateDirectories: true)
            print("[iCloudProvider] Using iCloud Drive folder: \(iCloudFolder.path)")
        } else {
            print("[iCloudProvider] ⚠️ iCloud Drive not accessible at: \(iCloudDriveBase.path)")
        }
    }

    var isConfigured: Bool {
        // Check if we have a valid container URL and it exists
        guard let url = containerURL else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    func upload(file: ConfigFile, data: Data) async throws {
        guard let containerURL = containerURL else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let destinationURL = containerURL.appendingPathComponent(storagePath)

        // Create intermediate directories
        let parentDir = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Write file to iCloud Drive (standard file operations)
        // Files written to ~/Library/Mobile Documents/com~apple~CloudDocs/ are automatically synced
        try data.write(to: destinationURL, options: [.atomic])
        print("[iCloudProvider] ✅ Uploaded \(file.filename) to iCloud Drive")
    }

    func download(file: ConfigFile) async throws -> Data {
        guard let containerURL = containerURL else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let sourceURL = containerURL.appendingPathComponent(storagePath)

        // Check if file exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CloudStorageError.fileNotFound(storagePath)
        }

        // Read file from iCloud Drive (standard file operations)
        let data = try Data(contentsOf: sourceURL)
        print("[iCloudProvider] ✅ Downloaded \(file.filename) from iCloud Drive")
        return data
    }

    func listFiles() async throws -> [RemoteFile] {
        guard let containerURL = containerURL else {
            throw CloudStorageError.notConfigured
        }

        let configsURL = containerURL.appendingPathComponent("configs")

        // Ensure directory exists
        if !fileManager.fileExists(atPath: configsURL.path) {
            try? fileManager.createDirectory(at: configsURL, withIntermediateDirectories: true)
            return []
        }

        var files: [RemoteFile] = []

        // Recursively list all files in iCloud Drive folder
        guard let enumerator = fileManager.enumerator(
            at: configsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let lastModified = resourceValues?.contentModificationDate ?? Date()
            let size = Int64(resourceValues?.fileSize ?? 0)

            let relativePath = fileURL.path.replacingOccurrences(of: containerURL.path + "/", with: "")

            files.append(RemoteFile(path: relativePath, size: size, lastModified: lastModified, checksum: nil))
        }

        return files
    }

    func delete(file: ConfigFile) async throws {
        guard let containerURL = containerURL else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let fileURL = containerURL.appendingPathComponent(storagePath)

        // Delete file from iCloud Drive (standard file operations)
        try fileManager.removeItem(at: fileURL)
        print("[iCloudProvider] ✅ Deleted \(file.filename) from iCloud Drive")
    }

    func getMetadata(for file: ConfigFile) async throws -> RemoteFile? {
        let files = try await listFiles()
        return files.first { $0.path.contains(file.filename) }
    }

    func testConnection() async throws -> Bool {
        guard let containerURL = containerURL else {
            throw CloudStorageError.notConfigured
        }

        // Check if iCloud Drive folder is accessible
        guard fileManager.fileExists(atPath: containerURL.path) else {
            throw CloudStorageError.networkError(
                NSError(domain: "iCloudProvider", code: 1001,
                       userInfo: [NSLocalizedDescriptionKey: "iCloud Drive folder not found at: \(containerURL.path)"])
            )
        }

        // Try to create a test file
        let testURL = containerURL.appendingPathComponent(".dotsync-test")
        let testData = "test".data(using: .utf8)!

        do {
            try testData.write(to: testURL, options: .atomic)
            try? fileManager.removeItem(at: testURL)
            print("[iCloudProvider] ✅ Test connection successful")
            return true
        } catch {
            throw CloudStorageError.networkError(
                NSError(domain: "iCloudProvider", code: 1002,
                       userInfo: [NSLocalizedDescriptionKey: "Cannot write to iCloud Drive: \(error.localizedDescription)"])
            )
        }
    }

}
