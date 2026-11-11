//
//  AppAI.swift
//  Dot Sync
//
//  The app's one AI object (NovaAIKit 1.0.0). Settings persist in UserDefaults (no secrets); API keys live only in
//  the Keychain under com.jkoch.dotsync.<backend>. Every AI feature in Dot Sync goes through `AppAI.run`, which
//  never throws: AI off, every backend down, or a reply the validator rejects all yield the feature's built-in
//  (rule-based) result.
//  Author: Jordan Koch
//

import Foundation
import NovaAIKit

@MainActor
enum AppAI {
    static let appID = "dotsync"
    static let appName = "Dot Sync"

    /// Old Keychain service used by the pre-NovaAIKit AI backend code (Dot Sync 1.2 and earlier).
    static let legacyKeychainService = "com.jordankoch.DotSync"
    /// Accounts that held the OpenAI key under the old service (`openAIAPIKey`, and the old defaults-key names).
    static let legacyOpenAIAccounts = ["openAIAPIKey"] + NovaAILegacySettings.openAIKeyKeys
    /// Accounts of the removed Google/Azure/AWS/IBM backends under the old service (deleted, never read out).
    static let legacyObsoleteAccounts = NovaAIKeys.obsoleteLegacyAccounts + [
        "AIBackend_GoogleCloud_Key", "AIBackend_Azure_Key", "AIBackend_Azure_Endpoint", "AIBackend_AWS_AccessKey",
        "AIBackend_AWS_SecretKey", "AIBackend_IBM_Key", "AIBackend_IBM_URL",
    ]
    static let footer = "When AI is off or unreachable, Dot Sync uses its built-in rules: regex secret scanning, " +
        "line-count health checks, three-way merge, keyword search and static best practices."

    static let shared: NovaAI = {
        let ai = NovaAI(configuration: configuration)
        migrateLegacy(ai)
        return ai
    }()

    static var configuration: NovaAIConfiguration {
        NovaAIConfiguration(appID: appID, appName: appName)
    }

    /// One AI feature call: ask, validate with `parse` (throw `NovaAIValidationError` to reject), else `fallback`.
    static func run<T: Sendable>(_ ai: NovaAI? = nil,
                                 prompt: String, system: String, temperature: Double, maxTokens: Int,
                                 parse: @escaping @Sendable (String) throws -> T,
                                 fallback: @escaping @Sendable () -> T) async -> NovaAIResult<T> {
        let ai = ai ?? shared
        let request = NovaAIRequest(prompt: prompt, system: system, temperature: temperature, maxTokens: maxTokens)
        return await ai.generate(request, validate: parse, fallback: fallback)
    }
}

extension AppAI {
    /// Once, at first launch after the upgrade: old AI settings (backend, Ollama model, on/off) → NovaAIKit
    /// settings, any plaintext OpenAI key in UserDefaults → Keychain, old Keychain items → com.jkoch.dotsync.*, and
    /// the removed cloud backends' secrets deleted. (Old TinyLLM/TinyChat URLs defaulted to localhost:8000, the
    /// same as NovaAIKit's defaults.) Idempotent.
    static func migrateLegacy(_ ai: NovaAI, defaults: UserDefaults = .standard) {
        ai.migrateFromLegacyAIBackendManager(defaults: defaults)
        for account in legacyOpenAIAccounts {
            ai.migrateLegacyKey(service: legacyKeychainService, account: account, to: .openAI, deleteLegacy: true)
        }
        ai.keys.deleteObsoleteLegacyItems(service: legacyKeychainService, accounts: legacyObsoleteAccounts)
    }
}

/// Parsing helpers shared by the AI services' validators.
enum AIReply {
    /// Value after `KEY:` on a line (case-insensitive), or nil.
    static func field(_ key: String, in line: String) -> String? {
        guard line.uppercased().hasPrefix(key.uppercased() + ":") else { return nil }
        return String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
    }

    /// Text between two marker lines, trimmed, or nil.
    static func block(_ text: String, start: String, end: String) -> String? {
        guard let s = text.range(of: start), let e = text.range(of: end, range: s.upperBound..<text.endIndex) else { return nil }
        return String(text[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lines with list markers / leading spaces stripped.
    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { line in
            var l = line.trimmingCharacters(in: .whitespaces)
            while l.hasPrefix("- ") || l.hasPrefix("* ") { l = String(l.dropFirst(2)) }
            return l
        }
    }
}
