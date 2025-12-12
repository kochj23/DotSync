//
//  GCPProvider.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Google Cloud Storage provider
class GCPProvider: BaseCloudProvider, CloudStorageProtocol {

    var isConfigured: Bool {
        credentials?.projectId != nil && credentials?.serviceAccountKey != nil
    }

    func upload(file: ConfigFile, data: Data) async throws {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let storagePath = storagePath(for: file)
        let url = buildGCSURL(for: storagePath)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.uploadFailed(NSError(domain: "GCPProvider", code: -1))
        }
    }

    func download(file: ConfigFile) async throws -> Data {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let storagePath = storagePath(for: file)
        let url = buildGCSURL(for: storagePath, alt: "media")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudStorageError.downloadFailed(NSError(domain: "GCPProvider", code: -1))
        }

        if httpResponse.statusCode == 404 {
            throw CloudStorageError.fileNotFound(storagePath)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.downloadFailed(NSError(domain: "GCPProvider", code: httpResponse.statusCode))
        }

        return data
    }

    func listFiles() async throws -> [RemoteFile] {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let prefix = "\(config.folderPath)/configs/"

        var components = URLComponents(string: "https://storage.googleapis.com/storage/v1/b/\(config.bucket)/o")!
        components.queryItems = [URLQueryItem(name: "prefix", value: prefix)]

        guard let url = components.url else {
            throw CloudStorageError.networkError(NSError(domain: "GCPProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.networkError(NSError(domain: "GCPProvider", code: -1))
        }

        return try parseGCSListResponse(data)
    }

    func delete(file: ConfigFile) async throws {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let storagePath = storagePath(for: file)
        let url = buildGCSURL(for: storagePath)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            throw CloudStorageError.networkError(NSError(domain: "GCPProvider", code: -1))
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

        _ = try await listFiles()
        return true
    }

    // MARK: - GCS Helpers

    private func buildGCSURL(for path: String, alt: String? = nil) -> URL {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        var urlString = "https://storage.googleapis.com/storage/v1/b/\(config.bucket)/o/\(encodedPath)"

        if let alt = alt {
            urlString += "?alt=\(alt)"
        }

        return URL(string: urlString)!
    }

    /// Get OAuth access token using service account
    private func getAccessToken() async throws -> String {
        guard let serviceAccountJSON = credentials?.serviceAccountKey else {
            throw CloudStorageError.invalidCredentials
        }

        // Parse service account JSON
        guard let jsonData = serviceAccountJSON.data(using: .utf8),
              let serviceAccount = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let clientEmail = serviceAccount["client_email"] as? String,
              let privateKey = serviceAccount["private_key"] as? String else {
            throw CloudStorageError.invalidCredentials
        }

        // Create JWT for Google OAuth
        let header = [
            "alg": "RS256",
            "typ": "JWT"
        ]

        let now = Int(Date().timeIntervalSince1970)
        let claims = [
            "iss": clientEmail,
            "scope": "https://www.googleapis.com/auth/devstorage.read_write",
            "aud": "https://oauth2.googleapis.com/token",
            "exp": now + 3600,
            "iat": now
        ] as [String : Any]

        // Note: Full JWT signing would require crypto library for RS256
        // For now, this is a simplified placeholder
        // Production would use GoogleSignIn SDK or proper JWT library

        // Get token from Google OAuth
        let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Note: This is simplified - full implementation requires RS256 JWT signing
        let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=PLACEHOLDER_JWT"
        request.httpBody = body.data(using: .utf8)

        // For now, throw error indicating full implementation needed
        throw CloudStorageError.networkError(
            NSError(domain: "GCPProvider", code: 1001,
                   userInfo: [NSLocalizedDescriptionKey: "GCP OAuth requires RS256 JWT signing - use Google SDK"])
        )
    }

    private func parseGCSListResponse(_ data: Data) throws -> [RemoteFile] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        var files: [RemoteFile] = []

        for item in items {
            guard let name = item["name"] as? String,
                  let sizeString = item["size"] as? String,
                  let size = Int64(sizeString),
                  let updated = item["updated"] as? String else {
                continue
            }

            let formatter = ISO8601DateFormatter()
            let date = formatter.date(from: updated) ?? Date()

            let checksum = item["md5Hash"] as? String

            files.append(RemoteFile(path: name, size: size, lastModified: date, checksum: checksum))
        }

        return files
    }
}
