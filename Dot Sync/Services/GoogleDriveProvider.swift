//
//  GoogleDriveProvider.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/6/26.
//

import Foundation

/// Google Drive storage provider using Drive API v3
class GoogleDriveProvider: BaseCloudProvider, CloudStorageProtocol {

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

        // Create or update file using multipart upload
        let boundary = "dotSyncBoundary"
        let metadata = """
        {
            "name": "\(file.filename)",
            "parents": ["\(config.bucket)"]
        }
        """

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadata.data(using: .utf8)!)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)

        let urlString = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
        guard let url = URL(string: urlString) else {
            throw CloudStorageError.uploadFailed(NSError(domain: "GoogleDriveProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.uploadFailed(NSError(domain: "GoogleDriveProvider", code: -1))
        }
    }

    func download(file: ConfigFile) async throws -> Data {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()

        // First, find the file ID
        let fileId = try await getFileId(filename: file.filename)

        // Download file content: GET /files/{fileId}?alt=media
        let urlString = "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media"
        guard let url = URL(string: urlString) else {
            throw CloudStorageError.downloadFailed(NSError(domain: "GoogleDriveProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudStorageError.downloadFailed(NSError(domain: "GoogleDriveProvider", code: -1))
        }

        if httpResponse.statusCode == 404 {
            throw CloudStorageError.fileNotFound(file.filename)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.downloadFailed(NSError(domain: "GoogleDriveProvider", code: httpResponse.statusCode))
        }

        return data
    }

    func listFiles() async throws -> [RemoteFile] {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()

        // List files: GET /files?q='folderId' in parents
        let query = "'\(config.bucket)' in parents and trashed=false"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        let urlString = "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name,size,modifiedTime)"
        guard let url = URL(string: urlString) else {
            throw CloudStorageError.networkError(NSError(domain: "GoogleDriveProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.networkError(NSError(domain: "GoogleDriveProvider", code: -1))
        }

        return try parseGoogleDriveListResponse(data)
    }

    func delete(file: ConfigFile) async throws {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let fileId = try await getFileId(filename: file.filename)

        // Delete: DELETE /files/{fileId}
        let urlString = "https://www.googleapis.com/drive/v3/files/\(fileId)"
        guard let url = URL(string: urlString) else {
            throw CloudStorageError.networkError(NSError(domain: "GoogleDriveProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            throw CloudStorageError.networkError(NSError(domain: "GoogleDriveProvider", code: -1))
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

        // Test by getting user info
        let token = try await getAccessToken()

        let urlString = "https://www.googleapis.com/drive/v3/about?fields=user"
        guard let url = URL(string: urlString) else {
            throw CloudStorageError.networkError(NSError(domain: "GoogleDriveProvider", code: -1))
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

        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = """
        grant_type=refresh_token&\
        client_id=\(clientId)&\
        client_secret=\(clientSecret)&\
        refresh_token=\(refreshToken)
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
        tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn - 60))

        return token
    }

    private func getFileId(filename: String) async throws -> String {
        let token = try await getAccessToken()

        let query = "name='\(filename)' and '\(config.bucket)' in parents and trashed=false"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        let urlString = "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id)"
        guard let url = URL(string: urlString) else {
            throw CloudStorageError.fileNotFound(filename)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.fileNotFound(filename)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]],
              let firstFile = files.first,
              let fileId = firstFile["id"] as? String else {
            throw CloudStorageError.fileNotFound(filename)
        }

        return fileId
    }

    private func parseGoogleDriveListResponse(_ data: Data) throws -> [RemoteFile] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            return []
        }

        var remoteFiles: [RemoteFile] = []

        for file in files {
            guard let name = file["name"] as? String,
                  let sizeString = file["size"] as? String,
                  let size = Int64(sizeString),
                  let modifiedTimeString = file["modifiedTime"] as? String else {
                continue
            }

            let formatter = ISO8601DateFormatter()
            let date = formatter.date(from: modifiedTimeString) ?? Date()

            remoteFiles.append(RemoteFile(path: name, size: size, lastModified: date, checksum: nil))
        }

        return remoteFiles
    }
}
