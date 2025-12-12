//
//  CloudProvider.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Cloud storage provider types
enum CloudProviderType: String, Codable, CaseIterable {
    case awsS3 = "AWS S3"
    case azureBlob = "Azure Blob"
    case googleCloud = "Google Cloud Storage"
    case iCloud = "iCloud Drive"
    case s3Compatible = "S3-Compatible"

    var icon: String {
        switch self {
        case .awsS3: return "cloud"
        case .azureBlob: return "cloud.fill"
        case .googleCloud: return "cloud.circle"
        case .iCloud: return "icloud"
        case .s3Compatible: return "server.rack"
        }
    }

    var requiresCredentials: Bool {
        switch self {
        case .iCloud: return false // Uses system credentials
        default: return true
        }
    }
}

/// Cloud provider configuration
struct CloudProviderConfig: Identifiable, Codable {
    let id: UUID
    let type: CloudProviderType
    let name: String
    let bucket: String // S3 bucket, Azure container, GCS bucket, iCloud folder
    let region: String?
    let endpoint: String? // For S3-compatible providers
    let folderPath: String // Path within bucket/container

    init(type: CloudProviderType, name: String, bucket: String,
         region: String? = nil, endpoint: String? = nil, folderPath: String = "dot-sync") {
        self.id = UUID()
        self.type = type
        self.name = name
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
        self.folderPath = folderPath
    }

    var displayName: String {
        "\(name) (\(type.rawValue))"
    }
}

/// Cloud provider credentials (stored in Keychain)
struct CloudCredentials: Codable {
    let accessKeyId: String?
    let secretAccessKey: String?
    let tenantId: String?
    let clientId: String?
    let clientSecret: String?
    let projectId: String?
    let serviceAccountKey: String?

    // AWS S3
    static func aws(accessKeyId: String, secretAccessKey: String) -> CloudCredentials {
        CloudCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey,
                        tenantId: nil, clientId: nil, clientSecret: nil,
                        projectId: nil, serviceAccountKey: nil)
    }

    // Azure
    static func azure(tenantId: String, clientId: String, clientSecret: String) -> CloudCredentials {
        CloudCredentials(accessKeyId: nil, secretAccessKey: nil,
                        tenantId: tenantId, clientId: clientId, clientSecret: clientSecret,
                        projectId: nil, serviceAccountKey: nil)
    }

    // Google Cloud
    static func gcp(projectId: String, serviceAccountKey: String) -> CloudCredentials {
        CloudCredentials(accessKeyId: nil, secretAccessKey: nil,
                        tenantId: nil, clientId: nil, clientSecret: nil,
                        projectId: projectId, serviceAccountKey: serviceAccountKey)
    }

    // iCloud (no credentials needed)
    static var iCloud: CloudCredentials {
        CloudCredentials(accessKeyId: nil, secretAccessKey: nil,
                        tenantId: nil, clientId: nil, clientSecret: nil,
                        projectId: nil, serviceAccountKey: nil)
    }
}
