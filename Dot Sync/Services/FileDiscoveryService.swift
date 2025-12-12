//
//  FileDiscoveryService.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation
import CryptoKit

/// Service for discovering and categorizing configuration files
class FileDiscoveryService: ObservableObject {
    static let shared = FileDiscoveryService()

    @Published var discoveredFiles: [ConfigFile] = []
    @Published var isScanning = false

    private let fileManager = FileManager.default
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    // MARK: - File Patterns

    /// Config file patterns by category
    private let filePatterns: [ConfigCategory: [String]] = [
        .shell: [".zshrc", ".bashrc", ".bash_profile", ".profile", ".zprofile",
                ".p10k.zsh", ".fzf.bash", ".fzf.zsh"],
        .git: [".gitconfig", ".gitignore_global"],
        .editor: [".vimrc", ".vim/", ".emacs", ".emacs.d/", ".ideavimrc",
                 ".config/Code/User/settings.json", ".vscode/settings.json"],
        .cloud: [".aws/config", ".azure/config", ".config/gcloud/"],
        .docker: [".docker/config.json", ".dockerignore"],
        .language: [".npmrc", ".gemrc", ".pypirc", ".cargo/config"],
        .claude: [".claude/CLAUDE.md", ".claude/settings.json", ".claude/preferences.md"],
        .documentation: [".aws_cheatsheet.md", ".azure_cheatsheet.md", ".gcp_cheatsheet.md",
                        ".zsh_cheatsheet.md", ".omz_plugin_recommendations.md"]
    ]

    /// Application preference files (in ~/Library/Preferences/)
    private let appPreferences: [ConfigCategory: [String]] = [
        .shell: [
            "com.apple.Terminal.plist",           // Terminal profiles and settings
            "com.googlecode.iterm2.plist"         // iTerm2 (if installed)
        ],
        .editor: [
            "com.microsoft.VSCode.plist",         // VS Code
            "com.sublimetext.3.plist"             // Sublime Text (if installed)
        ]
    ]

    /// Files/patterns to never sync (security/privacy)
    private let excludePatterns = [
        // SSH keys
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
        // Credentials
        "credentials", "password", "secret", "token",
        // History files
        "_history", ".lesshst", ".viminfo",
        // Cache
        "cache/", "Cache/",
        // System files
        ".DS_Store", ".CFUserTextEncoding",
        // Session data
        "_sessions/", ".claude/history.jsonl",
        // Temporary
        ".swp", ".tmp", ".temp"
    ]

    // MARK: - Discovery

    /// Scan home directory for config files
    func scanHomeDirectory() async {
        await MainActor.run {
            self.isScanning = true
        }

        var foundFiles: [ConfigFile] = []

        // Scan for individual files in home directory
        for (category, patterns) in filePatterns {
            for pattern in patterns {
                let fullPath = homeDirectory.appendingPathComponent(pattern)

                if fileManager.fileExists(atPath: fullPath.path) {
                    if let configFile = await createConfigFile(at: fullPath, category: category) {
                        foundFiles.append(configFile)
                    }
                }
            }
        }

        // Scan for application preferences in ~/Library/Preferences/
        let preferencesDir = homeDirectory.appendingPathComponent("Library/Preferences")
        for (category, prefFiles) in appPreferences {
            for prefFile in prefFiles {
                let fullPath = preferencesDir.appendingPathComponent(prefFile)

                if fileManager.fileExists(atPath: fullPath.path) {
                    if let configFile = await createConfigFile(at: fullPath, category: category) {
                        foundFiles.append(configFile)
                    }
                }
            }
        }

        // Sort by priority then category
        foundFiles.sort { lhs, rhs in
            if lhs.syncPriority != rhs.syncPriority {
                return lhs.syncPriority < rhs.syncPriority
            }
            return lhs.category.rawValue < rhs.category.rawValue
        }

        await MainActor.run {
            self.discoveredFiles = foundFiles
            self.isScanning = false
        }
    }

    /// Create ConfigFile from path
    private func createConfigFile(at url: URL, category: ConfigCategory) async -> ConfigFile? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }

        let isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory
        let size = attributes[.size] as? Int64 ?? 0
        let lastModified = attributes[.modificationDate] as? Date ?? Date()

        // Calculate checksum for files (not directories)
        let checksum = isDirectory ? "" : await calculateChecksum(at: url)

        // Determine if safe to sync
        let isSafeToSync = await isSafeFile(url)

        // Determine priority
        let priority = determinePriority(for: url, category: category)

        // Get relative path
        let relativePath = url.path.replacingOccurrences(of: homeDirectory.path + "/", with: "")

        return ConfigFile(
            path: url.path,
            relativePath: relativePath,
            filename: url.lastPathComponent,
            category: category,
            size: size,
            lastModified: lastModified,
            checksum: checksum,
            isSafeToSync: isSafeToSync,
            syncPriority: priority,
            isDirectory: isDirectory
        )
    }

    /// Calculate SHA-256 checksum
    private func calculateChecksum(at url: URL) async -> String {
        guard let data = try? Data(contentsOf: url) else {
            return ""
        }

        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Check if file is safe to sync
    private func isSafeFile(_ url: URL) async -> Bool {
        let filename = url.lastPathComponent
        let path = url.path

        // Check exclude patterns
        for pattern in excludePatterns {
            if filename.contains(pattern) || path.contains(pattern) {
                return false
            }
        }

        // Additional security check - scan content for credentials
        if await SecurityScanner.shared.containsCredentials(at: url) {
            return false
        }

        return true
    }

    /// Determine sync priority based on file category and importance
    private func determinePriority(for url: URL, category: ConfigCategory) -> SyncPriority {
        let filename = url.lastPathComponent

        // Critical files
        if [".zshrc", ".bashrc", ".bash_profile", ".gitconfig", ".vimrc"].contains(filename) {
            return .critical
        }

        // Terminal profiles are high priority (they're a pain to recreate!)
        if filename.contains("Terminal.plist") || filename.contains("iterm2.plist") {
            return .high
        }

        // High priority by category
        if [.shell, .git, .claude].contains(category) {
            return .high
        }

        // Medium priority
        if [.editor, .cloud, .docker].contains(category) {
            return .medium
        }

        // Low priority (documentation, custom)
        return .low
    }

    // MARK: - Utility

    /// Get home directory
    var homePath: String {
        homeDirectory.path
    }

    /// Get discovered files by category
    func files(for category: ConfigCategory) -> [ConfigFile] {
        discoveredFiles.filter { $0.category == category }
    }

    /// Get discovered files by priority
    func files(for priority: SyncPriority) -> [ConfigFile] {
        discoveredFiles.filter { $0.syncPriority == priority }
    }
}
