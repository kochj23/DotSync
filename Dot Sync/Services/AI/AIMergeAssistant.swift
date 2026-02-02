//
//  AIMergeAssistant.swift
//  Dot Sync
//
//  AI-powered intelligent merge assistance for configuration files
//  Features: AI Merge Suggestions, Semantic Conflict Resolution, Change Explanation
//  Author: Jordan Koch
//

import Foundation

/// AI-powered merge assistant for resolving configuration conflicts
@MainActor
class AIMergeAssistant: ObservableObject {
    static let shared = AIMergeAssistant()

    @Published var isProcessing = false
    @Published var lastMergeSuggestion: MergeSuggestion?

    private let aiManager = AIBackendManager.shared

    // MARK: - Data Models

    struct MergeSuggestion: Identifiable {
        let id = UUID()
        let filename: String
        let recommendation: MergeRecommendation
        let reasoning: String
        let mergedContent: String?
        let confidence: Double
        let warnings: [String]

        enum MergeRecommendation: String {
            case keepLocal = "Keep Local"
            case keepRemote = "Keep Remote"
            case merge = "Merge Both"
            case manualReview = "Manual Review Required"
        }
    }

    struct ChangeExplanation: Identifiable {
        let id = UUID()
        let filename: String
        let summary: String
        let changes: [ChangeDetail]
        let impact: ImpactLevel

        struct ChangeDetail: Identifiable {
            let id = UUID()
            let section: String
            let description: String
            let isAddition: Bool
            let isDeletion: Bool
            let isModification: Bool
        }

        enum ImpactLevel: String {
            case none = "No Impact"
            case low = "Low Impact"
            case medium = "Medium Impact"
            case high = "High Impact"
            case breaking = "Breaking Change"
        }
    }

    struct SemanticMergeResult: Identifiable {
        let id = UUID()
        let filename: String
        let success: Bool
        let mergedContent: String
        let conflicts: [SemanticConflict]
        let autoResolvedCount: Int

        struct SemanticConflict: Identifiable {
            let id = UUID()
            let section: String
            let localValue: String
            let remoteValue: String
            let suggestion: String
        }
    }

    // MARK: - AI Merge Suggestions

    /// Get AI-powered suggestion for how to resolve a merge conflict
    func suggestMergeResolution(
        localContent: String,
        remoteContent: String,
        ancestorContent: String?,
        filename: String
    ) async -> MergeSuggestion {
        isProcessing = true
        defer { isProcessing = false }

        guard aiManager.aiEnabled, aiManager.activeBackend != nil else {
            return createBasicSuggestion(localContent: localContent, remoteContent: remoteContent, filename: filename)
        }

        let fileType = detectFileType(filename: filename)
        let ancestorSection = ancestorContent != nil ?
            "COMMON ANCESTOR (last synced version):\n\(String(ancestorContent!.prefix(1500)))" :
            "No common ancestor available (first sync or history unavailable)"

        let prompt = """
        Analyze this configuration file merge conflict and suggest the best resolution.

        File: \(filename)
        Type: \(fileType)

        LOCAL VERSION (this machine):
        \(String(localContent.prefix(2000)))

        REMOTE VERSION (cloud):
        \(String(remoteContent.prefix(2000)))

        \(ancestorSection)

        Analyze the differences and recommend:
        1. Which version to keep, or how to merge
        2. Your reasoning
        3. Any warnings about the merge

        Respond in this exact format:
        RECOMMENDATION: <keep_local/keep_remote/merge/manual>
        CONFIDENCE: <0.0-1.0>
        REASONING: <your explanation>
        WARNINGS: <any warnings, or "none">
        MERGED_CONTENT: <if recommending merge, provide the merged content, otherwise write "N/A">
        """

        do {
            let response = try await aiManager.generate(
                prompt: prompt,
                systemPrompt: "You are an expert DevOps engineer who understands configuration files deeply. When merging, preserve both sets of changes when possible. Prioritize functional correctness over formatting.",
                temperature: 0.2,
                maxTokens: 4096
            )

            let suggestion = parseMergeSuggestion(response, filename: filename)
            lastMergeSuggestion = suggestion
            return suggestion
        } catch {
            return createBasicSuggestion(localContent: localContent, remoteContent: remoteContent, filename: filename)
        }
    }

    private func createBasicSuggestion(localContent: String, remoteContent: String, filename: String) -> MergeSuggestion {
        // Basic heuristic: newer is usually better, but flag for manual review
        let localLines = localContent.components(separatedBy: .newlines).count
        let remoteLines = remoteContent.components(separatedBy: .newlines).count

        return MergeSuggestion(
            filename: filename,
            recommendation: .manualReview,
            reasoning: "AI analysis unavailable. Local has \(localLines) lines, remote has \(remoteLines) lines. Manual review recommended.",
            mergedContent: nil,
            confidence: 0.3,
            warnings: ["AI backend unavailable - using basic comparison only"]
        )
    }

    // MARK: - Semantic Conflict Resolution

    /// Understand config syntax and merge intelligently
    func semanticMerge(
        localContent: String,
        remoteContent: String,
        filename: String
    ) async -> SemanticMergeResult {
        isProcessing = true
        defer { isProcessing = false }

        let fileType = detectFileType(filename: filename)

        guard aiManager.aiEnabled, aiManager.activeBackend != nil else {
            return performBasicMerge(localContent: localContent, remoteContent: remoteContent, filename: filename)
        }

        let prompt = """
        Perform a semantic merge of this \(fileType) configuration file.

        Understand the file's structure and merge intelligently:
        - For shell configs (.zshrc, .bashrc): Merge aliases, exports, functions separately
        - For Git config: Merge sections [user], [alias], [core], etc. independently
        - For YAML/JSON: Merge by key paths
        - For INI files: Merge by section

        LOCAL VERSION:
        \(String(localContent.prefix(3000)))

        REMOTE VERSION:
        \(String(remoteContent.prefix(3000)))

        Rules:
        1. Keep both versions of non-conflicting changes
        2. For direct conflicts, prefer the more complete/recent value
        3. Preserve comments and formatting where possible
        4. Mark unresolvable conflicts clearly

        Respond in this format:
        SUCCESS: <yes/no>
        AUTO_RESOLVED: <number of auto-resolved conflicts>
        CONFLICTS: <list any remaining conflicts, one per line as: CONFLICT|section|local_value|remote_value|suggestion>
        MERGED_CONTENT_START
        <the complete merged file content>
        MERGED_CONTENT_END
        """

        do {
            let response = try await aiManager.generate(
                prompt: prompt,
                systemPrompt: "You are a configuration file expert. Merge files semantically, understanding their structure. Output clean, working configuration files.",
                temperature: 0.1,
                maxTokens: 8192
            )

            return parseSemanticMergeResult(response, filename: filename)
        } catch {
            return performBasicMerge(localContent: localContent, remoteContent: remoteContent, filename: filename)
        }
    }

    private func performBasicMerge(localContent: String, remoteContent: String, filename: String) -> SemanticMergeResult {
        // Use the existing ThreeWayMerge for basic merging
        let mergeResult = ThreeWayMerge.merge(
            ancestor: localContent, // Use local as ancestor for basic 2-way merge
            local: localContent,
            remote: remoteContent
        )

        return SemanticMergeResult(
            filename: filename,
            success: !mergeResult.hasConflicts,
            mergedContent: mergeResult.mergedContent,
            conflicts: mergeResult.conflicts.map { conflict in
                SemanticMergeResult.SemanticConflict(
                    section: "Line \(conflict.lineNumber)",
                    localValue: conflict.localLine,
                    remoteValue: conflict.remoteLine,
                    suggestion: "Review manually"
                )
            },
            autoResolvedCount: 0
        )
    }

    // MARK: - Change Explanation

    /// Explain what changed between two versions in plain English
    func explainChanges(
        originalContent: String,
        newContent: String,
        filename: String
    ) async -> ChangeExplanation {
        isProcessing = true
        defer { isProcessing = false }

        let fileType = detectFileType(filename: filename)

        guard aiManager.aiEnabled, aiManager.activeBackend != nil else {
            return createBasicExplanation(originalContent: originalContent, newContent: newContent, filename: filename)
        }

        let prompt = """
        Explain the changes between these two versions of a \(fileType) configuration file in plain English.

        File: \(filename)

        ORIGINAL VERSION:
        \(String(originalContent.prefix(2500)))

        NEW VERSION:
        \(String(newContent.prefix(2500)))

        Provide a human-readable explanation of:
        1. A brief summary of what changed
        2. Specific changes by section/category
        3. The potential impact of these changes

        Respond in this format:
        SUMMARY: <one sentence summary>
        IMPACT: <none/low/medium/high/breaking>
        CHANGES:
        - SECTION|<section name>|<description>|<add/delete/modify>
        - SECTION|<section name>|<description>|<add/delete/modify>
        ...
        """

        do {
            let response = try await aiManager.generate(
                prompt: prompt,
                systemPrompt: "You are a technical writer explaining configuration changes to developers. Be clear and concise. Focus on what matters.",
                temperature: 0.3,
                maxTokens: 2048
            )

            return parseChangeExplanation(response, filename: filename)
        } catch {
            return createBasicExplanation(originalContent: originalContent, newContent: newContent, filename: filename)
        }
    }

    private func createBasicExplanation(originalContent: String, newContent: String, filename: String) -> ChangeExplanation {
        let originalLines = Set(originalContent.components(separatedBy: .newlines))
        let newLines = Set(newContent.components(separatedBy: .newlines))

        let additions = newLines.subtracting(originalLines).count
        let deletions = originalLines.subtracting(newLines).count

        var changes: [ChangeExplanation.ChangeDetail] = []
        if additions > 0 {
            changes.append(ChangeExplanation.ChangeDetail(
                section: "Content",
                description: "\(additions) lines added",
                isAddition: true,
                isDeletion: false,
                isModification: false
            ))
        }
        if deletions > 0 {
            changes.append(ChangeExplanation.ChangeDetail(
                section: "Content",
                description: "\(deletions) lines removed",
                isAddition: false,
                isDeletion: true,
                isModification: false
            ))
        }

        let impact: ChangeExplanation.ImpactLevel = {
            let totalChange = additions + deletions
            if totalChange == 0 { return .none }
            if totalChange < 5 { return .low }
            if totalChange < 20 { return .medium }
            return .high
        }()

        return ChangeExplanation(
            filename: filename,
            summary: "File has \(additions) additions and \(deletions) deletions.",
            changes: changes,
            impact: impact
        )
    }

    // MARK: - Parsing Helpers

    private func detectFileType(filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        let name = filename.lowercased()

        if name.contains("zshrc") || name.contains("bashrc") || name.contains("bash_profile") {
            return "Shell Configuration"
        } else if name == ".gitconfig" || name == "gitconfig" {
            return "Git Configuration"
        } else if ext == "json" { return "JSON" }
        else if ext == "yaml" || ext == "yml" { return "YAML" }
        else if ext == "toml" { return "TOML" }
        else if ext == "ini" || ext == "conf" || ext == "cfg" { return "INI/Config" }
        else if name.contains("vimrc") { return "Vim Configuration" }
        else if name.contains("aws") { return "AWS Configuration" }
        else if name.contains("ssh") { return "SSH Configuration" }

        return "Configuration"
    }

    private func parseMergeSuggestion(_ response: String, filename: String) -> MergeSuggestion {
        var recommendation: MergeSuggestion.MergeRecommendation = .manualReview
        var confidence: Double = 0.5
        var reasoning = ""
        var warnings: [String] = []
        var mergedContent: String? = nil

        for line in response.components(separatedBy: .newlines) {
            if line.uppercased().hasPrefix("RECOMMENDATION:") {
                let value = line.replacingOccurrences(of: "RECOMMENDATION:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces).lowercased()
                switch value {
                case "keep_local", "keeplocal", "local": recommendation = .keepLocal
                case "keep_remote", "keepremote", "remote": recommendation = .keepRemote
                case "merge", "both": recommendation = .merge
                default: recommendation = .manualReview
                }
            } else if line.uppercased().hasPrefix("CONFIDENCE:") {
                let value = line.replacingOccurrences(of: "CONFIDENCE:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                confidence = Double(value) ?? 0.5
            } else if line.uppercased().hasPrefix("REASONING:") {
                reasoning = line.replacingOccurrences(of: "REASONING:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().hasPrefix("WARNINGS:") {
                let value = line.replacingOccurrences(of: "WARNINGS:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                if value.lowercased() != "none" && !value.isEmpty {
                    warnings = value.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                }
            }
        }

        // Extract merged content if present
        if let startRange = response.range(of: "MERGED_CONTENT_START"),
           let endRange = response.range(of: "MERGED_CONTENT_END") {
            let contentStart = response.index(after: startRange.upperBound)
            mergedContent = String(response[contentStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return MergeSuggestion(
            filename: filename,
            recommendation: recommendation,
            reasoning: reasoning.isEmpty ? "Unable to determine reasoning" : reasoning,
            mergedContent: mergedContent,
            confidence: confidence,
            warnings: warnings
        )
    }

    private func parseSemanticMergeResult(_ response: String, filename: String) -> SemanticMergeResult {
        var success = false
        var autoResolved = 0
        var conflicts: [SemanticMergeResult.SemanticConflict] = []
        var mergedContent = ""

        for line in response.components(separatedBy: .newlines) {
            if line.uppercased().hasPrefix("SUCCESS:") {
                success = line.lowercased().contains("yes")
            } else if line.uppercased().hasPrefix("AUTO_RESOLVED:") {
                let value = line.replacingOccurrences(of: "AUTO_RESOLVED:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                autoResolved = Int(value) ?? 0
            } else if line.hasPrefix("CONFLICT|") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 5 {
                    conflicts.append(SemanticMergeResult.SemanticConflict(
                        section: parts[1],
                        localValue: parts[2],
                        remoteValue: parts[3],
                        suggestion: parts[4]
                    ))
                }
            }
        }

        // Extract merged content
        if let startRange = response.range(of: "MERGED_CONTENT_START"),
           let endRange = response.range(of: "MERGED_CONTENT_END") {
            let contentStart = response.index(after: startRange.upperBound)
            mergedContent = String(response[contentStart..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return SemanticMergeResult(
            filename: filename,
            success: success,
            mergedContent: mergedContent,
            conflicts: conflicts,
            autoResolvedCount: autoResolved
        )
    }

    private func parseChangeExplanation(_ response: String, filename: String) -> ChangeExplanation {
        var summary = ""
        var impact: ChangeExplanation.ImpactLevel = .low
        var changes: [ChangeExplanation.ChangeDetail] = []

        for line in response.components(separatedBy: .newlines) {
            if line.uppercased().hasPrefix("SUMMARY:") {
                summary = line.replacingOccurrences(of: "SUMMARY:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().hasPrefix("IMPACT:") {
                let value = line.replacingOccurrences(of: "IMPACT:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces).lowercased()
                switch value {
                case "none": impact = .none
                case "low": impact = .low
                case "medium": impact = .medium
                case "high": impact = .high
                case "breaking": impact = .breaking
                default: impact = .low
                }
            } else if line.contains("SECTION|") || line.hasPrefix("- SECTION|") {
                let cleanLine = line.replacingOccurrences(of: "- ", with: "")
                let parts = cleanLine.components(separatedBy: "|")
                if parts.count >= 4 {
                    let changeType = parts[3].lowercased()
                    changes.append(ChangeExplanation.ChangeDetail(
                        section: parts[1],
                        description: parts[2],
                        isAddition: changeType.contains("add"),
                        isDeletion: changeType.contains("delete") || changeType.contains("remove"),
                        isModification: changeType.contains("modify") || changeType.contains("change")
                    ))
                }
            }
        }

        return ChangeExplanation(
            filename: filename,
            summary: summary.isEmpty ? "Changes detected in file" : summary,
            changes: changes,
            impact: impact
        )
    }
}
