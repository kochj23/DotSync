//
//  AWSHelper.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//
//  AWS Signature V4 signing implementation
//

import Foundation
import CryptoKit

/// Helper for AWS Signature V4 authentication
class AWSHelper {

    /// Sign an AWS request with Signature V4
    static func signRequest(_ request: inout URLRequest,
                           accessKey: String,
                           secretKey: String,
                           region: String,
                           service: String = "s3",
                           payload: Data) {

        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoDate = dateFormatter.string(from: now)

        let shortDateFormatter = DateFormatter()
        shortDateFormatter.dateFormat = "yyyyMMdd"
        let shortDate = shortDateFormatter.string(from: now)

        // Add required headers
        request.setValue(isoDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue("aws4_request", forHTTPHeaderField: "X-Amz-Content-Sha256")

        // Calculate payload hash
        let payloadHash = SHA256.hash(data: payload)
        let payloadHashString = payloadHash.compactMap { String(format: "%02x", $0) }.joined()
        request.setValue(payloadHashString, forHTTPHeaderField: "X-Amz-Content-Sha256")

        // Build canonical request
        let method = request.httpMethod ?? "GET"
        let uri = request.url?.path ?? "/"
        let query = request.url?.query ?? ""

        var canonicalHeaders = ""
        var signedHeaders = ""

        if let allHeaders = request.allHTTPHeaderFields?.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
            for (key, value) in allHeaders {
                let lowerKey = key.lowercased()
                canonicalHeaders += "\(lowerKey):\(value.trimmingCharacters(in: .whitespaces))\n"
                signedHeaders += "\(lowerKey);"
            }
            signedHeaders = String(signedHeaders.dropLast())
        }

        let canonicalRequest = """
        \(method)
        \(uri)
        \(query)
        \(canonicalHeaders)
        \(signedHeaders)
        \(payloadHashString)
        """

        // Hash canonical request
        let canonicalHash = SHA256.hash(data: Data(canonicalRequest.utf8))
        let canonicalHashString = canonicalHash.compactMap { String(format: "%02x", $0) }.joined()

        // Create string to sign
        let credentialScope = "\(shortDate)/\(region)/\(service)/aws4_request"
        let stringToSign = """
        AWS4-HMAC-SHA256
        \(isoDate)
        \(credentialScope)
        \(canonicalHashString)
        """

        // Calculate signature
        let dateKey = hmacSHA256(key: Data("AWS4\(secretKey)".utf8), data: Data(shortDate.utf8))
        let regionKey = hmacSHA256(key: dateKey, data: Data(region.utf8))
        let serviceKey = hmacSHA256(key: regionKey, data: Data(service.utf8))
        let signingKey = hmacSHA256(key: serviceKey, data: Data("aws4_request".utf8))
        let signature = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8))
        let signatureString = signature.map { String(format: "%02x", $0) }.joined()

        // Build authorization header
        let authHeader = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signatureString)"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }

    /// HMAC-SHA256 helper
    private static func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(signature)
    }
}
