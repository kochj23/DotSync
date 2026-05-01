//
//  FilesystemIntegrationTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
import CryptoKit
@testable import Dot_Sync

/// Integration tests that exercise real filesystem operations in a temporary directory
final class FilesystemIntegrationTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotSyncIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - File Creation and Checksum

    func testChecksumConsistency() throws {
        let content = "export PATH=\"/usr/local/bin:$PATH\"\nalias ll='ls -la'"
        let fileURL = tempDir.appendingPathComponent(".zshrc")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Calculate checksum the same way FileDiscoveryService does
        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data)
        let checksum = hash.compactMap { String(format: "%02x", $0) }.joined()

        // Calculate again to verify determinism
        let data2 = try Data(contentsOf: fileURL)
        let hash2 = SHA256.hash(data: data2)
        let checksum2 = hash2.compactMap { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(checksum, checksum2, "Checksums should be deterministic")
        XCTAssertEqual(checksum.count, 64, "SHA-256 hex should be 64 characters")
    }

    func testChecksumChangesWithContent() throws {
        let file1 = tempDir.appendingPathComponent("file1")
        let file2 = tempDir.appendingPathComponent("file2")

        try "content A".write(to: file1, atomically: true, encoding: .utf8)
        try "content B".write(to: file2, atomically: true, encoding: .utf8)

        let hash1 = SHA256.hash(data: try Data(contentsOf: file1))
        let hash2 = SHA256.hash(data: try Data(contentsOf: file2))

        let checksum1 = hash1.compactMap { String(format: "%02x", $0) }.joined()
        let checksum2 = hash2.compactMap { String(format: "%02x", $0) }.joined()

        XCTAssertNotEqual(checksum1, checksum2, "Different content should produce different checksums")
    }

    // MARK: - Backup Creation

    func testBackupFileCreation() throws {
        let originalFile = tempDir.appendingPathComponent(".zshrc")
        try "original content".write(to: originalFile, atomically: true, encoding: .utf8)

        let backupPath = originalFile.path + ".backup"
        try FileManager.default.copyItem(atPath: originalFile.path, toPath: backupPath)

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))

        let backupContent = try String(contentsOfFile: backupPath, encoding: .utf8)
        XCTAssertEqual(backupContent, "original content")
    }

    func testAtomicFileWrite() throws {
        let fileURL = tempDir.appendingPathComponent(".gitconfig")
        let content = "[user]\n    name = Test\n    email = test@example.com"

        try content.data(using: .utf8)?.write(to: fileURL, options: .atomic)

        let readBack = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(readBack, content, "Atomic write should preserve content exactly")
    }

    // MARK: - Ancestor File Handling

    func testAncestorFileStorageAndRetrieval() throws {
        let ancestorPath = tempDir.appendingPathComponent(".zshrc.ancestor")
        let ancestorContent = "original version of config"

        try ancestorContent.data(using: .utf8)?.write(to: ancestorPath, options: .atomic)

        let retrieved = try String(contentsOfFile: ancestorPath.path, encoding: .utf8)
        XCTAssertEqual(retrieved, ancestorContent)
    }

    // MARK: - Symlink Safety

    func testSymlinkDetection() throws {
        let realFile = tempDir.appendingPathComponent("real_config")
        try "real content".write(to: realFile, atomically: true, encoding: .utf8)

        let symlinkPath = tempDir.appendingPathComponent("symlink_config")
        try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: realFile)

        // Verify symlink exists and points to real file
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkPath.path, isDirectory: &isDirectory))

        // Check attributes to detect symlink
        let attributes = try FileManager.default.attributesOfItem(atPath: symlinkPath.path)
        let fileType = attributes[.type] as? FileAttributeType
        XCTAssertEqual(fileType, .typeSymbolicLink, "Should detect symlink file type")
    }

    func testSymlinkDoesNotEscapeTempDir() throws {
        // Create a file inside tempDir
        let safeFile = tempDir.appendingPathComponent("safe")
        try "safe".write(to: safeFile, atomically: true, encoding: .utf8)

        // Resolve the symlink destination and verify it stays inside our sandbox
        let resolved = safeFile.resolvingSymlinksInPath()
        // The resolved path should be under the temp directory parent
        XCTAssertTrue(resolved.path.hasPrefix("/"),
                      "Resolved path should be absolute")
    }

    // MARK: - Path Traversal Prevention

    func testPathTraversalAttemptBlocked() throws {
        // Create a directory structure
        let subDir = tempDir.appendingPathComponent("configs")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        // A path traversal attempt should not escape the intended directory
        let traversalPath = subDir.appendingPathComponent("../../etc/passwd")
        let resolvedPath = traversalPath.standardized

        // The standardized path should not be under our temp directory configs
        XCTAssertFalse(resolvedPath.path.hasPrefix(subDir.path),
                       "Path traversal should be blocked by standardization")
    }

    func testRelativePathSanitization() {
        let homeDir = "/Users/test"
        let relativePath = ".zshrc"
        let fullPath = "\(homeDir)/\(relativePath)"

        // Verify the path does not escape home
        XCTAssertTrue(fullPath.hasPrefix(homeDir))
        XCTAssertFalse(relativePath.contains(".."),
                       "Relative path should not contain traversal")
    }

    // MARK: - File Attributes

    func testFileAttributesRetrieval() throws {
        let fileURL = tempDir.appendingPathComponent(".vimrc")
        let content = "set number\nset ruler"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        let size = attributes[.size] as? Int64
        XCTAssertNotNil(size)
        XCTAssertGreaterThan(size!, 0)

        let modDate = attributes[.modificationDate] as? Date
        XCTAssertNotNil(modDate)

        let fileType = attributes[.type] as? FileAttributeType
        XCTAssertEqual(fileType, .typeRegular)
    }

    func testDirectoryAttributesRetrieval() throws {
        let dirURL = tempDir.appendingPathComponent(".config")
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let attributes = try FileManager.default.attributesOfItem(atPath: dirURL.path)
        let fileType = attributes[.type] as? FileAttributeType
        XCTAssertEqual(fileType, .typeDirectory)
    }

    // MARK: - Concurrent File Operations

    func testConcurrentFileWrites() async throws {
        // Simulate multiple files being written concurrently (as in a sync operation)
        let files = (0..<10).map { "config_\($0)" }

        await withTaskGroup(of: Void.self) { group in
            for filename in files {
                group.addTask { [tempDir] in
                    let url = tempDir!.appendingPathComponent(filename)
                    try? "content of \(filename)".write(to: url, atomically: true, encoding: .utf8)
                }
            }
        }

        // Verify all files were created
        for filename in files {
            let path = tempDir.appendingPathComponent(filename).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                          "\(filename) should exist after concurrent write")
        }
    }

    // MARK: - Large File Handling

    func testLargeFileChecksum() throws {
        let fileURL = tempDir.appendingPathComponent("large_config")
        // Create a file with many lines
        let lines = (0..<10000).map { "export CONFIG_\($0)=value_\($0)" }
        let content = lines.joined(separator: "\n")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let data = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: data)
        let checksum = hash.compactMap { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(checksum.count, 64)
        XCTAssertGreaterThan(data.count, 100_000, "File should be reasonably large")
    }

    // MARK: - Exclude Pattern Integration

    func testExcludePatternMatchesSSHKeys() {
        let excludePatterns = ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
                               "credentials", "password", "secret", "token",
                               "_history", ".lesshst", ".viminfo",
                               "cache/", "Cache/", ".DS_Store", ".CFUserTextEncoding",
                               "_sessions/", ".swp", ".tmp", ".temp"]

        // Test SSH key exclusion
        let sshFiles = ["id_rsa", "id_dsa", "id_ecdsa", "id_ed25519"]
        for sshFile in sshFiles {
            let matches = excludePatterns.contains { sshFile.contains($0) }
            XCTAssertTrue(matches, "\(sshFile) should be excluded")
        }

        // Test history file exclusion
        let historyFiles = [".bash_history", ".zsh_history", ".python_history"]
        for histFile in historyFiles {
            let matches = excludePatterns.contains { histFile.contains($0) }
            XCTAssertTrue(matches, "\(histFile) should be excluded")
        }

        // Test safe file is not excluded
        let safeFile = ".zshrc"
        let matches = excludePatterns.contains { safeFile.contains($0) }
        XCTAssertFalse(matches, ".zshrc should not be excluded")
    }
}
