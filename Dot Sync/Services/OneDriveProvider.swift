//
//  OneDriveProvider.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/6/26.
//

import Foundation

/// OneDrive storage provider using Microsoft Graph API
class OneDriveProvider: BaseCloudProvider, CloudStorageProtocol {

    private var accessToken: String?
    private var tokenExpiry: Date?

    var isConfigured: Bool {
        credentials?.clientId != nil && credentials?.refreshToken != nil
    }

    func upload(file: ConfigFile, data: Data) async throws {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let storagePath = storagePath(for: file)

        // OneDrive upload URL: PUT /me/drive/root:/path/to/file:/content
        let encodedPath = storagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storagePath
        let urlString = "https://graph.microsoft.com/v1.0/me/drive/root:/\(encodedPath):/content"

        guard let url = URL(string: urlString) else {
            throw CloudStorageError.uploadFailed(NSError(domain: "OneDriveProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.uploadFailed(NSError(domain: "OneDriveProvider", code: -1))
        }
    }

    func download(file: ConfigFile) async throws -> Data {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let storagePath = storagePath(for: file)

        // OneDrive download URL: GET /me/drive/root:/path/to/file:/content
        let encodedPath = storagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storagePath
        let urlString = "https://graph.microsoft.com/v1.0/me/drive/root:/\(encodedPath):/content"

        guard let url = URL(string: urlString) else {
            throw CloudStorageError.downloadFailed(NSError(domain: "OneDriveProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudStorageError.downloadFailed(NSError(domain: "OneDriveProvider", code: -1))
        }

        if httpResponse.statusCode == 404 {
            throw CloudStorageError.fileNotFound(storagePath)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.downloadFailed(NSError(domain: "OneDriveProvider", code: httpResponse.statusCode))
        }

        return data
    }

    func listFiles() async throws -> [RemoteFile] {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let prefix = "\(config.folderPath)/configs"

        // List files in folder: GET /me/drive/root:/folder:/children
        let encodedPath = prefix.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? prefix
        let urlString = "https://graph.microsoft.com/v1.0/me/drive/root:/\(encodedPath):/children"

        guard let url = URL(string: urlString) else {
            throw CloudStorageError.networkError(NSError(domain: "OneDriveProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.networkError(NSError(domain: "OneDriveProvider", code: -1))
        }

        return try parseOneDriveListResponse(data)
    }

    func delete(file: ConfigFile) async throws {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let storagePath = storagePath(for: file)

        // Delete: DELETE /me/drive/root:/path/to/file
        let encodedPath = storagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? storagePath
        let urlString = "https://graph.microsoft.com/v1.0/me/drive/root:/\(encodedPath)"

        guard let url = URL(string: urlString) else {
            throw CloudStorageError.networkError(NSError(domain: "OneDriveProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            throw CloudStorageError.networkError(NSError(domain: "OneDriveProvider", code: -1))
        }
    }

    func getMetadata(for file: ConfigFile) async throws -> RemoteFile? {
        let files = try await listFiles()
        return files.first { $0.path.contains(file.filename) }
    }

    func testConnection() async throws -> Bool {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        // Test by getting user profile
        let token = try await getAccessToken()

        let urlString = "https://graph.microsoft.com/v1.0/me"
        guard let url = URL(string: urlString) else {
            throw CloudStorageError.networkError(NSError(domain: "OneDriveProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.authenticationFailed
        }

        return true
    }

    // MARK: - Helpers

    private func getAccessToken() async throws -> String {
        // Check if we have a valid cached token
        if let token = accessToken,
           let expiry = tokenExpiry,
           expiry > Date() {
            return token
        }

        // Refresh token
        guard let clientId = credentials?.clientId,
              let clientSecret = credentials?.clientSecret,
              let refreshToken = credentials?.refreshToken else {
            throw CloudStorageError.invalidCredentials
        }

        let tokenURL = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = """
        grant_type=refresh_token&\
        client_id=\(clientId)&\
        client_secret=\(clientSecret)&\
        refresh_token=\(refreshToken)&\
        scope=Files.ReadWrite.All offline_access
        """
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.authenticationFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw CloudStorageError.authenticationFailed
        }

        // Cache token
        accessToken = token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60)) // Refresh 60s early

        return token
    }

    private func parseOneDriveListResponse(_ data: Data) throws -> [RemoteFile] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["value"] as? [[String: Any]] else {
            return []
        }

        var files: [RemoteFile] = []

        for item in items {
            // Skip folders
            guard item["folder"] == nil else { continue }

            guard let name = item["name"] as? String,
                  let size = item["size"] as? Int,
                  let lastModifiedString = item["lastModifiedDateTime"] as? String else {
                continue
            }

            let formatter = ISO8601DateFormatter()
            let date = formatter.date(from: lastModifiedString) ?? Date()

            files.append(RemoteFile(path: name, size: Int64(size), lastModified: date, checksum: nil))
        }

        return files
    }
}
