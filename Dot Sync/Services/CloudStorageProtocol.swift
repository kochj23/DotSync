//
//  CloudStorageProtocol.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Protocol for cloud storage providers
protocol CloudStorageProtocol {
    /// Upload file to cloud storage
    func upload(file: ConfigFile, data: Data) async throws

    /// Download file from cloud storage
    func download(file: ConfigFile) async throws -> Data

    /// List all files in cloud storage
    func listFiles() async throws -> [RemoteFile]

    /// Delete file from cloud storage
    func delete(file: ConfigFile) async throws

    /// Get metadata for remote file
    func getMetadata(for file: ConfigFile) async throws -> RemoteFile?

    /// Check if provider is configured
    var isConfigured: Bool { get }

    /// Test connection
    func testConnection() async throws -> Bool
}

/// Remote file metadata
struct RemoteFile: Codable {
    let path: String
    let size: Int64
    let lastModified: Date
    let checksum: String?
}

/// Cloud storage errors
enum CloudStorageError: LocalizedError {
    case notConfigured
    case authenticationFailed
    case networkError(Error)
    case fileNotFound(String)
    case uploadFailed(Error)
    case downloadFailed(Error)
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Cloud storage not configured"
        case .authenticationFailed:
            return "Authentication failed - check credentials"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .uploadFailed(let error):
            return "Upload failed: \(error.localizedDescription)"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .invalidCredentials:
            return "Invalid credentials"
        }
    }
}

/// Base cloud provider implementation
class BaseCloudProvider {
    let config: CloudProviderConfig
    let credentials: CloudCredentials?

    init(config: CloudProviderConfig, credentials: CloudCredentials?) {
        self.config = config
        self.credentials = credentials
    }

    /// Build storage path for file
    func storagePath(for file: ConfigFile) -> String {
        // dot-sync/configs/shell/zshrc
        let category = file.category.rawValue.lowercased()
        return "\(config.folderPath)/configs/\(category)/\(file.filename)"
    }

    /// Create URLRequest with auth headers (subclasses override)
    func createAuthenticatedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }
}
