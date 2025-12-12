//
//  S3Provider.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation
import CryptoKit

/// AWS S3 storage provider
class S3Provider: BaseCloudProvider, CloudStorageProtocol {

    var isConfigured: Bool {
        credentials?.accessKeyId != nil && credentials?.secretAccessKey != nil
    }

    func upload(file: ConfigFile, data: Data) async throws {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let url = buildS3URL(for: storagePath)

        var request = createAuthenticatedRequest(url: url, method: "PUT")
        request.httpBody = data
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        // Add AWS Signature V4 headers
        try addAWSSignature(to: &request, payload: data)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.uploadFailed(NSError(domain: "S3Provider", code: -1))
        }
    }

    func download(file: ConfigFile) async throws -> Data {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let url = buildS3URL(for: storagePath)

        var request = createAuthenticatedRequest(url: url, method: "GET")
        try addAWSSignature(to: &request, payload: Data())

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudStorageError.downloadFailed(NSError(domain: "S3Provider", code: -1))
        }

        if httpResponse.statusCode == 404 {
            throw CloudStorageError.fileNotFound(storagePath)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.downloadFailed(NSError(domain: "S3Provider", code: httpResponse.statusCode))
        }

        return data
    }

    func listFiles() async throws -> [RemoteFile] {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        // List objects with prefix
        let prefix = "\(config.folderPath)/configs/"
        let url = buildS3URL(for: "", queryItems: [
            URLQueryItem(name: "list-type", value: "2"),
            URLQueryItem(name: "prefix", value: prefix)
        ])

        var request = createAuthenticatedRequest(url: url, method: "GET")
        try addAWSSignature(to: &request, payload: Data())

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CloudStorageError.networkError(NSError(domain: "S3Provider", code: -1))
        }

        // Parse XML response (simplified)
        return try parseS3ListResponse(data)
    }

    func delete(file: ConfigFile) async throws {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        let storagePath = storagePath(for: file)
        let url = buildS3URL(for: storagePath)

        var request = createAuthenticatedRequest(url: url, method: "DELETE")
        try addAWSSignature(to: &request, payload: Data())

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
            throw CloudStorageError.networkError(NSError(domain: "S3Provider", code: -1))
        }
    }

    func getMetadata(for file: ConfigFile) async throws -> RemoteFile? {
        let files = try await listFiles()
        let filename = file.filename
        return files.first { $0.path.contains(filename) }
    }

    func testConnection() async throws -> Bool {
        guard isConfigured else {
            throw CloudStorageError.notConfigured
        }

        // Try to list bucket contents
        _ = try await listFiles()
        return true
    }

    // MARK: - S3 Helpers

    private func buildS3URL(for path: String, queryItems: [URLQueryItem]? = nil) -> URL {
        let endpoint = config.endpoint ?? "https://s3.\(config.region ?? "us-east-1").amazonaws.com"
        var components = URLComponents(string: endpoint)!
        components.path = "/\(config.bucket)/\(path)"
        components.queryItems = queryItems
        return components.url!
    }

    private func addAWSSignature(to request: inout URLRequest, payload: Data) throws {
        guard let accessKey = credentials?.accessKeyId,
              let secretKey = credentials?.secretAccessKey else {
            throw CloudStorageError.invalidCredentials
        }

        // Use AWSHelper for full Signature V4 signing
        let region = config.region ?? "us-east-1"
        AWSHelper.signRequest(&request,
                            accessKey: accessKey,
                            secretKey: secretKey,
                            region: region,
                            service: "s3",
                            payload: payload)
    }

    private func parseS3ListResponse(_ data: Data) throws -> [RemoteFile] {
        // Simplified XML parsing
        // Production implementation would use XMLParser
        guard let xml = String(data: data, encoding: .utf8) else {
            return []
        }

        // Extract file information from XML (simplified)
        var files: [RemoteFile] = []

        // This is a placeholder - full implementation would parse XML properly
        let pattern = "<Key>(.*?)</Key>.*?<Size>(.*?)</Size>.*?<LastModified>(.*?)</LastModified>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))

            for match in matches {
                if match.numberOfRanges >= 4,
                   let keyRange = Range(match.range(at: 1), in: xml),
                   let sizeRange = Range(match.range(at: 2), in: xml),
                   let dateRange = Range(match.range(at: 3), in: xml) {

                    let path = String(xml[keyRange])
                    let size = Int64(String(xml[sizeRange])) ?? 0
                    let dateString = String(xml[dateRange])

                    let formatter = ISO8601DateFormatter()
                    let date = formatter.date(from: dateString) ?? Date()

                    files.append(RemoteFile(path: path, size: size, lastModified: date, checksum: nil))
                }
            }
        }

        return files
    }
}
