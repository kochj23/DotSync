//
//  SecurityScanner.swift
//  Dot Sync
//
//  Created by Jordan Koch on 12/11/25.
//

import Foundation

/// Scans files for credentials and sensitive data before syncing
class SecurityScanner {
    static let shared = SecurityScanner()

    // MARK: - Credential Patterns

    /// Regex patterns for detecting credentials
    private let credentialPatterns = [
        // API Keys
        "sk_live_[a-zA-Z0-9]{24,}",  // Stripe live keys
        "sk_test_[a-zA-Z0-9]{24,}",  // Stripe test keys
        "pk_live_[a-zA-Z0-9]{24,}",  // Stripe public keys
        "AKIA[0-9A-Z]{16}",          // AWS access keys
        "api[_-]?key[\"']?\\s*[:=]\\s*[\"'][a-zA-Z0-9]{20,}",  // Generic API keys

        // Tokens
        "Bearer\\s+[a-zA-Z0-9\\-._~+/]+=*",  // Bearer tokens
        "token[\"']?\\s*[:=]\\s*[\"'][a-zA-Z0-9]{20,}",  // Generic tokens
        "eyJ[a-zA-Z0-9_-]*\\.eyJ[a-zA-Z0-9_-]*\\.",  // JWT tokens

        // Passwords
        "password[\"']?\\s*[:=]\\s*[\"'][^\"'\\s]{8,}",  // Hardcoded passwords

        // SSH Keys (header detection)
        "BEGIN [A-Z]+ PRIVATE KEY",  // Private key headers
        "BEGIN RSA PRIVATE KEY",
        "BEGIN OPENSSH PRIVATE KEY",

        // Cloud Provider Keys
        "client_secret[\"']?\\s*[:=]\\s*[\"'][^\"']+",  // OAuth client secrets
        "service_account",  // GCP service account JSON
    ]

    // MARK: - Scanning

    /// Check if file contains credentials
    func containsCredentials(at url: URL) async -> Bool {
        // Skip directories
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }

        // Skip binary files
        guard isTextFile(url) else {
            return false
        }

        // Read file content
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }

        // Check file size (skip very large files)
        if content.count > 1_000_000 { // 1MB limit
            return false
        }

        // Scan for credential patterns
        for pattern in credentialPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil {
                return true
            }
        }

        return false
    }

    /// Scan file and return found credentials (for reporting)
    func scanForCredentials(at url: URL) async -> [String] {
        var foundPatterns: [String] = []

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        for pattern in credentialPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
                for match in matches {
                    if let range = Range(match.range, in: content) {
                        let matchedText = String(content[range])
                        foundPatterns.append("Pattern: \(pattern.prefix(30))... Found: \(matchedText.prefix(20))...")
                    }
                }
            }
        }

        return foundPatterns
    }

    /// Check if file is text-based (safe to scan)
    private func isTextFile(_ url: URL) -> Bool {
        let textExtensions = ["", "txt", "md", "json", "xml", "plist", "yml", "yaml",
                             "conf", "config", "cfg", "ini", "sh", "bash", "zsh",
                             "vim", "rc", "profile"]

        let ext = url.pathExtension.lowercased()
        return textExtensions.contains(ext) || url.lastPathComponent.hasPrefix(".")
    }

    // MARK: - Sanitization

    /// Sanitize a config file by removing sensitive data
    func sanitize(content: String) -> String {
        var sanitized = content

        // Remove credential helper sections from .gitconfig
        sanitized = sanitized.replacingOccurrences(
            of: "\\[credential.*?\\].*?helper.*?=.*?\\n",
            with: "",
            options: .regularExpression
        )

        // Remove auth sections from Docker config
        sanitized = sanitized.replacingOccurrences(
            of: "\"auth\"\\s*:\\s*\"[^\"]+\"",
            with: "\"auth\": \"REMOVED\"",
            options: .regularExpression
        )

        // Remove AWS credentials (keep config)
        sanitized = sanitized.replacingOccurrences(
            of: "aws_access_key_id\\s*=.*?\\n",
            with: "",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(
            of: "aws_secret_access_key\\s*=.*?\\n",
            with: "",
            options: .regularExpression
        )

        return sanitized
    }
}
