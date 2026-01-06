//
//  NASProvider.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/6/26.
//

import Foundation

/// NAS (SMB/NFS) storage provider
class NASProvider: BaseCloudProvider, CloudStorageProtocol {

    private let fileManager = FileManager.default
    private var mountedURL: URL?

    var isConfigured: Bool {
        credentials?.serverAddress != nil && credentials?.sharePath != nil
    }

    override init(config: CloudProviderConfig, credentials: CloudCredentials?) {
        super.init(config: config, credentials: credentials)

        // Attempt to mount the share
        if let serverAddress = credentials?.serverAddress,
           let sharePath = credentials?.sharePath {
            mountShare(server: serverAddress, share: sharePath)
        }
    }

    private func mountShare(server: String, share: String) {
        // For SMB: smb://server/share
        // For NFS: nfs://server/share
        let protocolScheme = share.contains("nfs://") ? "" : "smb://"
        let urlString = "\(protocolScheme)\(server)/\(share)"

        if let url = URL(string: urlString) {
            // Check if already mounted
            let volumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [])
            if let mounted = volumes?.first(where: { $0.path.contains(share) }) {
                mountedURL = mounted
            } else {
                // For macOS, SMB shares auto-mount when accessed
                // We'll use /Volumes/ShareName as the mount point
                let volumePath = "/Volumes/\(share.components(separatedBy: "/").last ?? share)"
                mountedURL = URL(fileURLWithPath: volumePath)
            }
        }
    }

    func upload(file: ConfigFile, data: Data) async throws {
        guard let mountedURL = mountedURL else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let destinationURL = mountedURL.appendingPathComponent(config.folderPath).appendingPathComponent(storagePath)

        // Create intermediate directories
        let parentDir = destinationURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Write file
        try data.write(to: destinationURL, options: [.atomic])
    }

    func download(file: ConfigFile) async throws -> Data {
        guard let mountedURL = mountedURL else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let sourceURL = mountedURL.appendingPathComponent(config.folderPath).appendingPathComponent(storagePath)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CloudStorageError.fileNotFound(storagePath)
        }

        return try Data(contentsOf: sourceURL)
    }

    func listFiles() async throws -> [RemoteFile] {
        guard let mountedURL = mountedURL else {
            throw CloudStorageError.notConfigured
        }

        let configsURL = mountedURL.appendingPathComponent(config.folderPath).appendingPathComponent("configs")

        guard fileManager.fileExists(atPath: configsURL.path) else {
            return []
        }

        var files: [RemoteFile] = []

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

                let relativePath = fileURL.path.replacingOccurrences(of: mountedURL.path + "/", with: "")

                files.append(RemoteFile(path: relativePath, size: size, lastModified: lastModified, checksum: nil))
            }
        }

        return files
    }

    func delete(file: ConfigFile) async throws {
        guard let mountedURL = mountedURL else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let fileURL = mountedURL.appendingPathComponent(config.folderPath).appendingPathComponent(storagePath)

        try fileManager.removeItem(at: fileURL)
    }

    func getMetadata(for file: ConfigFile) async throws -> RemoteFile? {
        let files = try await listFiles()
        return files.first { $0.path.contains(file.filename) }
    }

    func testConnection() async throws -> Bool {
        guard let mountedURL = mountedURL else {
            throw CloudStorageError.notConfigured
        }

        // Check if mount point is accessible
        guard fileManager.fileExists(atPath: mountedURL.path) else {
            throw CloudStorageError.networkError(NSError(domain: "NASProvider", code: 1001,
                                                         userInfo: [NSLocalizedDescriptionKey: "NAS share not mounted or accessible"]))
        }

        // Try to create test directory
        let testURL = mountedURL.appendingPathComponent(config.folderPath)
        try? fileManager.createDirectory(at: testURL, withIntermediateDirectories: true)

        return true
    }
}
