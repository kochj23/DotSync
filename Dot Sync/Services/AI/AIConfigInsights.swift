//
//  AIConfigInsights.swift
//  Dot Sync
//
//  AI-powered configuration insights and recommendations
//  Features: Config Health Check, Best Practices, Shell Optimization, Unused Config Detection
//  Author: Jordan Koch
//

import Foundation
import NovaAIKit

/// AI-powered configuration insights and recommendations
@MainActor
class AIConfigInsights: ObservableObject {
    static let shared = AIConfigInsights()

    @Published var isAnalyzing = false
    @Published var lastHealthReport: HealthReport?
    @Published var recommendations: [Recommendation] = []
    /// Where the last result came from ("AI · Ollama (model)" / "Built-in").
    @Published var lastSource: NovaAISource?

    private let ai: NovaAI

    init(ai: NovaAI? = nil) {
        self.ai = ai ?? AppAI.shared
    }

    // MARK: - Data Models

    struct HealthReport: Identifiable {
        let id = UUID()
        let timestamp: Date
        let overallScore: Int // 0-100
        let configResults: [ConfigHealthResult]
        let summary: String

        struct ConfigHealthResult: Identifiable {
            let id = UUID()
            let filename: String
            let score: Int // 0-100
            let issues: [HealthIssue]
            let status: HealthStatus
        }

        struct HealthIssue: Identifiable {
            let id = UUID()
            let severity: IssueSeverity
            let description: String
            let fix: String?
            let lineNumber: Int?

            enum IssueSeverity: String {
                case error = "Error"
                case warning = "Warning"
                case info = "Info"
            }
        }

        enum HealthStatus: String {
            case healthy = "Healthy"
            case needsAttention = "Needs Attention"
            case problematic = "Problematic"
            case unknown = "Unknown"
        }
    }

    struct Recommendation: Identifiable {
        let id = UUID()
        let filename: String
        let category: RecommendationCategory
        let title: String
        let description: String
        let suggestedChange: String?
        let priority: Priority

        enum RecommendationCategory: String {
            case security = "Security"
            case performance = "Performance"
            case bestPractice = "Best Practice"
            case modernization = "Modernization"
            case cleanup = "Cleanup"
        }

        enum Priority: String, Comparable {
            case high = "High"
            case medium = "Medium"
            case low = "Low"

            static func < (lhs: Priority, rhs: Priority) -> Bool {
                let order: [Priority] = [.low, .medium, .high]
                return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
            }
        }
    }

    struct ShellAnalysis: Identifiable {
        let id = UUID()
        let filename: String
        let startupTime: String?
        let issues: [ShellIssue]
        let optimizations: [String]

        struct ShellIssue: Identifiable {
            let id = UUID()
            let type: IssueType
            let description: String
            let lineNumber: Int?
            let suggestion: String

            enum IssueType: String {
                case slowStartup = "Slow Startup"
                case redundantAlias = "Redundant Alias"
                case conflictingConfig = "Conflicting Config"
                case deprecatedSyntax = "Deprecated Syntax"
                case inefficientCode = "Inefficient Code"
            }
        }
    }

    struct UnusedConfigResult: Identifiable {
        let id = UUID()
        let filename: String
        let toolName: String
        let reason: String
        let canDelete: Bool
    }

    // MARK: - Config Health Check

    /// Analyze configurations for deprecated settings, typos, or common mistakes
    func runHealthCheck(configs: [ConfigFile]) async -> HealthReport {
        isAnalyzing = true
        defer { isAnalyzing = false }

        var configResults: [HealthReport.ConfigHealthResult] = []

        for config in configs {
            guard let content = try? String(contentsOf: URL(fileURLWithPath: config.path), encoding: .utf8) else {
                continue
            }

            let result = await analyzeConfigHealth(content: content, filename: config.filename, filepath: config.path)
            configResults.append(result)
        }

        let avgScore = configResults.isEmpty ? 100 : configResults.map { $0.score }.reduce(0, +) / configResults.count
        let issueCount = configResults.flatMap { $0.issues }.count

        let summary: String
        if avgScore >= 90 {
            summary = "Your configurations are in excellent shape!"
        } else if avgScore >= 70 {
            summary = "Configurations are good with minor issues (\(issueCount) found)."
        } else if avgScore >= 50 {
            summary = "Some configurations need attention (\(issueCount) issues found)."
        } else {
            summary = "Multiple configuration issues detected (\(issueCount) issues). Review recommended."
        }

        let report = HealthReport(
            timestamp: Date(),
            overallScore: avgScore,
            configResults: configResults,
            summary: summary
        )

        lastHealthReport = report
        return report
    }

    private func analyzeConfigHealth(content: String, filename: String, filepath: String) async -> HealthReport.ConfigHealthResult {
        let prompt = """
        Analyze this configuration file for health issues.

        Check for:
        1. Syntax errors or typos
        2. Deprecated settings or options
        3. Common mistakes for this file type
        4. Missing recommended settings
        5. Potential conflicts

        File: \(filename)
        Path: \(filepath)
        Content:
        \(String(content.prefix(4000)))

        For each issue found, respond in this format (one per line):
        ISSUE|<severity:error/warning/info>|<line_number_or_0>|<description>|<fix_suggestion>

        After all issues, provide:
        SCORE: <0-100>

        If no issues: respond with SCORE: 100
        """

        let lineCount = content.components(separatedBy: .newlines).count
        let result = await AppAI.run(
            ai,
            prompt: prompt,
            system: "You are a configuration file expert. Check for real issues only - avoid false positives. Be helpful with fix suggestions.",
            temperature: 0.2,
            maxTokens: 2048,
            parse: { try Self.validateHealthCheck($0, filename: filename, lineCount: lineCount) },
            fallback: { Self.basicHealthCheck(content: content, filename: filename) }
        )
        lastSource = result.source
        return result.value
    }

    nonisolated static func basicHealthCheck(content: String, filename: String) -> HealthReport.ConfigHealthResult {
        var issues: [HealthReport.HealthIssue] = []
        let lines = content.components(separatedBy: .newlines)

        // Basic checks
        for (index, line) in lines.enumerated() {
            // Check for trailing whitespace (minor)
            if line.hasSuffix(" ") || line.hasSuffix("\t") {
                issues.append(HealthReport.HealthIssue(
                    severity: .info,
                    description: "Trailing whitespace",
                    fix: "Remove trailing whitespace",
                    lineNumber: index + 1
                ))
            }

            // Check for very long lines
            if line.count > 500 {
                issues.append(HealthReport.HealthIssue(
                    severity: .warning,
                    description: "Very long line (\(line.count) chars)",
                    fix: "Consider breaking into multiple lines",
                    lineNumber: index + 1
                ))
            }
        }

        let score = max(0, 100 - (issues.count * 2))
        let status: HealthReport.HealthStatus = {
            if score >= 90 { return .healthy }
            if score >= 70 { return .needsAttention }
            return .problematic
        }()

        return HealthReport.ConfigHealthResult(
            filename: filename,
            score: score,
            issues: issues,
            status: status
        )
    }

    // MARK: - Best Practices Suggestions

    /// Generate best practice recommendations for configuration files
    func suggestBestPractices(for config: ConfigFile) async -> [Recommendation] {
        guard let content = try? String(contentsOf: URL(fileURLWithPath: config.path), encoding: .utf8) else {
            return []
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let prompt = """
        Review this configuration file and suggest best practices.

        File: \(config.filename)
        Type: \(detectConfigType(config.filename))
        Content:
        \(String(content.prefix(3000)))

        Suggest improvements for:
        1. Security hardening
        2. Performance optimization
        3. Modern best practices
        4. Useful additions

        Respond with recommendations in this format (one per line):
        REC|<category:security/performance/bestPractice/modernization/cleanup>|<priority:high/medium/low>|<title>|<description>|<suggested_change_or_NA>
        """

        let filename = config.filename
        let result = await AppAI.run(
            ai,
            prompt: prompt,
            system: "You are a DevOps best practices expert. Provide actionable, specific recommendations. Focus on high-value improvements.",
            temperature: 0.3,
            maxTokens: 2048,
            parse: { try Self.validateRecommendations($0, filename: filename) },
            fallback: { Self.getStaticBestPractices(for: filename) }
        )
        lastSource = result.source
        return result.value
    }

    nonisolated static func getStaticBestPractices(for filename: String) -> [Recommendation] {
        var recs: [Recommendation] = []

        if filename.contains("gitconfig") {
            recs.append(Recommendation(
                filename: filename,
                category: .security,
                title: "Enable commit signing",
                description: "Sign your commits with GPG for added security",
                suggestedChange: "[commit]\n    gpgsign = true",
                priority: .medium
            ))
        }

        if filename.contains("zshrc") || filename.contains("bashrc") {
            recs.append(Recommendation(
                filename: filename,
                category: .performance,
                title: "Lazy load completions",
                description: "Defer loading completions for faster shell startup",
                suggestedChange: nil,
                priority: .low
            ))
        }

        return recs
    }

    // MARK: - Shell Optimization

    /// Analyze shell configs for slow startup, redundant aliases, or conflicts
    func analyzeShellConfig(content: String, filename: String) async -> ShellAnalysis {
        isAnalyzing = true
        defer { isAnalyzing = false }

        let prompt = """
        Analyze this shell configuration for optimization opportunities.

        File: \(filename)
        Content:
        \(String(content.prefix(4000)))

        Check for:
        1. SLOW STARTUP: Heavy operations running on every shell start (nvm, rbenv init without lazy loading)
        2. REDUNDANT ALIASES: Duplicate or conflicting alias definitions
        3. CONFLICTING CONFIG: PATH additions that override each other, conflicting env vars
        4. DEPRECATED SYNTAX: Old-style syntax that could be modernized
        5. INEFFICIENT CODE: Subshells in loops, unnecessary command substitutions

        Respond in this format:
        STARTUP_IMPACT: <fast/moderate/slow/very_slow>
        ISSUES:
        ISSUE|<type:slowStartup/redundantAlias/conflictingConfig/deprecatedSyntax/inefficientCode>|<line_number_or_0>|<description>|<suggestion>
        ...
        OPTIMIZATIONS:
        - <optimization suggestion>
        ...
        """

        let result = await AppAI.run(
            ai,
            prompt: prompt,
            system: "You are a shell scripting expert focused on performance. Identify real performance issues and provide specific fixes.",
            temperature: 0.2,
            maxTokens: 2048,
            parse: { try Self.validateShellAnalysis($0, filename: filename) },
            fallback: { Self.basicShellAnalysis(content: content, filename: filename) }
        )
        lastSource = result.source
        return result.value
    }

    nonisolated static func basicShellAnalysis(content: String, filename: String) -> ShellAnalysis {
        var issues: [ShellAnalysis.ShellIssue] = []
        var optimizations: [String] = []

        // Check for common slow patterns
        if content.contains("nvm") && !content.contains("--no-use") {
            issues.append(ShellAnalysis.ShellIssue(
                type: .slowStartup,
                description: "NVM loads on every shell start",
                lineNumber: nil,
                suggestion: "Use lazy loading for NVM"
            ))
        }

        if content.contains("rbenv init") {
            issues.append(ShellAnalysis.ShellIssue(
                type: .slowStartup,
                description: "rbenv initializes on every shell start",
                lineNumber: nil,
                suggestion: "Consider lazy loading rbenv"
            ))
        }

        // Check for duplicate alias patterns
        let aliasPattern = try? NSRegularExpression(pattern: "^alias\\s+(\\w+)=", options: .anchorsMatchLines)
        if let regex = aliasPattern {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            let aliasNames = matches.compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: content) else { return nil }
                return String(content[range])
            }
            let duplicates = Dictionary(grouping: aliasNames, by: { $0 }).filter { $0.value.count > 1 }
            for (alias, _) in duplicates {
                issues.append(ShellAnalysis.ShellIssue(
                    type: .redundantAlias,
                    description: "Alias '\(alias)' defined multiple times",
                    lineNumber: nil,
                    suggestion: "Remove duplicate alias definitions"
                ))
            }
        }

        if issues.isEmpty {
            optimizations.append("Shell configuration looks optimized!")
        }

        return ShellAnalysis(
            filename: filename,
            startupTime: nil,
            issues: issues,
            optimizations: optimizations
        )
    }

    // MARK: - Unused Config Detection

    /// Identify configs for tools no longer installed on the machine
    func detectUnusedConfigs(configs: [ConfigFile]) async -> [UnusedConfigResult] {
        isAnalyzing = true
        defer { isAnalyzing = false }

        var results: [UnusedConfigResult] = []

        // Map of config files to their expected tools
        let configToolMap: [(pattern: String, tool: String, checkCommand: String)] = [
            (".npmrc", "npm", "npm --version"),
            (".yarnrc", "yarn", "yarn --version"),
            (".pypirc", "pip", "pip --version"),
            (".cargo", "cargo", "cargo --version"),
            (".rustup", "rustup", "rustup --version"),
            (".rbenv", "rbenv", "rbenv --version"),
            (".nvm", "nvm", "command -v nvm"),
            (".docker", "docker", "docker --version"),
            (".kube", "kubectl", "kubectl version --client"),
            (".terraform", "terraform", "terraform --version"),
            (".aws", "aws-cli", "aws --version"),
            (".azure", "azure-cli", "az --version"),
            ("gcloud", "gcloud", "gcloud --version"),
        ]

        for config in configs {
            for (pattern, tool, checkCommand) in configToolMap {
                if config.filename.contains(pattern) || config.path.contains(pattern) {
                    let isInstalled = await checkToolInstalled(command: checkCommand)
                    if !isInstalled {
                        results.append(UnusedConfigResult(
                            filename: config.filename,
                            toolName: tool,
                            reason: "\(tool) does not appear to be installed",
                            canDelete: true
                        ))
                    }
                }
            }
        }

        return results
    }

    private func checkToolInstalled(command: String) async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Validators (reject replies that ignore the format; clamp values to their legal range)

    /// Rejects a reply without SCORE:; clamps the score to 0...100 and drops line numbers outside the file.
    nonisolated static func validateHealthCheck(_ response: String, filename: String, lineCount: Int) throws -> HealthReport.ConfigHealthResult {
        let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let scoreLine = lines.first(where: { $0.uppercased().hasPrefix("SCORE:") }),
              Int(scoreLine.dropFirst(6).trimmingCharacters(in: .whitespaces).components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "") != nil else {
            throw NovaAIValidationError("expected a numeric SCORE: line")
        }
        let r = parseHealthCheckResult(lines.joined(separator: "\n"), filename: filename)
        let score = min(max(r.score, 0), 100)
        let issues = r.issues.map { i -> HealthReport.HealthIssue in
            guard let n = i.lineNumber, n < 1 || n > lineCount else { return i }
            return HealthReport.HealthIssue(severity: i.severity, description: i.description, fix: i.fix, lineNumber: nil)
        }
        return HealthReport.ConfigHealthResult(filename: filename, score: score, issues: issues, status: status(for: score))
    }

    /// Rejects a reply without REC lines.
    nonisolated static func validateRecommendations(_ response: String, filename: String) throws -> [Recommendation] {
        let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let recs = parseRecommendations(lines.joined(separator: "\n"), filename: filename)
        guard !recs.isEmpty else { throw NovaAIValidationError("expected REC|category|priority|title|description|change lines") }
        return recs
    }

    /// Rejects a reply without STARTUP_IMPACT:; clamps it to fast/moderate/slow/very_slow.
    nonisolated static func validateShellAnalysis(_ response: String, filename: String) throws -> ShellAnalysis {
        let lines = response.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(where: { $0.uppercased().hasPrefix("STARTUP_IMPACT:") }) else {
            throw NovaAIValidationError("expected a STARTUP_IMPACT: line")
        }
        let r = parseShellAnalysis(lines.joined(separator: "\n"), filename: filename)
        let impact = r.startupTime.map { t in
            ["very_slow", "slow", "moderate", "fast"].first { t.lowercased().replacingOccurrences(of: " ", with: "_").hasPrefix($0) } ?? "moderate"
        }
        return ShellAnalysis(filename: r.filename, startupTime: impact, issues: r.issues, optimizations: r.optimizations)
    }

    nonisolated static func status(for score: Int) -> HealthReport.HealthStatus {
        if score >= 90 { return .healthy }
        if score >= 70 { return .needsAttention }
        return .problematic
    }

    // MARK: - Parsing Helpers

    private func detectConfigType(_ filename: String) -> String {
        let name = filename.lowercased()
        if name.contains("zshrc") || name.contains("bashrc") { return "Shell" }
        if name.contains("gitconfig") { return "Git" }
        if name.contains("vimrc") { return "Vim" }
        if name.contains("aws") { return "AWS" }
        if name.contains("ssh") { return "SSH" }
        if name.contains("docker") { return "Docker" }
        return "Config"
    }

    nonisolated static func parseHealthCheckResult(_ response: String, filename: String) -> HealthReport.ConfigHealthResult {
        var issues: [HealthReport.HealthIssue] = []
        var score = 100

        for line in response.components(separatedBy: .newlines) {
            if line.hasPrefix("ISSUE|") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 5 {
                    let severityStr = parts[1].lowercased()
                    let severity: HealthReport.HealthIssue.IssueSeverity = {
                        switch severityStr {
                        case "error": return .error
                        case "warning": return .warning
                        default: return .info
                        }
                    }()

                    issues.append(HealthReport.HealthIssue(
                        severity: severity,
                        description: parts[3],
                        fix: parts[4] == "NA" ? nil : parts[4],
                        lineNumber: Int(parts[2].trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
                    ))
                }
            } else if line.uppercased().hasPrefix("SCORE:") {
                let value = line.replacingOccurrences(of: "SCORE:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                score = Int(value.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "") ?? 100
            }
        }

        let status: HealthReport.HealthStatus = {
            if score >= 90 { return .healthy }
            if score >= 70 { return .needsAttention }
            return .problematic
        }()

        return HealthReport.ConfigHealthResult(
            filename: filename,
            score: score,
            issues: issues,
            status: status
        )
    }

    nonisolated static func parseRecommendations(_ response: String, filename: String) -> [Recommendation] {
        var recommendations: [Recommendation] = []

        for line in response.components(separatedBy: .newlines) {
            if line.hasPrefix("REC|") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 6 {
                    let category: Recommendation.RecommendationCategory = {
                        switch parts[1].lowercased() {
                        case "security": return .security
                        case "performance": return .performance
                        case "bestpractice", "best_practice": return .bestPractice
                        case "modernization": return .modernization
                        case "cleanup": return .cleanup
                        default: return .bestPractice
                        }
                    }()

                    let priority: Recommendation.Priority = {
                        switch parts[2].lowercased() {
                        case "high": return .high
                        case "medium": return .medium
                        default: return .low
                        }
                    }()

                    recommendations.append(Recommendation(
                        filename: filename,
                        category: category,
                        title: parts[3],
                        description: parts[4],
                        suggestedChange: parts[5] == "NA" ? nil : parts[5],
                        priority: priority
                    ))
                }
            }
        }

        return recommendations
    }

    nonisolated static func parseShellAnalysis(_ response: String, filename: String) -> ShellAnalysis {
        var startupTime: String? = nil
        var issues: [ShellAnalysis.ShellIssue] = []
        var optimizations: [String] = []

        var inOptimizations = false

        for line in response.components(separatedBy: .newlines) {
            if line.uppercased().hasPrefix("STARTUP_IMPACT:") {
                startupTime = line.replacingOccurrences(of: "STARTUP_IMPACT:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("ISSUE|") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 5 {
                    let typeStr = parts[1].lowercased()
                    let type: ShellAnalysis.ShellIssue.IssueType = {
                        if typeStr.contains("slow") { return .slowStartup }
                        if typeStr.contains("redundant") { return .redundantAlias }
                        if typeStr.contains("conflict") { return .conflictingConfig }
                        if typeStr.contains("deprecated") { return .deprecatedSyntax }
                        return .inefficientCode
                    }()

                    issues.append(ShellAnalysis.ShellIssue(
                        type: type,
                        description: parts[3],
                        lineNumber: Int(parts[2].trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil },
                        suggestion: parts[4]
                    ))
                }
            } else if line.uppercased().contains("OPTIMIZATIONS:") {
                inOptimizations = true
            } else if inOptimizations && line.hasPrefix("- ") {
                optimizations.append(String(line.dropFirst(2)))
            }
        }

        return ShellAnalysis(
            filename: filename,
            startupTime: startupTime,
            issues: issues,
            optimizations: optimizations
        )
    }
}
