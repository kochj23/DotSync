//
//  AIFeaturesDashboard.swift
//  Dot Sync
//
//  Dashboard for all AI-powered features
//  Author: Jordan Koch
//

import SwiftUI

struct AIFeaturesDashboard: View {
    @ObservedObject var aiManager = AIBackendManager.shared
    @ObservedObject var securityAnalyzer = AISecurityAnalyzer.shared
    @ObservedObject var mergeAssistant = AIMergeAssistant.shared
    @ObservedObject var configInsights = AIConfigInsights.shared
    @ObservedObject var configAssistant = AIConfigAssistant.shared

    let configs: [ConfigFile]
    @Binding var selectedTab: AITab

    enum AITab: String, CaseIterable {
        case askAI = "Ask AI"
        case security = "Security"
        case insights = "Insights"
        case merge = "Merge"
    }

    @State private var isRunningAnalysis = false
    @State private var analysisProgress: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // AI Status Header
            aiStatusHeader

            Divider()

            // Tab Selector
            tabSelector

            Divider()

            // Content based on selected tab
            Group {
                switch selectedTab {
                case .askAI:
                    AskAIView(configs: configs)
                case .security:
                    securityView
                case .insights:
                    insightsView
                case .merge:
                    mergeView
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - AI Status Header

    private var aiStatusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .foregroundColor(.purple)
                    Text("AI Features")
                        .font(.headline)
                }

                HStack(spacing: 12) {
                    // Backend status
                    HStack(spacing: 4) {
                        Circle()
                            .fill(aiManager.activeBackend != nil ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(aiManager.activeBackend?.rawValue ?? "No AI Backend")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if aiManager.activeBackend != nil {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(configs.count) configs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if isRunningAnalysis {
                        Text("•")
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(analysisProgress)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }

            Spacer()

            // Quick actions
            if aiManager.activeBackend != nil {
                Button(action: runFullAnalysis) {
                    Label("Full Analysis", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .disabled(isRunningAnalysis)
            } else {
                Button(action: { Task { await aiManager.checkBackendAvailability() } }) {
                    Label("Connect AI", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(AITab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func tabButton(_ tab: AITab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 6) {
                Image(systemName: iconForTab(tab))
                Text(tab.rawValue)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == tab ? Color.blue : Color.clear)
            )
            .foregroundColor(selectedTab == tab ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func iconForTab(_ tab: AITab) -> String {
        switch tab {
        case .askAI: return "bubble.left.and.bubble.right"
        case .security: return "lock.shield"
        case .insights: return "chart.bar.xaxis"
        case .merge: return "arrow.triangle.merge"
        }
    }

    // MARK: - Security View

    private var securityView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Security scan section
                sectionHeader("Security Scan", icon: "lock.shield")

                if securityAnalyzer.isAnalyzing {
                    HStack {
                        ProgressView()
                        Text("Scanning configurations...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if securityAnalyzer.lastAnalysisResults.isEmpty {
                    emptyStateCard(
                        icon: "shield.checkered",
                        title: "No Scan Results",
                        message: "Run a security scan to check your configs for credentials and security issues.",
                        action: ("Run Security Scan", runSecurityScan)
                    )
                } else {
                    // Show results
                    ForEach(securityAnalyzer.lastAnalysisResults) { result in
                        securityResultCard(result)
                    }
                }

                Divider()
                    .padding(.vertical)

                // Anomaly detection section
                sectionHeader("Anomaly Detection", icon: "exclamationmark.triangle")

                Text("Anomaly detection monitors your config files for unexpected changes that could indicate corruption or unauthorized modifications.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .padding()
        }
    }

    private func securityResultCard(_ result: AISecurityAnalyzer.SecurityAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.filename)
                    .font(.headline)

                Spacer()

                riskBadge(result.overallRisk)
            }

            if result.findings.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No issues found")
                        .foregroundColor(.green)
                }
            } else {
                ForEach(result.findings.prefix(3)) { finding in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: severityIcon(finding.severity))
                            .foregroundColor(severityColor(finding.severity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.description)
                                .font(.callout)
                            Text(finding.recommendation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if result.findings.count > 3 {
                    Text("+ \(result.findings.count - 3) more issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Insights View

    private var insightsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Health check section
                sectionHeader("Configuration Health", icon: "heart.text.square")

                if configInsights.isAnalyzing {
                    HStack {
                        ProgressView()
                        Text("Analyzing configurations...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if let report = configInsights.lastHealthReport {
                    healthReportCard(report)
                } else {
                    emptyStateCard(
                        icon: "stethoscope",
                        title: "No Health Report",
                        message: "Run a health check to identify issues in your configurations.",
                        action: ("Run Health Check", runHealthCheck)
                    )
                }

                Divider()
                    .padding(.vertical)

                // Recommendations section
                sectionHeader("Recommendations", icon: "lightbulb")

                if configInsights.recommendations.isEmpty {
                    emptyStateCard(
                        icon: "sparkles",
                        title: "No Recommendations Yet",
                        message: "Get AI-powered suggestions to improve your configurations.",
                        action: ("Get Recommendations", getBestPractices)
                    )
                } else {
                    ForEach(configInsights.recommendations.prefix(5)) { rec in
                        recommendationCard(rec)
                    }
                }
            }
            .padding()
        }
    }

    private func healthReportCard(_ report: AIConfigInsights.HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Score circle
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: Double(report.overallScore) / 100)
                        .stroke(scoreColor(report.overallScore), lineWidth: 8)
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    Text("\(report.overallScore)")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall Health Score")
                        .font(.headline)
                    Text(report.summary)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            // Individual config results
            ForEach(report.configResults.prefix(5)) { result in
                HStack {
                    statusIcon(result.status)
                    Text(result.filename)
                        .font(.callout)
                    Spacer()
                    Text("\(result.score)/100")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func recommendationCard(_ rec: AIConfigInsights.Recommendation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: categoryIcon(rec.category))
                .foregroundColor(categoryColor(rec.category))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rec.title)
                        .font(.callout)
                        .fontWeight(.medium)
                    Spacer()
                    priorityBadge(rec.priority)
                }

                Text(rec.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(rec.filename)
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Merge View

    private var mergeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("AI Merge Assistant", icon: "arrow.triangle.merge")

                if mergeAssistant.isProcessing {
                    HStack {
                        ProgressView()
                        Text("Analyzing merge...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if let suggestion = mergeAssistant.lastMergeSuggestion {
                    mergeSuggestionCard(suggestion)
                } else {
                    emptyStateCard(
                        icon: "arrow.triangle.branch",
                        title: "No Merge Conflicts",
                        message: "When conflicts occur during sync, the AI will help you resolve them intelligently.",
                        action: nil
                    )
                }

                Divider()
                    .padding(.vertical)

                // Features explanation
                sectionHeader("Merge Features", icon: "info.circle")

                featureCard(
                    icon: "brain",
                    title: "AI Merge Suggestions",
                    description: "Get intelligent recommendations on how to resolve conflicts based on file content and context."
                )

                featureCard(
                    icon: "doc.text.magnifyingglass",
                    title: "Semantic Merging",
                    description: "AI understands config file syntax and merges sections intelligently instead of line-by-line."
                )

                featureCard(
                    icon: "text.bubble",
                    title: "Change Explanations",
                    description: "Get plain-English explanations of what changed between versions and the potential impact."
                )
            }
            .padding()
        }
    }

    private func mergeSuggestionCard(_ suggestion: AIMergeAssistant.MergeSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(suggestion.filename)
                    .font(.headline)
                Spacer()
                Text(suggestion.recommendation.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.2)))
            }

            Text(suggestion.reasoning)
                .font(.callout)

            HStack {
                Text("Confidence: \(Int(suggestion.confidence * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !suggestion.warnings.isEmpty {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("\(suggestion.warnings.count) warning(s)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Helper Views

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
        }
    }

    private func emptyStateCard(icon: String, title: String, message: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let action = action {
                Button(action: action.1) {
                    Text(action.0)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func featureCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.purple)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func riskBadge(_ risk: AISecurityAnalyzer.SecurityAnalysisResult.RiskLevel) -> some View {
        Text(risk.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(riskColor(risk).opacity(0.2)))
            .foregroundColor(riskColor(risk))
    }

    private func priorityBadge(_ priority: AIConfigInsights.Recommendation.Priority) -> some View {
        Text(priority.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(priorityColor(priority).opacity(0.2)))
            .foregroundColor(priorityColor(priority))
    }

    private func statusIcon(_ status: AIConfigInsights.HealthReport.HealthStatus) -> some View {
        Image(systemName: {
            switch status {
            case .healthy: return "checkmark.circle.fill"
            case .needsAttention: return "exclamationmark.circle.fill"
            case .problematic: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }())
        .foregroundColor({
            switch status {
            case .healthy: return .green
            case .needsAttention: return .yellow
            case .problematic: return .red
            case .unknown: return .gray
            }
        }())
    }

    // MARK: - Colors

    private func riskColor(_ risk: AISecurityAnalyzer.SecurityAnalysisResult.RiskLevel) -> Color {
        switch risk {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        case .none: return .green
        }
    }

    private func severityColor(_ severity: AISecurityAnalyzer.SecurityAnalysisResult.RiskLevel) -> Color {
        riskColor(severity)
    }

    private func severityIcon(_ severity: AISecurityAnalyzer.SecurityAnalysisResult.RiskLevel) -> String {
        switch severity {
        case .critical: return "exclamationmark.octagon.fill"
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "info.circle.fill"
        case .none: return "checkmark.circle.fill"
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 90 { return .green }
        if score >= 70 { return .yellow }
        if score >= 50 { return .orange }
        return .red
    }

    private func priorityColor(_ priority: AIConfigInsights.Recommendation.Priority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    private func categoryIcon(_ category: AIConfigInsights.Recommendation.RecommendationCategory) -> String {
        switch category {
        case .security: return "lock.shield"
        case .performance: return "bolt"
        case .bestPractice: return "star"
        case .modernization: return "sparkles"
        case .cleanup: return "trash"
        }
    }

    private func categoryColor(_ category: AIConfigInsights.Recommendation.RecommendationCategory) -> Color {
        switch category {
        case .security: return .red
        case .performance: return .orange
        case .bestPractice: return .blue
        case .modernization: return .purple
        case .cleanup: return .gray
        }
    }

    // MARK: - Actions

    private func runFullAnalysis() {
        isRunningAnalysis = true
        analysisProgress = "Starting..."

        Task {
            // Security scan
            await MainActor.run { analysisProgress = "Security scan..." }
            _ = await securityAnalyzer.auditConfigSecurity(configs: configs)

            // Health check
            await MainActor.run { analysisProgress = "Health check..." }
            _ = await configInsights.runHealthCheck(configs: configs)

            // Best practices
            await MainActor.run { analysisProgress = "Best practices..." }
            for config in configs.prefix(5) {
                let recs = await configInsights.suggestBestPractices(for: config)
                await MainActor.run {
                    configInsights.recommendations.append(contentsOf: recs)
                }
            }

            await MainActor.run {
                isRunningAnalysis = false
                analysisProgress = ""
            }
        }
    }

    private func runSecurityScan() {
        Task {
            _ = await securityAnalyzer.auditConfigSecurity(configs: configs)
        }
    }

    private func runHealthCheck() {
        Task {
            _ = await configInsights.runHealthCheck(configs: configs)
        }
    }

    private func getBestPractices() {
        Task {
            for config in configs.prefix(5) {
                let recs = await configInsights.suggestBestPractices(for: config)
                await MainActor.run {
                    configInsights.recommendations.append(contentsOf: recs)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AIFeaturesDashboard(configs: [], selectedTab: .constant(.askAI))
}
