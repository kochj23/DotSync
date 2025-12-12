//
//  iCloudProvider.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// iCloud Drive provider using NSFileCoordinator
class iCloudProvider: BaseCloudProvider, CloudStorageProtocol {

    private let fileManager = FileManager.default
    private var containerURL: URL?

    override init(config: CloudProviderConfig, credentials: CloudCredentials?) {
        super.init(config: config, credentials: credentials)

        // Get iCloud container URL
        if let url = fileManager.url(forUbiquityContainerIdentifier: nil) {
            containerURL = url.appendingPathComponent(config.folderPath)

            // Create folder structure if needed
            try? fileManager.createDirectory(at: containerURL!, withIntermediateDirectories: true)
        }
    }

    var isConfigured: Bool {
        containerURL != nil
    }

    func upload(file: ConfigFile, data: Data) async throws {
        guard let containerURL = containerURL else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let destinationURL = containerURL.appendingPathComponent(storagePath)

        // Create intermediate directories
        let parentDir = destinationURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Use NSFileCoordinator for iCloud operations
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            coordinator.coordinate(writingItemAt: destinationURL, options: .forReplacing, error: &coordinatorError) { url in
                do {
                    try data.write(to: url, options: [.atomic])

                    // Files in ubiquity container are automatically uploaded to iCloud
                    // No need to manually set isUbiquitous

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
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

        // Use NSFileCoordinator for safe iCloud reading
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            coordinator.coordinate(readingItemAt: sourceURL, options: [], error: &coordinatorError) { url in
                do {
                    // Download if needed
                    try? fileManager.startDownloadingUbiquitousItem(at: url)

                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
    }

    func listFiles() async throws -> [RemoteFile] {
        guard let containerURL = containerURL else {
            throw CloudStorageError.notConfigured
        }

        let configsURL = containerURL.appendingPathComponent("configs")

        // Ensure directory exists
        if !fileManager.fileExists(atPath: configsURL.path) {
            return []
        }

        var files: [RemoteFile] = []

        // Recursively list all files (using Task to avoid async context warning)
        await Task {
            if let enumerator = fileManager.enumerator(at: configsURL,
                                                       includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                                       options: [.skipsHiddenFiles]) {
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
            }
        }.value

        return files
    }

    func delete(file: ConfigFile) async throws {
        guard let containerURL = containerURL else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let fileURL = containerURL.appendingPathComponent(storagePath)

        // Use NSFileCoordinator for safe deletion
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            coordinator.coordinate(writingItemAt: fileURL, options: .forDeleting, error: &coordinatorError) { url in
                do {
                    try fileManager.removeItem(at: url)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            if let error = coordinatorError {
                continuation.resume(throwing: error)
            }
        }
    }

    func getMetadata(for file: ConfigFile) async throws -> RemoteFile? {
        let files = try await listFiles()
        return files.first { $0.path.contains(file.filename) }
    }

    func testConnection() async throws -> Bool {
        guard containerURL != nil else {
            throw CloudStorageError.notConfigured
        }

        // Check if iCloud is available
        guard fileManager.ubiquityIdentityToken != nil else {
            throw CloudStorageError.authenticationFailed
        }

        // Try to create a test file
        let testURL = containerURL!.appendingPathComponent(".dotsync-test")
        let testData = "test".data(using: .utf8)!

        try testData.write(to: testURL)
        try? fileManager.removeItem(at: testURL)

        return true
    }

    // MARK: - Helpers

    private func getAccessToken() async throws -> String {
        // iCloud doesn't use OAuth - it uses system authentication
        // This method is not needed but kept for protocol consistency
        return ""
    }
}
