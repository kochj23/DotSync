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
    ///
    /// NOTE: This is a simplified implementation. For production use, consider:
    /// 1. Use the official Google Cloud SDK
    /// 2. Implement proper RS256 JWT signing with a crypto library
    /// 3. Or have users provide a pre-generated access token
    ///
    /// For now, this implementation expects the serviceAccountKey to contain
    /// a pre-generated access token instead of the full service account JSON.
    private func getAccessToken() async throws -> String {
        guard let serviceAccountKey = credentials?.serviceAccountKey else {
            throw CloudStorageError.invalidCredentials
        }

        // Check if it looks like a JSON service account (starts with '{')
        if serviceAccountKey.trimmingCharacters(in: .whitespaces).starts(with: "{") {
            // Parse service account JSON to extract project info
            guard let jsonData = serviceAccountKey.data(using: .utf8),
                  let serviceAccount = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let clientEmail = serviceAccount["client_email"] as? String,
                  let privateKeyId = serviceAccount["private_key_id"] as? String else {
                throw CloudStorageError.invalidCredentials
            }

            // For now, return a helpful error message
            throw CloudStorageError.networkError(
                NSError(domain: "GCPProvider", code: 1001,
                       userInfo: [NSLocalizedDescriptionKey: """
                       Full service account authentication requires RS256 JWT signing.

                       Options:
                       1. Use 'gcloud auth application-default print-access-token' to get a token
                       2. Paste the access token as the 'Service Account Key' field
                       3. Or use the official Google Cloud SDK

                       Service Account: \(clientEmail)
                       Key ID: \(privateKeyId)
                       """])
            )
        }

        // Assume it's a pre-generated access token
        // Access tokens start with "ya29." or similar
        if !serviceAccountKey.isEmpty {
            return serviceAccountKey
        }

        throw CloudStorageError.invalidCredentials
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
