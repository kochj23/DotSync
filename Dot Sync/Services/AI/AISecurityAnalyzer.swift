//
//  AISecurityAnalyzer.swift
//  Dot Sync
//
//  AI-powered security analysis for configuration files
//  Features: Smart Credential Detection, Config Security Audit, Anomaly Detection
//  Author: Jordan Koch
//

import Foundation

/// AI-powered security analyzer for configuration files
@MainActor
class AISecurityAnalyzer: ObservableObject {
    static let shared = AISecurityAnalyzer()

    @Published var isAnalyzing = false
    @Published var lastAnalysisResults: [SecurityAnalysisResult] = []

    private let aiManager = AIBackendManager.shared

    // MARK: - Analysis Results

    struct SecurityAnalysisResult: Identifiable {
        let id = UUID()
        let filename: String
        let filepath: String
        let findings: [SecurityFinding]
        let overallRisk: RiskLevel
        let timestamp: Date

        enum RiskLevel: String, Comparable {
            case critical = "Critical"
            case high = "High"
            case medium = "Medium"
            case low = "Low"
            case none = "None"

            var color: String {
                switch self {
                case .critical: return "red"
                case .high: return "orange"
                case .medium: return "yellow"
                case .low: return "blue"
                case .none: return "green"
                }
            }

            static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
                let order: [RiskLevel] = [.none, .low, .medium, .high, .critical]
                return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
            }
        }
    }

    struct SecurityFinding: Identifiable {
        let id = UUID()
        let type: FindingType
        let description: String
        let lineNumber: Int?
        let recommendation: String
        let severity: SecurityAnalysisResult.RiskLevel

        enum FindingType: String {
            case hardcodedCredential = "Hardcoded Credential"
            case base64EncodedSecret = "Base64 Encoded Secret"
            case weakConfiguration = "Weak Configuration"
            case exposedToken = "Exposed Token"
            case insecureSetting = "Insecure Setting"
            case deprecatedOption = "Deprecated Option"
            case permissionIssue = "Permission Issue"
            case anomaly = "Anomaly Detected"
        }
    }

    // MARK: - Smart Credential Detection

    /// AI-powered credential detection that finds obfuscated secrets regex misses
    func detectCredentials(in content: String, filename: String) async -> [SecurityFinding] {
        guard aiManager.aiEnabled, aiManager.activeBackend != nil else {
            return detectCredentialsWithRegex(in: content, filename: filename)
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let prompt = """
        Analyze this configuration file for credentials, secrets, and sensitive data.
        Be thorough - look for:
        1. Hardcoded passwords, API keys, tokens (including obfuscated ones)
        2. Base64 encoded secrets (decode and check)
        3. Environment variable references that might expose secrets
        4. Connection strings with embedded credentials
        5. Private key material or certificate data
        6. OAuth client secrets or refresh tokens
        7. Database credentials
        8. AWS/Azure/GCP credentials (including assumed role configs)

        File: \(filename)
        Content:
        \(String(content.prefix(4000)))

        For each finding, respond in this exact format (one per line):
        FINDING|<type>|<severity:critical/high/medium/low>|<line_number_or_0>|<description>|<recommendation>

        If no issues found, respond with: NO_FINDINGS
        """

        do {
            let response = try await aiManager.generate(
                prompt: prompt,
                systemPrompt: "You are a senior security engineer specializing in credential detection and secrets management. Be thorough but avoid false positives. Only report actual security concerns.",
                temperature: 0.2,
                maxTokens: 2048
            )

            return parseSecurityFindings(response)
        } catch {
            print("[AISecurityAnalyzer] AI analysis failed: \(error.localizedDescription)")
            return detectCredentialsWithRegex(in: content, filename: filename)
        }
    }

    /// Fallback regex-based detection when AI is unavailable
    private func detectCredentialsWithRegex(in content: String, filename: String) -> [SecurityFinding] {
        var findings: [SecurityFinding] = []
        let lines = content.components(separatedBy: .newlines)

        let patterns: [(pattern: String, type: SecurityFinding.FindingType, severity: SecurityAnalysisResult.RiskLevel, description: String)] = [
            ("(?i)(password|passwd|pwd)\\s*[=:]\\s*['\"]?[^\\s'\"]+", .hardcodedCredential, .critical, "Hardcoded password detected"),
            ("(?i)api[_-]?key\\s*[=:]\\s*['\"]?[A-Za-z0-9_\\-]{20,}", .exposedToken, .critical, "API key detected"),
            ("sk_live_[A-Za-z0-9]{24,}", .exposedToken, .critical, "Stripe live key detected"),
            ("sk_test_[A-Za-z0-9]{24,}", .exposedToken, .medium, "Stripe test key detected"),
            ("AKIA[A-Z0-9]{16}", .exposedToken, .critical, "AWS Access Key ID detected"),
            ("(?i)bearer\\s+[A-Za-z0-9\\-_\\.]+", .exposedToken, .high, "Bearer token detected"),
            ("eyJ[A-Za-z0-9_-]*\\.[A-Za-z0-9_-]*\\.[A-Za-z0-9_-]*", .exposedToken, .high, "JWT token detected"),
            ("-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----", .hardcodedCredential, .critical, "Private key detected"),
            ("(?i)(secret|token)\\s*[=:]\\s*['\"]?[A-Za-z0-9_\\-]{16,}", .exposedToken, .high, "Secret/token detected"),
            ("ghp_[A-Za-z0-9]{36}", .exposedToken, .critical, "GitHub personal access token detected"),
            ("xox[baprs]-[A-Za-z0-9\\-]{10,}", .exposedToken, .critical, "Slack token detected"),
        ]

        for (lineNum, line) in lines.enumerated() {
            for (pattern, type, severity, description) in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: line, options: [], range: NSRange(line.startIndex..., in: line)) != nil {
                    findings.append(SecurityFinding(
                        type: type,
                        description: description,
                        lineNumber: lineNum + 1,
                        recommendation: "Remove this credential and use environment variables or a secrets manager instead.",
                        severity: severity
                    ))
                }
            }
        }

        return findings
    }

    // MARK: - Config Security Audit

    /// Comprehensive security audit of configuration files
    func auditConfigSecurity(configs: [ConfigFile]) async -> [SecurityAnalysisResult] {
        guard aiManager.aiEnabled, aiManager.activeBackend != nil else {
            return []
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        var results: [SecurityAnalysisResult] = []

        for config in configs {
            guard let content = try? String(contentsOf: URL(fileURLWithPath: config.path), encoding: .utf8) else {
                continue
            }

            let findings = await auditSingleConfig(content: content, filename: config.filename, filepath: config.path)

            let maxSeverity = findings.map { $0.severity }.max() ?? .none

            results.append(SecurityAnalysisResult(
                filename: config.filename,
                filepath: config.path,
                findings: findings,
                overallRisk: maxSeverity,
                timestamp: Date()
            ))
        }

        lastAnalysisResults = results
        return results
    }

    private func auditSingleConfig(content: String, filename: String, filepath: String) async -> [SecurityFinding] {
        let prompt = """
        Perform a security audit on this configuration file.

        Check for:
        1. CREDENTIALS: Hardcoded secrets, API keys, passwords, tokens
        2. WEAK SETTINGS: Insecure defaults, disabled security features
        3. PERMISSIONS: Overly permissive access settings
        4. DEPRECATED: Outdated/deprecated security options
        5. BEST PRACTICES: Missing security hardening options

        File: \(filename)
        Path: \(filepath)

        Content:
        \(String(content.prefix(4000)))

        For each finding, respond in this exact format (one per line):
        FINDING|<type:credential/weak/permission/deprecated/practice>|<severity:critical/high/medium/low>|<line_number_or_0>|<description>|<recommendation>

        If no issues found, respond with: NO_FINDINGS
        """

        do {
            let response = try await aiManager.generate(
                prompt: prompt,
                systemPrompt: "You are a security auditor reviewing configuration files. Focus on actionable security issues. Be specific about what's wrong and how to fix it.",
                temperature: 0.2,
                maxTokens: 2048
            )

            return parseSecurityFindings(response)
        } catch {
            return []
        }
    }

    // MARK: - Anomaly Detection

    struct AnomalyResult: Identifiable {
        let id = UUID()
        let filename: String
        let changeDescription: String
        let riskAssessment: String
        let isSignificant: Bool
        let recommendation: String
    }

    /// Detect anomalous changes in configuration files
    func detectAnomalies(originalContent: String, newContent: String, filename: String) async -> AnomalyResult? {
        guard aiManager.aiEnabled, aiManager.activeBackend != nil else {
            return detectAnomaliesBasic(originalContent: originalContent, newContent: newContent, filename: filename)
        }

        // Skip if contents are identical
        guard originalContent != newContent else { return nil }

        let prompt = """
        Analyze these configuration file changes for anomalies or suspicious modifications.

        File: \(filename)

        ORIGINAL VERSION:
        \(String(originalContent.prefix(2000)))

        NEW VERSION:
        \(String(newContent.prefix(2000)))

        Check for:
        1. Unexpected security setting changes (disabled protections)
        2. New credentials or tokens added
        3. Significant structural changes
        4. Potential malicious modifications
        5. Corruption indicators

        Respond in this exact format:
        SIGNIFICANT: <yes/no>
        CHANGE_SUMMARY: <brief description of what changed>
        RISK_ASSESSMENT: <none/low/medium/high/critical>
        RECOMMENDATION: <what the user should do>
        """

        do {
            let response = try await aiManager.generate(
                prompt: prompt,
                systemPrompt: "You are a configuration change analyst. Identify potentially problematic changes while avoiding false alarms for normal modifications.",
                temperature: 0.2,
                maxTokens: 1024
            )

            return parseAnomalyResult(response, filename: filename)
        } catch {
            return detectAnomaliesBasic(originalContent: originalContent, newContent: newContent, filename: filename)
        }
    }

    /// Basic anomaly detection without AI
    private func detectAnomaliesBasic(originalContent: String, newContent: String, filename: String) -> AnomalyResult? {
        let originalLines = originalContent.components(separatedBy: .newlines).count
        let newLines = newContent.components(separatedBy: .newlines).count
        let lineDiff = abs(newLines - originalLines)
        let percentChange = originalLines > 0 ? Double(lineDiff) / Double(originalLines) * 100 : 100

        // Flag significant changes (>30% line change)
        if percentChange > 30 {
            return AnomalyResult(
                filename: filename,
                changeDescription: "File changed by \(Int(percentChange))% (\(lineDiff) lines)",
                riskAssessment: percentChange > 50 ? "Medium" : "Low",
                isSignificant: true,
                recommendation: "Review changes carefully before syncing."
            )
        }

        return nil
    }

    // MARK: - Parsing Helpers

    private func parseSecurityFindings(_ response: String) -> [SecurityFinding] {
        if response.contains("NO_FINDINGS") { return [] }

        var findings: [SecurityFinding] = []
        let lines = response.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("FINDING|") {
                let parts = line.components(separatedBy: "|")
                if parts.count >= 6 {
                    let typeStr = parts[1].lowercased()
                    let severityStr = parts[2].lowercased()
                    let lineNum = Int(parts[3]) ?? 0
                    let description = parts[4]
                    let recommendation = parts[5]

                    let type: SecurityFinding.FindingType = {
                        if typeStr.contains("credential") || typeStr.contains("password") { return .hardcodedCredential }
                        if typeStr.contains("base64") { return .base64EncodedSecret }
                        if typeStr.contains("weak") { return .weakConfiguration }
                        if typeStr.contains("token") { return .exposedToken }
                        if typeStr.contains("insecure") || typeStr.contains("practice") { return .insecureSetting }
                        if typeStr.contains("deprecated") { return .deprecatedOption }
                        if typeStr.contains("permission") { return .permissionIssue }
                        return .anomaly
                    }()

                    let severity: SecurityAnalysisResult.RiskLevel = {
                        switch severityStr {
                        case "critical": return .critical
                        case "high": return .high
                        case "medium": return .medium
                        case "low": return .low
                        default: return .medium
                        }
                    }()

                    findings.append(SecurityFinding(
                        type: type,
                        description: description,
                        lineNumber: lineNum > 0 ? lineNum : nil,
                        recommendation: recommendation,
                        severity: severity
                    ))
                }
            }
        }

        return findings
    }

    private func parseAnomalyResult(_ response: String, filename: String) -> AnomalyResult? {
        var isSignificant = false
        var changeSummary = ""
        var riskAssessment = "Low"
        var recommendation = "Review changes before syncing."

        for line in response.components(separatedBy: .newlines) {
            if line.uppercased().hasPrefix("SIGNIFICANT:") {
                isSignificant = line.lowercased().contains("yes")
            } else if line.uppercased().hasPrefix("CHANGE_SUMMARY:") {
                changeSummary = line.replacingOccurrences(of: "CHANGE_SUMMARY:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().hasPrefix("RISK_ASSESSMENT:") {
                riskAssessment = line.replacingOccurrences(of: "RISK_ASSESSMENT:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().hasPrefix("RECOMMENDATION:") {
                recommendation = line.replacingOccurrences(of: "RECOMMENDATION:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            }
        }

        guard !changeSummary.isEmpty else { return nil }

        return AnomalyResult(
            filename: filename,
            changeDescription: changeSummary,
            riskAssessment: riskAssessment,
            isSignificant: isSignificant,
            recommendation: recommendation
        )
    }
}
