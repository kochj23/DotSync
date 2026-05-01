//
//  CloudProviderTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
@testable import Dot_Sync

final class CloudProviderTests: XCTestCase {

    // MARK: - CloudProviderType

    func testAllProviderTypesHaveIcons() {
        for type in CloudProviderType.allCases {
            XCTAssertFalse(type.icon.isEmpty, "\(type.rawValue) should have an icon")
        }
    }

    func testICloudDoesNotRequireCredentials() {
        XCTAssertFalse(CloudProviderType.iCloud.requiresCredentials)
    }

    func testOtherProvidersRequireCredentials() {
        let nonICloud = CloudProviderType.allCases.filter { $0 != .iCloud }
        for type in nonICloud {
            XCTAssertTrue(type.requiresCredentials,
                          "\(type.rawValue) should require credentials")
        }
    }

    // MARK: - CloudProviderConfig

    func testCloudProviderConfigInit() {
        let config = CloudProviderConfig(
            type: .awsS3,
            name: "My S3",
            bucket: "my-dotfiles",
            region: "us-east-1"
        )

        XCTAssertEqual(config.type, .awsS3)
        XCTAssertEqual(config.name, "My S3")
        XCTAssertEqual(config.bucket, "my-dotfiles")
        XCTAssertEqual(config.region, "us-east-1")
        XCTAssertEqual(config.folderPath, "dot-sync")
    }

    func testCloudProviderConfigDisplayName() {
        let config = CloudProviderConfig(type: .azureBlob, name: "Work Azure", bucket: "container")
        XCTAssertEqual(config.displayName, "Work Azure (Azure Blob)")
    }

    func testCloudProviderConfigDefaultFolderPath() {
        let config = CloudProviderConfig(type: .iCloud, name: "iCloud", bucket: "DotSync")
        XCTAssertEqual(config.folderPath, "dot-sync")
    }

    func testCloudProviderConfigCustomFolderPath() {
        let config = CloudProviderConfig(
            type: .awsS3, name: "S3", bucket: "bucket",
            folderPath: "custom/path"
        )
        XCTAssertEqual(config.folderPath, "custom/path")
    }

    // MARK: - CloudCredentials Factory Methods

    func testAWSCredentials() {
        let creds = CloudCredentials.aws(accessKeyId: "AKIA123", secretAccessKey: "secret")
        XCTAssertEqual(creds.accessKeyId, "AKIA123")
        XCTAssertEqual(creds.secretAccessKey, "secret")
        XCTAssertNil(creds.tenantId)
        XCTAssertNil(creds.clientId)
    }

    func testAzureCredentials() {
        let creds = CloudCredentials.azure(tenantId: "tid", clientId: "cid", clientSecret: "secret")
        XCTAssertEqual(creds.tenantId, "tid")
        XCTAssertEqual(creds.clientId, "cid")
        XCTAssertEqual(creds.clientSecret, "secret")
        XCTAssertNil(creds.accessKeyId)
    }

    func testGCPCredentials() {
        let creds = CloudCredentials.gcp(projectId: "proj", serviceAccountKey: "{json}")
        XCTAssertEqual(creds.projectId, "proj")
        XCTAssertEqual(creds.serviceAccountKey, "{json}")
        XCTAssertNil(creds.accessKeyId)
    }

    func testNASCredentials() {
        let creds = CloudCredentials.nas(
            serverAddress: "192.168.1.100", sharePath: "/share",
            username: "admin", password: "pass"
        )
        XCTAssertEqual(creds.serverAddress, "192.168.1.100")
        XCTAssertEqual(creds.sharePath, "/share")
        XCTAssertEqual(creds.username, "admin")
        XCTAssertEqual(creds.password, "pass")
    }

    func testOneDriveCredentials() {
        let creds = CloudCredentials.oneDrive(
            clientId: "cid", clientSecret: "secret", refreshToken: "refresh"
        )
        XCTAssertEqual(creds.clientId, "cid")
        XCTAssertEqual(creds.refreshToken, "refresh")
    }

    func testGoogleDriveCredentials() {
        let creds = CloudCredentials.googleDrive(
            clientId: "cid", clientSecret: "secret", refreshToken: "refresh"
        )
        XCTAssertEqual(creds.clientId, "cid")
        XCTAssertEqual(creds.refreshToken, "refresh")
    }

    func testICloudCredentials() {
        let creds = CloudCredentials.iCloud
        XCTAssertNil(creds.accessKeyId)
        XCTAssertNil(creds.secretAccessKey)
        XCTAssertNil(creds.tenantId)
    }

    // MARK: - CloudStorageError

    func testCloudStorageErrorDescriptions() {
        let errors: [CloudStorageError] = [
            .notConfigured,
            .authenticationFailed,
            .networkError(NSError(domain: "test", code: 1)),
            .fileNotFound("/path"),
            .uploadFailed(NSError(domain: "test", code: 2)),
            .downloadFailed(NSError(domain: "test", code: 3)),
            .invalidCredentials
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription,
                            "Error should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - BaseCloudProvider

    func testStoragePath() {
        let config = CloudProviderConfig(type: .awsS3, name: "S3", bucket: "bucket")
        let provider = BaseCloudProvider(config: config, credentials: nil)

        let file = ConfigFile(
            path: "/Users/test/.zshrc",
            relativePath: ".zshrc",
            filename: ".zshrc",
            category: .shell,
            size: 100,
            lastModified: Date(),
            checksum: "abc",
            isSafeToSync: true,
            syncPriority: .critical
        )

        let path = provider.storagePath(for: file)
        XCTAssertEqual(path, "configs/shell/.zshrc")
    }

    func testStoragePathCategoryFormatting() {
        let config = CloudProviderConfig(type: .awsS3, name: "S3", bucket: "bucket")
        let provider = BaseCloudProvider(config: config, credentials: nil)

        let file = ConfigFile(
            path: "/Users/test/.gitconfig",
            relativePath: ".gitconfig",
            filename: ".gitconfig",
            category: .git,
            size: 100,
            lastModified: Date(),
            checksum: "abc",
            isSafeToSync: true,
            syncPriority: .critical
        )

        let path = provider.storagePath(for: file)
        XCTAssertTrue(path.hasPrefix("configs/"))
        XCTAssertTrue(path.contains("git"))
        XCTAssertTrue(path.hasSuffix(".gitconfig"))
    }

    // MARK: - RemoteFile

    func testRemoteFileCodable() throws {
        let original = RemoteFile(
            path: "configs/shell/.zshrc",
            size: 1024,
            lastModified: Date(),
            checksum: "abc123"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteFile.self, from: data)

        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.size, original.size)
        XCTAssertEqual(decoded.checksum, original.checksum)
    }

    // MARK: - Codable Conformance

    func testCloudProviderConfigCodable() throws {
        let original = CloudProviderConfig(
            type: .awsS3, name: "Test", bucket: "bucket",
            region: "us-west-2", endpoint: nil, folderPath: "dot-sync"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CloudProviderConfig.self, from: data)

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.bucket, original.bucket)
        XCTAssertEqual(decoded.region, original.region)
    }

    func testCloudCredentialsCodable() throws {
        let original = CloudCredentials.aws(accessKeyId: "key", secretAccessKey: "secret")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CloudCredentials.self, from: data)

        XCTAssertEqual(decoded.accessKeyId, original.accessKeyId)
        XCTAssertEqual(decoded.secretAccessKey, original.secretAccessKey)
    }
}
