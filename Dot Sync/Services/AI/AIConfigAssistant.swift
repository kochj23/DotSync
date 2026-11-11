//
//  AIConfigAssistant.swift
//  Dot Sync
//
//  AI-powered configuration assistant for automation and intelligence
//  Features: Natural Language Search, Config Generation, Migration Assistant, Sync Priority Learning
//  Author: Jordan Koch
//

import Foundation
import NovaAIKit

/// AI-powered configuration assistant
@MainActor
class AIConfigAssistant: ObservableObject {
    static let shared = AIConfigAssistant()

    @Published var isProcessing = false
    @Published var searchResults: [SearchResult] = []
    @Published var usageHistory: [ConfigUsageRecord] = []
    /// Where the last result came from ("AI · Ollama (model)" / "Built-in").
    @Published var lastSource: NovaAISource?

    private let ai: NovaAI
    private let userDefaults: UserDefaults

    init(ai: NovaAI? = nil, userDefaults: UserDefaults = .standard) {
        self.ai = ai ?? AppAI.shared
        self.userDefaults = userDefaults
    }

    // MARK: - Data Models

    struct SearchResult: Identifiable {
        let id = UUID()
        let filename: String
        let filepath: String
        let matchType: MatchType
        let matchedContent: String
        let lineNumber: Int?
        let relevanceScore: Double

        enum MatchType: String {
            case exactMatch = "Exact Match"
            case semanticMatch = "Semantic Match"
            case contextMatch = "Context Match"
        }
    }

    struct ConfigGenerationResult: Identifiable {
        let id = UUID()
        let targetFile: String
        let generatedContent: String
        let explanation: String
        let warnings: [String]
    }

    struct MigrationPlan: Identifiable {
        let id = UUID()
        let sourceFile: String
        let targetFile: String
        let steps: [MigrationStep]
        let warnings: [String]
        let estimatedEffort: String

        struct MigrationStep: Identifiable {
            let id = UUID()
            let order: Int
            let description: String
            let originalContent: String?
            let newContent: String?
            let isManual: Bool
        }
    }

    struct ConfigUsageRecord: Codable, Identifiable {
        let id: UUID
        let filepath: String
        let filename: String
        let lastAccessed: Date
        let accessCount: Int
        let lastModified: Date?
        var learnedPriority: SyncPriority?

        enum SyncPriority: String, Codable {
            case critical = "Critical"
            case high = "High"
            case medium = "Medium"
            case low = "Low"
        }
    }

    // MARK: - Natural Language Search

    /// Search configs using natural language queries
    func search(query: String, in configs: [ConfigFile]) async -> [SearchResult] {
        isProcessing = true
        defer { isProcessing = false }

        // First, do a quick keyword search
        var results = keywordSearch(query: query, in: configs)

        // Enhance with AI semantic search (built-in: keyword results only)
        let semanticResults = await semanticSearch(query: query, in: configs)
        results = mergeSearchResults(keyword: results, semantic: semanticResults)

        searchResults = results.sorted { $0.relevanceScore > $1.relevanceScore }
        return searchResults
    }

    private func keywordSearch(query: String, in configs: [ConfigFile]) -> [SearchResult] {
        var results: [SearchResult] = []
        let queryTerms = query.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        for config in configs {
            guard let content = try? String(contentsOf: URL(fileURLWithPath: config.path), encoding: .utf8) else {
                continue
            }

            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let lowercaseLine = line.lowercased()
                let matchCount = queryTerms.filter { lowercaseLine.contains($0) }.count

                if matchCount > 0 {
                    let score = Double(matchCount) / Double(queryTerms.count)
                    results.append(SearchResult(
                        filename: config.filename,
                        filepath: config.path,
                        matchType: .exactMatch,
                        matchedContent: line.trimmingCharacters(in: .whitespaces),
                        lineNumber: index + 1,
                        relevanceScore: score
                    ))
                }
            }
        }

        return results
    }

    private func semanticSearch(query: String, in configs: [ConfigFile]) async -> [SearchResult] {
        // Build context from all configs
        var configSummaries: [(config: ConfigFile, content: String)] = []
        for config in configs {
            if let content = try? String(contentsOf: URL(fileURLWithPath: config.path), encoding: .utf8) {
                configSummaries.append((config, String(content.prefix(1000))))
            }
        }

        guard !configSummaries.isEmpty else { return [] }

        let configList = configSummaries.enumerated().map { index, item in
            "[\(index)] \(item.config.filename):\n\(item.content)"
        }.joined(separator: "\n---\n")

        let prompt = """
        Find configuration settings related to this query: "\(query)"

        Available config files:
        \(String(configList.prefix(6000)))

        Return matches in this format (one per line):
        MATCH|<config_index>|<relevance:0.0-1.0>|<matched_content_snippet>|<explanation>

        Only return relevant matches. If nothing matches, respond with: NO_MATCHES
        """

        let candidates = configSummaries.map { $0.config }
        let result = await AppAI.run(
            ai,
            prompt: prompt,
            system: "You are a configuration search expert. Find settings that semantically match the user's query, even if exact keywords don't match.",
            temperature: 0.2,
            maxTokens: 2048,
            parse: { try Self.validateSemanticSearch($0, configs: candidates) },
            fallback: { [] }
        )
        lastSource = result.source
        return result.value
    }

    private func mergeSearchResults(keyword: [SearchResult], semantic: [SearchResult]) -> [SearchResult] {
        var merged = keyword

        // Add semantic results that aren't duplicates
        for semResult in semantic {
            let isDuplicate = keyword.contains { kwResult in
                kwResult.filepath == semResult.filepath && kwResult.lineNumber == semResult.lineNumber
            }
            if !isDuplicate {
                merged.append(semResult)
            }
        }

        return merged
    }

    // MARK: - Config Generation

    /// Generate configuration content from natural language description
    func generateConfig(description: String, targetFile: String, existingContent: String?) async -> ConfigGenerationResult? {
        isProcessing = true
        defer { isProcessing = false }

        let fileType = detectFileType(targetFile)
        let existingSection = existingContent != nil ?
            "EXISTING CONTENT (to append to or modify):\n\(String(existingContent!.prefix(2000)))" :
            "This is a new file."

        let prompt = """
        Generate configuration content for: \(targetFile)
        File type: \(fileType)

        User request: "\(description)"

        \(existingSection)

        Generate the configuration that accomplishes the user's request.
        Follow best practices for this file type.
        Include helpful comments.

        Respond in this format:
        EXPLANATION: <brief explanation of what the config does>
        WARNINGS: <any warnings about the config, or "none">
        CONFIG_START
        <the generated configuration content>
        CONFIG_END
        """

        // Built-in: none (generation needs AI) — callers show "AI unavailable" for nil.
        let result = await AppAI.run(
            ai,
            prompt: prompt,
            system: "You are a configuration expert. Generate clean, well-documented, best-practice configurations. Include comments explaining non-obvious settings.",
            temperature: 0.3,
            maxTokens: 4096,
            parse: { try Self.validateConfigGeneration($0, targetFile: targetFile) },
            fallback: { nil }
        )
        lastSource = result.source
        return result.value
    }

    // MARK: - Migration Assistant

    /// Help migrate configs when switching tools (e.g., bash→zsh, vim→neovim)
    func createMigrationPlan(
        sourceFile: String,
        sourceContent: String,
        targetTool: String
    ) async -> MigrationPlan? {
        isProcessing = true
        defer { isProcessing = false }

        let sourceTool = detectToolFromFilename(sourceFile)

        let prompt = """
        Create a migration plan to move from \(sourceTool) to \(targetTool).

        Source file: \(sourceFile)
        Source content:
        \(String(sourceContent.prefix(4000)))

        Provide a step-by-step migration plan that:
        1. Identifies what can be directly migrated
        2. Identifies what needs manual conversion
        3. Identifies what cannot be migrated
        4. Provides the new configuration content where possible

        Respond in this format:
        EFFORT: <minimal/moderate/significant>
        WARNINGS:
        - <warning 1>
        - <warning 2>
        STEPS:
        STEP|<order>|<description>|<original_content_or_NA>|<new_content_or_NA>|<manual:yes/no>
        ...
        """

        // Built-in: none (a migration plan needs AI) — callers show "AI unavailable" for nil.
        let result = await AppAI.run(
            ai,
            prompt: prompt,
            system: "You are a developer tools migration expert. Create practical, step-by-step migration plans. Be thorough but realistic about what can be automated.",
            temperature: 0.2,
            maxTokens: 4096,
            parse: { try Self.validateMigrationPlan($0, sourceFile: sourceFile, targetTool: targetTool) },
            fallback: { nil }
        )
        lastSource = result.source
        return result.value
    }

    // MARK: - Sync Priority Learning

    /// Record config file usage to learn priorities
    func recordUsage(config: ConfigFile) {
        var records = loadUsageHistory()

        if let index = records.firstIndex(where: { $0.filepath == config.path }) {
            var record = records[index]
            record = ConfigUsageRecord(
                id: record.id,
                filepath: record.filepath,
                filename: record.filename,
                lastAccessed: Date(),
                accessCount: record.accessCount + 1,
                lastModified: record.lastModified,
                learnedPriority: record.learnedPriority
            )
            records[index] = record
        } else {
            let record = ConfigUsageRecord(
                id: UUID(),
                filepath: config.path,
                filename: config.filename,
                lastAccessed: Date(),
                accessCount: 1,
                lastModified: nil,
                learnedPriority: nil
            )
            records.append(record)
        }

        saveUsageHistory(records)
        usageHistory = records
    }

    /// Calculate learned priority based on usage patterns
    func calculateLearnedPriority(for config: ConfigFile) -> ConfigUsageRecord.SyncPriority {
        let records = loadUsageHistory()

        guard let record = records.first(where: { $0.filepath == config.path }) else {
            return .medium
        }

        // Priority based on access frequency and recency
        let daysSinceAccess = Calendar.current.dateComponents([.day], from: record.lastAccessed, to: Date()).day ?? 0

        if record.accessCount >= 10 && daysSinceAccess < 7 {
            return .critical
        } else if record.accessCount >= 5 && daysSinceAccess < 14 {
            return .high
        } else if record.accessCount >= 2 && daysSinceAccess < 30 {
            return .medium
        } else {
            return .low
        }
    }

    /// Get AI-suggested priorities for all configs based on usage and content
    func suggestPriorities(for configs: [ConfigFile]) async -> [String: ConfigUsageRecord.SyncPriority] {
        var priorities: [String: ConfigUsageRecord.SyncPriority] = [:]

        // Start with learned priorities
        for config in configs {
            priorities[config.path] = calculateLearnedPriority(for: config)
        }

        // Enhance with AI content analysis (built-in: learned priorities only).
        // AI can upgrade a priority, never downgrade the learned one, and only for files we asked about.
        let aiPriorities = await analyzeConfigImportance(configs: configs)
        for (path, aiPriority) in aiPriorities {
            if let current = priorities[path], aiPriority > current {
                priorities[path] = aiPriority
            }
        }

        return priorities
    }

    private func analyzeConfigImportance(configs: [ConfigFile]) async -> [String: ConfigUsageRecord.SyncPriority] {
        let configList = configs.prefix(20).map { "\($0.filename): \($0.path)" }.joined(separator: "\n")

        let prompt = """
        Analyze these configuration files and suggest sync priorities based on typical developer importance.

        Files:
        \(configList)

        Consider:
        - Shell configs (.zshrc, .bashrc) are usually critical
        - Git config is usually high priority
        - Cloud CLI configs (AWS, Azure) are high priority for cloud developers
        - Editor configs vary by usage

        Respond with priorities in this format (one per line):
        PRIORITY|<filepath>|<critical/high/medium/low>
        """

        let knownPaths = Set(configs.prefix(20).map(\.path))
        let result = await AppAI.run(
            ai,
            prompt: prompt,
            system: "You are evaluating configuration file importance. Be practical - prioritize files that affect daily workflow.",
            temperature: 0.2,
            maxTokens: 1024,
            parse: { try Self.validatePriorities($0, knownPaths: knownPaths) },
            fallback: { [:] }
        )
        lastSource = result.source
        return result.value
    }

    // MARK: - Storage Helpers

    private func loadUsageHistory() -> [ConfigUsageRecord] {
        guard let data = userDefaults.data(forKey: "AIConfigAssistant_UsageHistory"),
              let records = try? JSONDecoder().decode([ConfigUsageRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func saveUsageHistory(_ records: [ConfigUsageRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            userDefaults.set(data, forKey: "AIConfigAssistant_UsageHistory")
        }
    }

    // MARK: - Validators (reject replies that ignore the format; clamp values to their legal range)

    /// Rejects a reply with neither NO_MATCHES nor a MATCH line; drops out-of-range indices; clamps relevance to 0...1.
    nonisolated static func validateSemanticSearch(_ response: String, configs: [ConfigFile]) throws -> [SearchResult] {
        let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard response.contains("NO_MATCHES") || lines.contains(where: { $0.hasPrefix("MATCH|") }) else {
            throw NovaAIValidationError("expected MATCH|… lines or NO_MATCHES")
        }
        return parseSemanticSearchResults(lines.joined(separator: "\n"), configs: configs).map { r in
            let score = r.relevanceScore.isFinite ? min(max(r.relevanceScore, 0), 1) : 0.5
            return SearchResult(filename: r.filename, filepath: r.filepath, matchType: r.matchType,
                                matchedContent: String(r.matchedContent.prefix(500)), lineNumber: r.lineNumber,
                                relevanceScore: score)
        }
    }

    /// Rejects a reply without content between CONFIG_START and CONFIG_END.
    nonisolated static func validateConfigGeneration(_ response: String, targetFile: String) throws -> ConfigGenerationResult? {
        guard let r = parseConfigGenerationResult(response, targetFile: targetFile) else {
            throw NovaAIValidationError("expected the configuration between CONFIG_START and CONFIG_END")
        }
        return r
    }

    /// Rejects a reply without STEP lines; renumbers steps 1…n.
    nonisolated static func validateMigrationPlan(_ response: String, sourceFile: String, targetTool: String) throws -> MigrationPlan? {
        guard let plan = parseMigrationPlan(response, sourceFile: sourceFile, targetTool: targetTool) else {
            throw NovaAIValidationError("expected STEP|… lines")
        }
        let steps = plan.steps.enumerated().map { i, s in
            MigrationPlan.MigrationStep(order: i + 1, description: s.description, originalContent: s.originalContent,
                                        newContent: s.newContent, isManual: s.isManual)
        }
        let effort = ["minimal", "moderate", "significant"].first { plan.estimatedEffort.lowercased().hasPrefix($0) } ?? "moderate"
        return MigrationPlan(sourceFile: plan.sourceFile, targetFile: plan.targetFile, steps: steps,
                             warnings: plan.warnings, estimatedEffort: effort)
    }

    /// Rejects a reply without PRIORITY lines; keeps only files that were asked about.
    nonisolated static func validatePriorities(_ response: String, knownPaths: Set<String>) throws -> [String: ConfigUsageRecord.SyncPriority] {
        let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: { $0.hasPrefix("PRIORITY|") }) else {
            throw NovaAIValidationError("expected PRIORITY|<filepath>|<priority> lines")
        }
        return parseAIPriorities(lines.joined(separator: "\n")).filter { knownPaths.contains($0.key) }
    }

    // MARK: - Parsing Helpers

    private func detectFileType(_ filename: String) -> String {
        let name = filename.lowercased()
        if name.contains("zshrc") { return "zsh shell configuration" }
        if name.contains("bashrc") || name.contains("bash_profile") { return "bash shell configuration" }
        if name.contains("gitconfig") { return "git configuration (INI format)" }
        if name.contains("vimrc") { return "vim configuration" }
        if name.contains("aws") { return "AWS configuration (INI format)" }
        if name.contains("ssh") { return "SSH configuration" }
        if name.hasSuffix(".json") { return "JSON" }
        if name.hasSuffix(".yaml") || name.hasSuffix(".yml") { return "YAML" }
        if name.hasSuffix(".toml") { return "TOML" }
        return "configuration file"
    }

    private func detectToolFromFilename(_ filename: String) -> String {
        let name = filename.lowercased()
        if name.contains("zsh") { return "Zsh" }
        if name.contains("bash") { return "Bash" }
        if name.contains("vim") && !name.contains("neovim") { return "Vim" }
        if name.contains("neovim") || name.contains("nvim") { return "Neovim" }
        if name.contains("emacs") { return "Emacs" }
        if name.contains("tmux") { return "tmux" }
        return "Unknown"
    }

    nonisolated static func parseSemanticSearchResults(_ response: String, configs: [ConfigFile]) -> [SearchResult] {
        if response.contains("NO_MATCHES") { return [] }

        var results: [SearchResult] = []

        for line in response.components(separatedBy: .newlines) {
            if line.hasPrefix("MATCH|") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 5 {
                    let index = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? -1
                    guard index >= 0 && index < configs.count else { continue }

                    let config = configs[index]
                    let relevance = Double(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0.5

                    results.append(SearchResult(
                        filename: config.filename,
                        filepath: config.path,
                        matchType: .semanticMatch,
                        matchedContent: parts[3],
                        lineNumber: nil,
                        relevanceScore: relevance
                    ))
                }
            }
        }

        return results
    }

    nonisolated static func parseConfigGenerationResult(_ response: String, targetFile: String) -> ConfigGenerationResult? {
        var explanation = ""
        var warnings: [String] = []
        var generatedContent = ""

        for line in response.components(separatedBy: .newlines) {
            if line.uppercased().hasPrefix("EXPLANATION:") {
                explanation = line.replacingOccurrences(of: "EXPLANATION:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().hasPrefix("WARNINGS:") {
                let value = line.replacingOccurrences(of: "WARNINGS:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                if value.lowercased() != "none" && !value.isEmpty {
                    warnings = value.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                }
            }
        }

        // Extract generated content
        if let startRange = response.range(of: "CONFIG_START"),
           let endRange = response.range(of: "CONFIG_END") {
            let contentStart = response.index(after: startRange.upperBound)
            generatedContent = String(response[contentStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !generatedContent.isEmpty else { return nil }

        return ConfigGenerationResult(
            targetFile: targetFile,
            generatedContent: generatedContent,
            explanation: explanation,
            warnings: warnings
        )
    }

    nonisolated static func parseMigrationPlan(_ response: String, sourceFile: String, targetTool: String) -> MigrationPlan? {
        var effort = "moderate"
        var warnings: [String] = []
        var steps: [MigrationPlan.MigrationStep] = []

        var inWarnings = false

        for line in response.components(separatedBy: .newlines) {
            if line.uppercased().hasPrefix("EFFORT:") {
                effort = line.replacingOccurrences(of: "EFFORT:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().contains("WARNINGS:") {
                inWarnings = true
            } else if line.uppercased().contains("STEPS:") {
                inWarnings = false
            } else if inWarnings && line.hasPrefix("- ") {
                warnings.append(String(line.dropFirst(2)))
            } else if line.hasPrefix("STEP|") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 6 {
                    steps.append(MigrationPlan.MigrationStep(
                        order: Int(parts[1]) ?? steps.count + 1,
                        description: parts[2],
                        originalContent: parts[3] == "NA" ? nil : parts[3],
                        newContent: parts[4] == "NA" ? nil : parts[4],
                        isManual: parts[5].lowercased().contains("yes")
                    ))
                }
            }
        }

        guard !steps.isEmpty else { return nil }

        let targetFile = ".\(targetTool.lowercased())rc"

        return MigrationPlan(
            sourceFile: sourceFile,
            targetFile: targetFile,
            steps: steps.sorted { $0.order < $1.order },
            warnings: warnings,
            estimatedEffort: effort
        )
    }

    nonisolated static func parseAIPriorities(_ response: String) -> [String: ConfigUsageRecord.SyncPriority] {
        var priorities: [String: ConfigUsageRecord.SyncPriority] = [:]

        for line in response.components(separatedBy: .newlines) {
            if line.hasPrefix("PRIORITY|") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 3 {
                    let filepath = parts[1].trimmingCharacters(in: .whitespaces)
                    let priorityStr = parts[2].trimmingCharacters(in: .whitespaces).lowercased()

                    let priority: ConfigUsageRecord.SyncPriority = {
                        switch priorityStr {
                        case "critical": return .critical
                        case "high": return .high
                        case "medium": return .medium
                        case "low": return .low
                        default: return .medium
                        }
                    }()

                    priorities[filepath] = priority
                }
            }
        }

        return priorities
    }
}

// Extension to make SyncPriority comparable
extension AIConfigAssistant.ConfigUsageRecord.SyncPriority: Comparable {
    static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}
