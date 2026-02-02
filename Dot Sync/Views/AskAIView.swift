//
//  AskAIView.swift
//  Dot Sync
//
//  Chat interface for AI-powered configuration assistance
//  Features: Config Q&A, Diff Explanation, Troubleshooting
//  Author: Jordan Koch
//

import SwiftUI

struct AskAIView: View {
    @ObservedObject var aiManager = AIBackendManager.shared
    @ObservedObject var configAssistant = AIConfigAssistant.shared
    @ObservedObject var securityAnalyzer = AISecurityAnalyzer.shared
    @ObservedObject var mergeAssistant = AIMergeAssistant.shared
    @ObservedObject var configInsights = AIConfigInsights.shared

    let configs: [ConfigFile]

    @State private var question = ""
    @State private var chatHistory: [ChatMessage] = []
    @State private var isQuerying = false
    @State private var showQuickActions = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Chat area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Welcome message if empty
                        if chatHistory.isEmpty {
                            welcomeCard
                        }

                        // Chat messages
                        ForEach(chatHistory) { message in
                            chatMessageView(message)
                                .id(message.id)
                        }

                        // Typing indicator
                        if isQuerying {
                            typingIndicator
                        }
                    }
                    .padding()
                }
                .onChange(of: chatHistory.count) { _ in
                    if let lastId = chatHistory.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Quick actions (collapsible)
            if showQuickActions && !isQuerying {
                quickActionsBar
            }

            // Input area
            inputArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ask AI")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    // AI Status
                    Circle()
                        .fill(aiManager.activeBackend != nil ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(aiManager.activeBackend?.rawValue ?? "AI Offline")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text("\(configs.count) configs loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button(action: { showQuickActions.toggle() }) {
                    Image(systemName: showQuickActions ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                }
                .buttonStyle(.borderless)
                .help("Toggle quick actions")

                Button(action: clearChat) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(chatHistory.isEmpty)
                .help("Clear conversation")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Welcome Card

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("AI Configuration Assistant")
                    .font(.headline)
            }

            Text("Ask questions about your configuration files in natural language.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Try asking:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(sampleQuestions, id: \.self) { q in
                    Button(action: { askQuestion(q) }) {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                                .font(.caption)
                            Text(q)
                                .font(.callout)
                        }
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
        )
    }

    private var sampleQuestions: [String] {
        [
            "Where is my AWS region configured?",
            "What git aliases do I have?",
            "Check my configs for security issues",
            "What shell plugins am I using?",
            "Explain the differences in my .zshrc"
        ]
    }

    // MARK: - Chat Message View

    private func chatMessageView(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isUser {
                Spacer()
                userMessageBubble(message)
            } else {
                aiMessageBubble(message)
                Spacer()
            }
        }
    }

    private func userMessageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(message.content)
                .padding(12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(16)

            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: 400, alignment: .trailing)
    }

    private func aiMessageBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .textSelection(.enabled)

                    // Show sources if available
                    if !message.sources.isEmpty {
                        sourcesSection(message.sources)
                    }

                    // Show action buttons if applicable
                    if let action = message.suggestedAction {
                        actionButton(action)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)

            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: 500, alignment: .leading)
    }

    private func sourcesSection(_ sources: [ChatMessage.Source]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources:")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(sources) { source in
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                    Text(source.filename)
                        .font(.caption)
                    if let line = source.lineNumber {
                        Text("(line \(line))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.blue)
            }
        }
        .padding(.top, 4)
    }

    private func actionButton(_ action: ChatMessage.SuggestedAction) -> some View {
        Button(action: { performAction(action) }) {
            HStack {
                Image(systemName: action.icon)
                Text(action.title)
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .foregroundColor(.purple)
            Text("Thinking...")
                .foregroundColor(.secondary)
            ProgressView()
                .scaleEffect(0.7)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }

    // MARK: - Quick Actions Bar

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickActionButton("🔒 Security Scan", action: runSecurityScan)
                quickActionButton("🏥 Health Check", action: runHealthCheck)
                quickActionButton("💡 Best Practices", action: suggestBestPractices)
                quickActionButton("🔍 Find Setting", action: findSetting)
                quickActionButton("⚡ Shell Analysis", action: analyzeShell)
                quickActionButton("🗑️ Unused Configs", action: findUnused)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func quickActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Ask about your configs...", text: $question)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .onSubmit {
                    if !question.isEmpty {
                        askQuestion(question)
                    }
                }

            Button(action: {
                if !question.isEmpty {
                    askQuestion(question)
                }
            }) {
                Image(systemName: "paperplane.fill")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .disabled(question.isEmpty || isQuerying)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Actions

    private func askQuestion(_ q: String) {
        let userMessage = ChatMessage(
            content: q,
            isUser: true,
            timestamp: Date()
        )
        chatHistory.append(userMessage)
        question = ""

        isQuerying = true

        Task {
            let response = await processQuestion(q)
            await MainActor.run {
                chatHistory.append(response)
                isQuerying = false
            }
        }
    }

    private func processQuestion(_ q: String) async -> ChatMessage {
        let lowercaseQ = q.lowercased()

        // Route to appropriate handler
        if lowercaseQ.contains("security") || lowercaseQ.contains("secret") || lowercaseQ.contains("credential") {
            return await handleSecurityQuestion(q)
        } else if lowercaseQ.contains("health") || lowercaseQ.contains("check") || lowercaseQ.contains("issue") {
            return await handleHealthQuestion(q)
        } else if lowercaseQ.contains("best practice") || lowercaseQ.contains("recommend") || lowercaseQ.contains("suggest") {
            return await handleBestPracticesQuestion(q)
        } else if lowercaseQ.contains("shell") || lowercaseQ.contains("zsh") || lowercaseQ.contains("bash") || lowercaseQ.contains("slow") {
            return await handleShellQuestion(q)
        } else if lowercaseQ.contains("diff") || lowercaseQ.contains("change") || lowercaseQ.contains("different") {
            return await handleDiffQuestion(q)
        } else {
            // General search/Q&A
            return await handleGeneralQuestion(q)
        }
    }

    private func handleSecurityQuestion(_ q: String) async -> ChatMessage {
        var findings: [AISecurityAnalyzer.SecurityFinding] = []

        for config in configs {
            if let content = try? String(contentsOf: URL(fileURLWithPath: config.path), encoding: .utf8) {
                let configFindings = await securityAnalyzer.detectCredentials(in: content, filename: config.filename)
                findings.append(contentsOf: configFindings)
            }
        }

        if findings.isEmpty {
            return ChatMessage(
                content: "✅ No security issues found! Your configuration files look clean.",
                isUser: false,
                timestamp: Date()
            )
        }

        let critical = findings.filter { $0.severity == .critical }.count
        let high = findings.filter { $0.severity == .high }.count

        var response = "🔒 **Security Scan Results**\n\n"
        response += "Found \(findings.count) potential issues"
        if critical > 0 { response += " (\(critical) critical)" }
        if high > 0 { response += " (\(high) high priority)" }
        response += ".\n\n"

        for finding in findings.prefix(5) {
            response += "• **\(finding.type.rawValue)** (\(finding.severity.rawValue)): \(finding.description)\n"
            response += "  💡 \(finding.recommendation)\n\n"
        }

        if findings.count > 5 {
            response += "\n...and \(findings.count - 5) more issues."
        }

        return ChatMessage(
            content: response,
            isUser: false,
            timestamp: Date()
        )
    }

    private func handleHealthQuestion(_ q: String) async -> ChatMessage {
        let report = await configInsights.runHealthCheck(configs: configs)

        var response = "🏥 **Configuration Health Report**\n\n"
        response += "Overall Score: **\(report.overallScore)/100**\n"
        response += report.summary + "\n\n"

        for result in report.configResults.prefix(5) where result.status != .healthy {
            response += "**\(result.filename)** (\(result.status.rawValue))\n"
            for issue in result.issues.prefix(3) {
                response += "  • \(issue.severity.rawValue): \(issue.description)\n"
            }
            response += "\n"
        }

        return ChatMessage(
            content: response,
            isUser: false,
            timestamp: Date()
        )
    }

    private func handleBestPracticesQuestion(_ q: String) async -> ChatMessage {
        var allRecs: [AIConfigInsights.Recommendation] = []

        for config in configs.prefix(5) {
            let recs = await configInsights.suggestBestPractices(for: config)
            allRecs.append(contentsOf: recs)
        }

        if allRecs.isEmpty {
            return ChatMessage(
                content: "✨ Your configurations follow best practices! No recommendations at this time.",
                isUser: false,
                timestamp: Date()
            )
        }

        var response = "💡 **Best Practice Recommendations**\n\n"

        let sorted = allRecs.sorted { $0.priority > $1.priority }
        for rec in sorted.prefix(5) {
            response += "**\(rec.title)** (\(rec.filename))\n"
            response += "\(rec.description)\n"
            if let change = rec.suggestedChange {
                response += "```\n\(change)\n```\n"
            }
            response += "\n"
        }

        return ChatMessage(
            content: response,
            isUser: false,
            timestamp: Date()
        )
    }

    private func handleShellQuestion(_ q: String) async -> ChatMessage {
        let shellConfigs = configs.filter {
            $0.filename.contains("zshrc") || $0.filename.contains("bashrc") || $0.filename.contains("bash_profile")
        }

        guard let shellConfig = shellConfigs.first,
              let content = try? String(contentsOf: URL(fileURLWithPath: shellConfig.path), encoding: .utf8) else {
            return ChatMessage(
                content: "No shell configuration files found.",
                isUser: false,
                timestamp: Date()
            )
        }

        let analysis = await configInsights.analyzeShellConfig(content: content, filename: shellConfig.filename)

        var response = "⚡ **Shell Configuration Analysis** (\(shellConfig.filename))\n\n"

        if let startup = analysis.startupTime {
            response += "Startup Impact: **\(startup)**\n\n"
        }

        if analysis.issues.isEmpty {
            response += "✅ No issues found! Your shell config looks optimized.\n"
        } else {
            response += "**Issues Found:**\n"
            for issue in analysis.issues {
                response += "• \(issue.type.rawValue): \(issue.description)\n"
                response += "  💡 \(issue.suggestion)\n\n"
            }
        }

        if !analysis.optimizations.isEmpty {
            response += "\n**Optimizations:**\n"
            for opt in analysis.optimizations {
                response += "• \(opt)\n"
            }
        }

        return ChatMessage(
            content: response,
            isUser: false,
            timestamp: Date()
        )
    }

    private func handleDiffQuestion(_ q: String) async -> ChatMessage {
        return ChatMessage(
            content: "To explain differences between config versions, please select two files or a file with conflicts in the main view. I can then analyze what changed and explain the impact.",
            isUser: false,
            timestamp: Date()
        )
    }

    private func handleGeneralQuestion(_ q: String) async -> ChatMessage {
        // Use natural language search
        let results = await configAssistant.search(query: q, in: configs)

        if results.isEmpty {
            // Fall back to AI generation
            return await generateAIResponse(q)
        }

        var response = "🔍 **Found \(results.count) match\(results.count == 1 ? "" : "es"):**\n\n"

        let sources = results.prefix(5).map { result in
            ChatMessage.Source(filename: result.filename, lineNumber: result.lineNumber)
        }

        for result in results.prefix(5) {
            response += "**\(result.filename)**"
            if let line = result.lineNumber {
                response += " (line \(line))"
            }
            response += "\n```\n\(result.matchedContent)\n```\n\n"
        }

        return ChatMessage(
            content: response,
            isUser: false,
            timestamp: Date(),
            sources: Array(sources)
        )
    }

    private func generateAIResponse(_ q: String) async -> ChatMessage {
        guard aiManager.aiEnabled, aiManager.activeBackend != nil else {
            return ChatMessage(
                content: "I couldn't find specific information for your question. Please try a more specific search term, or ensure an AI backend is connected for more advanced queries.",
                isUser: false,
                timestamp: Date()
            )
        }

        // Build context from configs
        var context = "Available configuration files:\n"
        for config in configs.prefix(10) {
            if let content = try? String(contentsOf: URL(fileURLWithPath: config.path), encoding: .utf8) {
                context += "\n--- \(config.filename) ---\n\(String(content.prefix(500)))\n"
            }
        }

        let prompt = """
        Question about configuration files: \(q)

        \(context)

        Provide a helpful, concise answer based on the configuration content shown.
        """

        do {
            let response = try await aiManager.generate(
                prompt: prompt,
                systemPrompt: "You are a helpful assistant answering questions about developer configuration files. Be concise and specific. If you can't answer from the given context, say so.",
                temperature: 0.3,
                maxTokens: 1024
            )

            return ChatMessage(
                content: response,
                isUser: false,
                timestamp: Date()
            )
        } catch {
            return ChatMessage(
                content: "I encountered an error processing your question. Please try again.",
                isUser: false,
                timestamp: Date()
            )
        }
    }

    // MARK: - Quick Action Handlers

    private func runSecurityScan() {
        askQuestion("Run a security scan on all my config files")
    }

    private func runHealthCheck() {
        askQuestion("Check the health of my configuration files")
    }

    private func suggestBestPractices() {
        askQuestion("What best practices should I follow for my configs?")
    }

    private func findSetting() {
        question = "Where is "
    }

    private func analyzeShell() {
        askQuestion("Analyze my shell configuration for performance issues")
    }

    private func findUnused() {
        askQuestion("Are there any unused configuration files?")
    }

    private func performAction(_ action: ChatMessage.SuggestedAction) {
        // Handle action button presses
        switch action.type {
        case .openFile:
            if let path = action.data {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            }
        case .runScan:
            runSecurityScan()
        case .applyFix:
            askQuestion("Apply the suggested fix")
        }
    }

    private func clearChat() {
        chatHistory.removeAll()
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
    var sources: [Source] = []
    var suggestedAction: SuggestedAction?

    struct Source: Identifiable {
        let id = UUID()
        let filename: String
        let lineNumber: Int?
    }

    struct SuggestedAction {
        let type: ActionType
        let title: String
        let icon: String
        let data: String?

        enum ActionType {
            case openFile
            case runScan
            case applyFix
        }
    }
}

// MARK: - Preview

#Preview {
    AskAIView(configs: [])
}
