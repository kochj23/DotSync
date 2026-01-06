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
    case nas = "NAS (SMB/NFS)"
    case oneDrive = "OneDrive"
    case googleDrive = "Google Drive"

    var icon: String {
        switch self {
        case .awsS3: return "cloud"
        case .azureBlob: return "cloud.fill"
        case .googleCloud: return "cloud.circle"
        case .iCloud: return "icloud"
        case .s3Compatible: return "server.rack"
        case .nas: return "externaldrive.connected.to.line.below"
        case .oneDrive: return "arrow.up.doc.on.clipboard"
        case .googleDrive: return "arrow.down.doc"
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
    let username: String?
    let password: String?
    let serverAddress: String?
    let sharePath: String?
    let refreshToken: String?

    // AWS S3
    static func aws(accessKeyId: String, secretAccessKey: String) -> CloudCredentials {
        CloudCredentials(accessKeyId: accessKeyId, secretAccessKey: secretAccessKey,
                        tenantId: nil, clientId: nil, clientSecret: nil,
                        projectId: nil, serviceAccountKey: nil,
                        username: nil, password: nil, serverAddress: nil, sharePath: nil, refreshToken: nil)
    }

    // Azure
    static func azure(tenantId: String, clientId: String, clientSecret: String) -> CloudCredentials {
        CloudCredentials(accessKeyId: nil, secretAccessKey: nil,
                        tenantId: tenantId, clientId: clientId, clientSecret: clientSecret,
                        projectId: nil, serviceAccountKey: nil,
                        username: nil, password: nil, serverAddress: nil, sharePath: nil, refreshToken: nil)
    }

    // Google Cloud
    static func gcp(projectId: String, serviceAccountKey: String) -> CloudCredentials {
        CloudCredentials(accessKeyId: nil, secretAccessKey: nil,
                        tenantId: nil, clientId: nil, clientSecret: nil,
                        projectId: projectId, serviceAccountKey: serviceAccountKey,
                        username: nil, password: nil, serverAddress: nil, sharePath: nil, refreshToken: nil)
    }

    // NAS (SMB/NFS)
    static func nas(serverAddress: String, sharePath: String, username: String, password: String) -> CloudCredentials {
        CloudCredentials(accessKeyId: nil, secretAccessKey: nil,
                        tenantId: nil, clientId: nil, clientSecret: nil,
                        projectId: nil, serviceAccountKey: nil,
                        username: username, password: password, serverAddress: serverAddress, sharePath: sharePath, refreshToken: nil)
    }

    // OneDrive
    static func oneDrive(clientId: String, clientSecret: String, refreshToken: String) -> CloudCredentials {
        CloudCredentials(accessKeyId: nil, secretAccessKey: nil,
                        tenantId: nil, clientId: clientId, clientSecret: clientSecret,
                        projectId: nil, serviceAccountKey: nil,
                        username: nil, password: nil, serverAddress: nil, sharePath: nil, refreshToken: refreshToken)
    }

    // Google Drive
    static func googleDrive(clientId: String, clientSecret: String, refreshToken: String) -> CloudCredentials {
        CloudCredentials(accessKeyId: nil, secretAccessKey: nil,
                        tenantId: nil, clientId: clientId, clientSecret: clientSecret,
                        projectId: nil, serviceAccountKey: nil,
                        username: nil, password: nil, serverAddress: nil, sharePath: nil, refreshToken: refreshToken)
    }

    // iCloud (no credentials needed)
    static var iCloud: CloudCredentials {
        CloudCredentials(accessKeyId: nil, secretAccessKey: nil,
                        tenantId: nil, clientId: nil, clientSecret: nil,
                        projectId: nil, serviceAccountKey: nil,
                        username: nil, password: nil, serverAddress: nil, sharePath: nil, refreshToken: nil)
    }
}
