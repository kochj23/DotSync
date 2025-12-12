//
//  AzureBlobProvider.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation
import CryptoKit

/// Azure Blob Storage provider
class AzureBlobProvider: BaseCloudProvider, CloudStorageProtocol {

    var isConfigured: Bool {
        credentials?.clientId != nil && credentials?.clientSecret != nil && credentials?.tenantId != nil
    }

    func upload(file: ConfigFile, data: Data) async throws {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        // Get access token
        let token = try await getAccessToken()

        let storagePath = storagePath(for: file)
        let url = buildAzureURL(for: storagePath)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        request.setValue("2021-08-06", forHTTPHeaderField: "x-ms-version")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.uploadFailed(NSError(domain: "AzureBlobProvider", code: -1))
        }
    }

    func download(file: ConfigFile) async throws -> Data {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let storagePath = storagePath(for: file)
        let url = buildAzureURL(for: storagePath)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2021-08-06", forHTTPHeaderField: "x-ms-version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudStorageError.downloadFailed(NSError(domain: "AzureBlobProvider", code: -1))
        }

        if httpResponse.statusCode == 404 {
            throw CloudStorageError.fileNotFound(storagePath)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.downloadFailed(NSError(domain: "AzureBlobProvider", code: httpResponse.statusCode))
        }

        return data
    }

    func listFiles() async throws -> [RemoteFile] {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let prefix = "\(config.folderPath)/configs/"

        var components = URLComponents(string: "https://\(config.bucket).blob.core.windows.net/\(config.bucket)")!
        components.queryItems = [
            URLQueryItem(name: "restype", value: "container"),
            URLQueryItem(name: "comp", value: "list"),
            URLQueryItem(name: "prefix", value: prefix)
        ]

        guard let url = components.url else {
            throw CloudStorageError.networkError(NSError(domain: "AzureBlobProvider", code: -1))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2021-08-06", forHTTPHeaderField: "x-ms-version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.networkError(NSError(domain: "AzureBlobProvider", code: -1))
        }

        return try parseAzureListResponse(data)
    }

    func delete(file: ConfigFile) async throws {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let token = try await getAccessToken()
        let storagePath = storagePath(for: file)
        let url = buildAzureURL(for: storagePath)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2021-08-06", forHTTPHeaderField: "x-ms-version")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            throw CloudStorageError.networkError(NSError(domain: "AzureBlobProvider", code: -1))
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

    // MARK: - Azure Helpers

    private func buildAzureURL(for path: String) -> URL {
        // https://{account}.blob.core.windows.net/{container}/{blob}
        let urlString = "https://\(config.bucket).blob.core.windows.net/\(config.bucket)/\(path)"
        return URL(string: urlString)!
    }

    /// Get OAuth access token from Azure AD
    private func getAccessToken() async throws -> String {
        guard let clientId = credentials?.clientId,
              let clientSecret = credentials?.clientSecret,
              let tenantId = credentials?.tenantId else {
            throw CloudStorageError.invalidCredentials
        }

        let tokenURL = URL(string: "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = """
        grant_type=client_credentials&\
        client_id=\(clientId)&\
        client_secret=\(clientSecret)&\
        scope=https://storage.azure.com/.default
        """
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.authenticationFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw CloudStorageError.authenticationFailed
        }

        return token
    }

    private func parseAzureListResponse(_ data: Data) throws -> [RemoteFile] {
        // Parse Azure XML response
        guard let xml = String(data: data, encoding: .utf8) else {
            return []
        }

        var files: [RemoteFile] = []

        let pattern = "<Name>(.*?)</Name>.*?<Content-Length>(.*?)</Content-Length>.*?<Last-Modified>(.*?)</Last-Modified>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

            for match in matches {
                if match.numberOfRanges >= 4,
                   let nameRange = Range(match.range(at: 1), in: xml),
                   let sizeRange = Range(match.range(at: 2), in: xml),
                   let dateRange = Range(match.range(at: 3), in: xml) {

                    let path = String(xml[nameRange])
                    let size = Int64(String(xml[sizeRange])) ?? 0
                    let dateString = String(xml[dateRange])

                    let formatter = DateFormatter()
                    formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss z"
                    let date = formatter.date(from: dateString) ?? Date()

                    files.append(RemoteFile(path: path, size: size, lastModified: date, checksum: nil))
                }
            }
        }

        return files
    }
}
