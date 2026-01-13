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

        let homeDir = fileManager.homeDirectoryForCurrentUser

        // Try multiple iCloud Drive paths (macOS versions vary)
        let possiblePaths = [
            // Modern macOS (10.15+): ~/Library/Mobile Documents/com~apple~CloudDocs/
            homeDir.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"),
            // Alternative path for some systems
            homeDir.appendingPathComponent("Library/CloudStorage/iCloud Drive"),
            // Google Drive (commonly confused with iCloud)
            homeDir.appendingPathComponent("My Drive"),
            // Direct iCloud Drive symlink
            homeDir.appendingPathComponent("iCloud Drive"),
            // If user specified full path, try it directly
            URL(fileURLWithPath: config.bucket.hasPrefix("/") ? config.bucket : homeDir.appendingPathComponent(config.bucket).path),
        ]

        var iCloudDriveBase: URL?
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path.path) {
                iCloudDriveBase = path
                print("[iCloudProvider] ✅ Found iCloud Drive at: \(path.path)")
                break
            }
        }

        // Determine final iCloud folder path
        var iCloudFolder: URL

        if let baseURL = iCloudDriveBase {
            // Found iCloud Drive base, append user's folder name
            iCloudFolder = baseURL.appendingPathComponent(config.bucket)
        } else if config.bucket.hasPrefix("/") || config.bucket.hasPrefix("~") {
            // User provided full path
            let expandedPath = config.bucket.replacingOccurrences(of: "~", with: homeDir.path)
            iCloudFolder = URL(fileURLWithPath: expandedPath)
            print("[iCloudProvider] Using user-specified path: \(iCloudFolder.path)")
        } else {
            // Can't determine path - log diagnostics
            print("[iCloudProvider] ⚠️ iCloud Drive not found. Tried paths:")
            for path in possiblePaths {
                print("  - \(path.path) [exists: \(fileManager.fileExists(atPath: path.path))]")
            }
            print("[iCloudProvider] Folder name entered: '\(config.bucket)'")
            return
        }

        // Verify or create the folder
        if fileManager.fileExists(atPath: iCloudFolder.path) {
            print("[iCloudProvider] ✅ Found existing folder: \(iCloudFolder.path)")
        } else {
            do {
                try fileManager.createDirectory(at: iCloudFolder, withIntermediateDirectories: true)
                print("[iCloudProvider] ✅ Created iCloud Drive folder: \(iCloudFolder.path)")
            } catch {
                print("[iCloudProvider] ❌ Error creating folder: \(error)")
                return
            }
        }

        containerURL = iCloudFolder
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
        // NOTE: DO NOT skip hidden files - most config files start with dot (.)
        guard let enumerator = fileManager.enumerator(
            at: configsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: []  // No options - include hidden files
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }

            let filename = fileURL.lastPathComponent

            // Skip system files and metadata
            if filename == ".DS_Store" || filename.hasSuffix(".metadata.json") || filename.hasSuffix(".ancestor") {
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
