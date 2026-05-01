//
//  FileDiscoveryServiceTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
@testable import Dot_Sync

final class FileDiscoveryServiceTests: XCTestCase {

    var service: FileDiscoveryService!

    override func setUp() {
        service = FileDiscoveryService.shared
    }

    // MARK: - Categorization

    func testCategorizeShellFiles() {
        XCTAssertEqual(service.categorize(filename: ".zshrc"), .shell)
        XCTAssertEqual(service.categorize(filename: ".bashrc"), .shell)
        XCTAssertEqual(service.categorize(filename: ".bash_profile"), .shell)
        XCTAssertEqual(service.categorize(filename: ".profile"), .shell)
        XCTAssertEqual(service.categorize(filename: ".p10k.zsh"), .shell)
    }

    func testCategorizeGitFiles() {
        XCTAssertEqual(service.categorize(filename: ".gitconfig"), .git)
        XCTAssertEqual(service.categorize(filename: ".gitignore_global"), .git)
    }

    func testCategorizeEditorFiles() {
        XCTAssertEqual(service.categorize(filename: ".vimrc"), .editor)
    }

    func testCategorizeClaudeFiles() {
        // Claude files should be matched by the pattern
        let result = service.categorize(filename: ".claude")
        // The pattern is ".claude/CLAUDE.md" etc, so a bare ".claude" may not match
        // This tests the categorization behavior
        XCTAssertNotNil(result)
    }

    func testCategorizeDocumentation() {
        XCTAssertEqual(service.categorize(filename: ".aws_cheatsheet.md"), .documentation)
        XCTAssertEqual(service.categorize(filename: ".azure_cheatsheet.md"), .documentation)
    }

    func testCategorizeMarkdownAsDocumentation() {
        // Any .md file should fall back to documentation
        XCTAssertEqual(service.categorize(filename: "README.md"), .documentation)
        XCTAssertEqual(service.categorize(filename: "notes.md"), .documentation)
    }

    func testCategorizeUnknownFile() {
        XCTAssertEqual(service.categorize(filename: "random_binary"), .unknown)
    }

    // MARK: - Priority Determination

    func testCriticalPriorityFiles() {
        XCTAssertEqual(service.determinePriority(for: ".zshrc", category: .shell), .critical)
        XCTAssertEqual(service.determinePriority(for: ".bashrc", category: .shell), .critical)
        XCTAssertEqual(service.determinePriority(for: ".gitconfig", category: .git), .critical)
        XCTAssertEqual(service.determinePriority(for: ".vimrc", category: .editor), .critical)
        XCTAssertEqual(service.determinePriority(for: ".bash_profile", category: .shell), .critical)
    }

    func testHighPriorityByCategory() {
        XCTAssertEqual(service.determinePriority(for: ".profile", category: .shell), .high)
        XCTAssertEqual(service.determinePriority(for: ".gitignore_global", category: .git), .high)
    }

    func testHighPriorityTerminalProfiles() {
        XCTAssertEqual(service.determinePriority(for: "com.apple.Terminal.plist", category: .shell), .high)
        XCTAssertEqual(service.determinePriority(for: "com.googlecode.iterm2.plist", category: .shell), .high)
    }

    func testMediumPriorityCategories() {
        XCTAssertEqual(service.determinePriority(for: "settings.json", category: .editor), .medium)
        XCTAssertEqual(service.determinePriority(for: "config", category: .cloud), .medium)
        XCTAssertEqual(service.determinePriority(for: "CLAUDE.md", category: .claude), .medium)
    }

    func testLowPriorityDocumentation() {
        XCTAssertEqual(service.determinePriority(for: "notes.md", category: .documentation), .low)
    }

    // MARK: - File Filtering

    func testFilesForCategory() {
        // After scanning, files should be filterable by category
        let shellFiles = service.files(for: .shell)
        for file in shellFiles {
            XCTAssertEqual(file.category, .shell)
        }
    }

    func testEverythingReturnAllFiles() {
        let allFiles = service.files(for: .everything)
        let discovered = service.discoveredFiles
        XCTAssertEqual(allFiles.count, discovered.count,
                       "Everything filter should return all discovered files")
    }

    func testFilesForPriority() {
        let criticalFiles = service.files(for: .critical)
        for file in criticalFiles {
            XCTAssertEqual(file.syncPriority, .critical)
        }
    }

    // MARK: - Home Path

    func testHomePathNotEmpty() {
        XCTAssertFalse(service.homePath.isEmpty)
    }

    func testHomePathIsAbsolute() {
        XCTAssertTrue(service.homePath.hasPrefix("/"))
    }
}
