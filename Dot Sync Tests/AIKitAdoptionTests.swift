//
//  AIKitAdoptionTests.swift
//  Dot Sync Tests
//
//  Dot Sync's contract with NovaAIKit 1.0.0, grouped in the 7 QE categories (security, performance, retry, unit,
//  integration, functional, frame/UI-state). NovaAIKit's own suite covers backends, transport and the Keychain;
//  these cover Dot Sync's prompts → validators → fallbacks. No real network and no real Keychain: every NovaAI here
//  uses an in-memory settings store, an in-memory key store and a stubbed URLSession.
//  Author: Jordan Koch
//

import XCTest
import SwiftUI
import NovaAIKit
@testable import Dot_Sync

// MARK: - Test support

/// Canned replies by URL path. Anything without a reply fails with "cannot connect" (offline).
final class DotSyncAIStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var replies: [String] = []          // successive /api/chat reply texts
    private static var statuses: [Int] = []            // successive /api/chat HTTP statuses (default 200)
    private static var chatCount = 0
    private static var authHeaders: [String] = []

    static func reset(replies r: [String] = [], statuses s: [Int] = []) {
        lock.lock(); replies = r; statuses = s; chatCount = 0; authHeaders = []; lock.unlock()
    }
    static var chatRequests: Int { lock.lock(); defer { lock.unlock() }; return chatCount }
    static var authorizationHeaders: [String] { lock.lock(); defer { lock.unlock() }; return authHeaders }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let path = url.path
        Self.lock.lock()
        if let auth = request.value(forHTTPHeaderField: "Authorization") { Self.authHeaders.append(auth) }
        var body: String?
        var status = 200
        if path.hasSuffix("/api/tags") {
            body = #"{"models":[{"name":"qwen3:8b"}]}"#
        } else if path.hasSuffix("/api/chat") || path.hasSuffix("/chat/completions") {
            let i = Self.chatCount
            Self.chatCount += 1
            if i < Self.statuses.count { status = Self.statuses[i] }
            if !Self.replies.isEmpty {
                let text = Self.replies[min(i, Self.replies.count - 1)]
                let quoted = String(data: try! JSONSerialization.data(withJSONObject: [text]), encoding: .utf8)!.dropFirst().dropLast()
                body = #"{"model":"qwen3:8b","message":{"role":"assistant","content":\#(quoted)},"done":true}"#
            }
        }
        Self.lock.unlock()
        guard let body else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((status == 200 ? body : "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
enum DotSyncAITest {
    /// A NovaAI wired to the stub. Default settings: AI on, Ollama only (deterministic, no failover chain).
    static func makeAI(_ settings: NovaAISettings = NovaAISettings(backend: .ollama),
                       keys: NovaAIMemoryKeyStore = NovaAIMemoryKeyStore()) -> NovaAI {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [DotSyncAIStub.self]
        return NovaAI(configuration: AppAI.configuration,
                      storage: NovaAIMemoryStorage(settings), keyStore: keys,
                      session: URLSession(configuration: cfg), sleep: { _ in })
    }
    static var off: NovaAISettings { NovaAISettings(enabled: false, backend: .ollama) }

    /// A throwaway UserDefaults suite.
    static func suite(_ name: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: "DotSyncAITests.\(name)")!
        d.removePersistentDomain(forName: "DotSyncAITests.\(name)")
        return d
    }

    /// A config file on disk (for the features that read files).
    static func configFile(_ name: String, _ content: String) throws -> ConfigFile {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DotSyncAITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return ConfigFile(path: url.path, relativePath: name, filename: name, category: .shell, size: Int64(content.utf8.count),
                          lastModified: Date(), checksum: "x", isSafeToSync: true, syncPriority: .medium, isDirectory: false)
    }

    static let secretConfig = "export PATH=/usr/bin\nAWS_KEY=AKIAABCDEFGHIJKLMNOP\npassword = hunter2\n"
    static let shellConfig = "export NVM_DIR=~/.nvm\nsource $NVM_DIR/nvm.sh\nalias ll='ls -l'\nalias ll='ls -la'\n"
}

/// One sweep over every Dot Sync AI feature; asserts each produced its built-in result.
@MainActor
private func assertEveryFeatureUsesBuiltIn(_ ai: NovaAI, file: StaticString = #filePath, line: UInt = #line) async throws {
    let security = AISecurityAnalyzer(ai: ai)
    let merge = AIMergeAssistant(ai: ai)
    let insights = AIConfigInsights(ai: ai)
    let assistant = AIConfigAssistant(ai: ai, userDefaults: DotSyncAITest.suite())

    let findings = await security.detectCredentials(in: DotSyncAITest.secretConfig, filename: ".env")
    XCTAssertTrue(findings.contains { $0.description.contains("AWS Access Key") }, "regex scan", file: file, line: line)
    XCTAssertEqual(security.lastSource?.isAI, false, file: file, line: line)

    let secretFile = try DotSyncAITest.configFile(".netrc", DotSyncAITest.secretConfig)
    let audit = await security.auditConfigSecurity(configs: [secretFile])
    XCTAssertEqual(audit.count, 1, file: file, line: line)
    XCTAssertFalse(audit[0].findings.isEmpty, "audit falls back to the regex scan", file: file, line: line)

    let anomaly = await security.detectAnomalies(originalContent: "a\n", newContent: "a\nb\nc\nd\n", filename: ".zshrc")
    XCTAssertEqual(anomaly?.isSignificant, true, file: file, line: line)

    let suggestion = await merge.suggestMergeResolution(localContent: "a\nb", remoteContent: "a\nc", ancestorContent: nil, filename: ".gitconfig")
    XCTAssertEqual(suggestion.recommendation, .manualReview, file: file, line: line)

    let semantic = await merge.semanticMerge(localContent: "a\nb", remoteContent: "a\nb", filename: ".zshrc")
    XCTAssertTrue(semantic.success, file: file, line: line)
    XCTAssertEqual(semantic.mergedContent, "a\nb", file: file, line: line)

    let explanation = await merge.explainChanges(originalContent: "a", newContent: "a\nb", filename: ".vimrc")
    XCTAssertEqual(explanation.summary, "File has 1 additions and 0 deletions.", file: file, line: line)

    let health = await insights.runHealthCheck(configs: [try DotSyncAITest.configFile(".zshrc", "alias x=y \n")])
    XCTAssertEqual(health.configResults.first?.issues.first?.description, "Trailing whitespace", file: file, line: line)

    let recs = await insights.suggestBestPractices(for: try DotSyncAITest.configFile(".gitconfig", "[user]\n"))
    XCTAssertEqual(recs.first?.title, "Enable commit signing", file: file, line: line)

    let shell = await insights.analyzeShellConfig(content: DotSyncAITest.shellConfig, filename: ".zshrc")
    XCTAssertTrue(shell.issues.contains { $0.type == .slowStartup }, file: file, line: line)
    XCTAssertTrue(shell.issues.contains { $0.type == .redundantAlias }, file: file, line: line)

    let search = await assistant.search(query: "nvm", in: [try DotSyncAITest.configFile(".zshrc", DotSyncAITest.shellConfig)])
    XCTAssertFalse(search.isEmpty, "keyword search still works", file: file, line: line)
    XCTAssertTrue(search.allSatisfy { $0.matchType == .exactMatch }, file: file, line: line)

    let generated = await assistant.generateConfig(description: "add an alias", targetFile: ".zshrc", existingContent: nil)
    XCTAssertNil(generated, "generation needs AI: nil = 'AI unavailable'", file: file, line: line)
    let plan = await assistant.createMigrationPlan(sourceFile: ".bashrc", sourceContent: "alias a=b", targetTool: "zsh")
    XCTAssertNil(plan, file: file, line: line)

    let cfg = try DotSyncAITest.configFile(".zshrc", "x")
    let priorities = await assistant.suggestPriorities(for: [cfg])
    XCTAssertEqual(priorities[cfg.path], .medium, "learned priority only", file: file, line: line)
}

// MARK: - 1. Security

@MainActor
final class AIKitSecurityTests: XCTestCase {
    override func setUp() { DotSyncAIStub.reset() }

    func testKeychainServiceNames() {
        let c = AppAI.configuration
        XCTAssertEqual(c.appID, "dotsync")
        XCTAssertEqual(c.keychainService(for: .openAI), "com.jkoch.dotsync.openai")
        XCTAssertEqual(c.keychainService(for: .openRouter), "com.jkoch.dotsync.openrouter")
        XCTAssertEqual(NovaAIConfiguration.keychainAccount, "apiKey")
    }

    func testLegacyKeychainItemMovesAndObsoleteCloudSecretsAreDeleted() {
        let store = NovaAIMemoryKeyStore()
        XCTAssertTrue(store.write("sk-legacy-test", service: AppAI.legacyKeychainService, account: "openAIAPIKey"))
        XCTAssertTrue(store.write("g", service: AppAI.legacyKeychainService, account: "googleCloudAPIKey"))
        XCTAssertTrue(store.write("a", service: AppAI.legacyKeychainService, account: "AIBackend_AWS_SecretKey"))
        let ai = DotSyncAITest.makeAI(keys: store)

        AppAI.migrateLegacy(ai, defaults: DotSyncAITest.suite())

        XCTAssertTrue(ai.hasAPIKey(for: .openAI))
        XCTAssertEqual(store.read(service: "com.jkoch.dotsync.openai", account: "apiKey"), "sk-legacy-test")
        XCTAssertNil(store.read(service: AppAI.legacyKeychainService, account: "openAIAPIKey"), "old item deleted after verified copy")
        XCTAssertNil(store.read(service: AppAI.legacyKeychainService, account: "googleCloudAPIKey"))
        XCTAssertNil(store.read(service: AppAI.legacyKeychainService, account: "AIBackend_AWS_SecretKey"))
        XCTAssertEqual(store.count, 1)
    }

    func testPlaintextKeyInUserDefaultsMovesToKeychain() {
        let defaults = DotSyncAITest.suite()
        defaults.set("sk-plaintext-test", forKey: NovaAILegacySettings.openAIKeyKeys[0])
        defaults.set("legacy-google", forKey: "AIBackend_GoogleCloud_Key")
        let store = NovaAIMemoryKeyStore()
        let ai = DotSyncAITest.makeAI(keys: store)

        AppAI.migrateLegacy(ai, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: NovaAILegacySettings.openAIKeyKeys[0]), "no plaintext key left in UserDefaults")
        XCTAssertNil(defaults.object(forKey: "AIBackend_GoogleCloud_Key"))
        XCTAssertEqual(store.read(service: "com.jkoch.dotsync.openai", account: "apiKey"), "sk-plaintext-test")
    }

    func testMigrationIsIdempotent() {
        let store = NovaAIMemoryKeyStore()
        _ = store.write("sk-1", service: AppAI.legacyKeychainService, account: "openAIAPIKey")
        let ai = DotSyncAITest.makeAI(keys: store)
        let defaults = DotSyncAITest.suite()
        AppAI.migrateLegacy(ai, defaults: defaults)
        AppAI.migrateLegacy(ai, defaults: defaults)
        XCTAssertEqual(store.count, 1)
    }

    func testKeyIsNeverSentOverPlainHTTP() async {
        var s = NovaAISettings(backend: .openAI)
        s.setURL("http://example.invalid/v1", for: .openAI)
        let ai = DotSyncAITest.makeAI(s)
        ai.setAPIKey("sk-should-not-leak", for: .openAI)
        DotSyncAIStub.reset(replies: ["NO_FINDINGS"])

        let findings = await AISecurityAnalyzer(ai: ai).detectCredentials(in: DotSyncAITest.secretConfig, filename: ".env")

        XCTAssertFalse(findings.isEmpty, "built-in regex result")
        XCTAssertTrue(DotSyncAIStub.authorizationHeaders.isEmpty, "no Authorization header went out over http")
    }

    func testSettingsHoldNoSecrets() throws {
        let ai = DotSyncAITest.makeAI()
        ai.setAPIKey("sk-secret-test", for: .openAI)
        let json = String(data: try JSONEncoder().encode(ai.settings), encoding: .utf8)!
        XCTAssertFalse(json.contains("sk-secret-test"))
    }

    func testNoLegacyAIClientInSources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Dot Sync")
        guard let e = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            throw XCTSkip("sources not available")
        }
        var offenders: [String] = []
        for case let url as URL in e where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for banned in ["AIBackendManager", "EthicalAIGuardian", "OPENAI_API_KEY", "/api/generate", "/v1/chat/completions"]
            where text.replacingOccurrences(of: "migrateFromLegacyAIBackendManager", with: "").contains(banned) {
                offenders.append("\(url.lastPathComponent): \(banned)")
            }
        }
        XCTAssertEqual(offenders, [])
    }
}

// MARK: - 2. Performance

@MainActor
final class AIKitPerformanceTests: XCTestCase {
    override func setUp() { DotSyncAIStub.reset() }

    func testValidatorsParseLargeRepliesQuickly() throws {
        let reply = (1...2000).map { "FINDING|credential|high|\($0)|secret \($0)|rotate it" }.joined(separator: "\n")
        let start = Date()
        let findings = try AISecurityAnalyzer.validateFindings(reply, lineCount: 1000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
        XCTAssertEqual(findings.count, 2000)
        XCTAssertEqual(findings.filter { $0.lineNumber == nil }.count, 1000, "lines past the end are dropped")
    }

    func testAIOffFallbackIsImmediate() async {
        let ai = DotSyncAITest.makeAI(DotSyncAITest.off)
        let big = (0..<5000).map { "export VAR\($0)=value\($0)" }.joined(separator: "\n")
        let start = Date()
        _ = await AISecurityAnalyzer(ai: ai).detectCredentials(in: big, filename: ".zshrc")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5.0)
        XCTAssertEqual(DotSyncAIStub.chatRequests, 0, "nothing sent when AI is off")
    }

    func testOfflineFallbackDoesNotHang() async {
        let ai = DotSyncAITest.makeAI()
        let start = Date()
        _ = await AIMergeAssistant(ai: ai).explainChanges(originalContent: "a", newContent: "b", filename: ".zshrc")
        XCTAssertLessThan(Date().timeIntervalSince(start), 10.0)
    }
}

// MARK: - 3. Retry

@MainActor
final class AIKitRetryTests: XCTestCase {
    override func setUp() { DotSyncAIStub.reset() }

    func testRejectedReplyIsRetriedOnceThenAccepted() async {
        DotSyncAIStub.reset(replies: ["Sure! Your file looks fine.", "SUMMARY: Added an alias\nIMPACT: low\nCHANGES:\n- SECTION|aliases|added ll|add"])
        let merge = AIMergeAssistant(ai: DotSyncAITest.makeAI())
        let r = await merge.explainChanges(originalContent: "a", newContent: "a\nalias ll=ls", filename: ".zshrc")
        XCTAssertEqual(r.summary, "Added an alias")
        XCTAssertEqual(r.impact, .low)
        XCTAssertEqual(merge.lastSource?.isAI, true)
        XCTAssertEqual(DotSyncAIStub.chatRequests, 2)
    }

    func testTwiceRejectedReplyFallsBackToBuiltIn() async {
        DotSyncAIStub.reset(replies: ["no idea"])
        let merge = AIMergeAssistant(ai: DotSyncAITest.makeAI())
        let r = await merge.suggestMergeResolution(localContent: "a", remoteContent: "b", ancestorContent: nil, filename: ".zshrc")
        XCTAssertEqual(r.recommendation, .manualReview)
        if case .fallback(.validationFailed) = merge.lastSource {} else { XCTFail("expected validationFailed, got \(String(describing: merge.lastSource))") }
    }

    func testTransientServerErrorIsRetried() async {
        DotSyncAIStub.reset(replies: ["SCORE: 95"], statuses: [503])
        let insights = AIConfigInsights(ai: DotSyncAITest.makeAI())
        let health = await insights.runHealthCheck(configs: [try! DotSyncAITest.configFile(".zshrc", "alias a=b\n")])
        XCTAssertEqual(health.overallScore, 95)
        XCTAssertEqual(insights.lastSource?.isAI, true)
        XCTAssertGreaterThanOrEqual(DotSyncAIStub.chatRequests, 2)
    }
}

// MARK: - 4. Unit (validators: reject nonsense, clamp to legal ranges)

final class AIKitUnitTests: XCTestCase {
    func testBackendCount() {
        XCTAssertEqual(NovaAIBackend.allCases.count, 9)
        XCTAssertFalse(NovaAIBackend.allCases.map(\.rawValue).contains { ["google", "azure", "aws", "ibm"].contains($0) })
    }

    func testFindingsValidator() throws {
        XCTAssertThrowsError(try AISecurityAnalyzer.validateFindings("Looks good to me!", lineCount: 10))
        XCTAssertEqual(try AISecurityAnalyzer.validateFindings("NO_FINDINGS", lineCount: 10).count, 0)
        let f = try AISecurityAnalyzer.validateFindings("  FINDING|token|critical|99|leaked|rotate\nFINDING|weak|bogus|3|x|y", lineCount: 10)
        XCTAssertEqual(f.count, 2)
        XCTAssertNil(f[0].lineNumber, "line 99 of a 10-line file is dropped")
        XCTAssertEqual(f[0].severity, .critical)
        XCTAssertEqual(f[1].severity, .medium, "unknown severity clamps to medium")
        XCTAssertEqual(f[1].lineNumber, 3)
    }

    func testAnomalyValidator() throws {
        XCTAssertThrowsError(try AISecurityAnalyzer.validateAnomaly("whatever", filename: "f"))
        let a = try AISecurityAnalyzer.validateAnomaly("SIGNIFICANT: yes\nCHANGE_SUMMARY: x\nRISK_ASSESSMENT: apocalyptic\nRECOMMENDATION: r", filename: "f")
        XCTAssertEqual(a?.riskAssessment, "Medium", "unknown risk clamps")
        XCTAssertEqual(a?.isSignificant, true)
    }

    func testMergeValidators() throws {
        XCTAssertThrowsError(try AIMergeAssistant.validateMergeSuggestion("keep it", filename: "f"))
        let s = try AIMergeAssistant.validateMergeSuggestion("RECOMMENDATION: keep_local\nCONFIDENCE: 7.5\nREASONING: r\nWARNINGS: none", filename: "f")
        XCTAssertEqual(s.recommendation, .keepLocal)
        XCTAssertEqual(s.confidence, 1.0, "confidence clamps to 0...1")
        let m = try AIMergeAssistant.validateMergeSuggestion("RECOMMENDATION: merge\nCONFIDENCE: -1\nMERGED_CONTENT: N/A", filename: "f")
        XCTAssertEqual(m.recommendation, .manualReview, "merge without merged content → manual review")
        XCTAssertEqual(m.confidence, 0)

        XCTAssertThrowsError(try AIMergeAssistant.validateSemanticMerge("SUCCESS: yes", filename: "f"))
        let sm = try AIMergeAssistant.validateSemanticMerge("SUCCESS: yes\nAUTO_RESOLVED: -4\nMERGED_CONTENT_START\nalias a=b\nMERGED_CONTENT_END", filename: "f")
        XCTAssertEqual(sm.mergedContent, "alias a=b")
        XCTAssertEqual(sm.autoResolvedCount, 0)

        XCTAssertThrowsError(try AIMergeAssistant.validateChangeExplanation("It changed.", filename: "f"))
    }

    func testInsightsValidators() throws {
        XCTAssertThrowsError(try AIConfigInsights.validateHealthCheck("All good!", filename: "f", lineCount: 5))
        let h = try AIConfigInsights.validateHealthCheck("ISSUE|error|42|bad|fix\nSCORE: 250", filename: "f", lineCount: 5)
        XCTAssertEqual(h.score, 100)
        XCTAssertNil(h.issues.first?.lineNumber)
        XCTAssertEqual(h.status, .healthy)

        XCTAssertThrowsError(try AIConfigInsights.validateRecommendations("Use git.", filename: "f"))
        XCTAssertEqual(try AIConfigInsights.validateRecommendations("REC|security|high|T|D|NA", filename: "f").first?.suggestedChange, nil)

        XCTAssertThrowsError(try AIConfigInsights.validateShellAnalysis("fast enough", filename: "f"))
        XCTAssertEqual(try AIConfigInsights.validateShellAnalysis("STARTUP_IMPACT: glacial", filename: "f").startupTime, "moderate")
        XCTAssertEqual(try AIConfigInsights.validateShellAnalysis("STARTUP_IMPACT: very slow", filename: "f").startupTime, "very_slow")
    }

    func testAssistantValidators() throws {
        let cfg = ConfigFile(path: "/tmp/.zshrc", relativePath: ".zshrc", filename: ".zshrc", category: .shell, size: 1,
                             lastModified: Date(), checksum: "x", isSafeToSync: true, syncPriority: .medium, isDirectory: false)
        XCTAssertThrowsError(try AIConfigAssistant.validateSemanticSearch("maybe", configs: [cfg]))
        let r = try AIConfigAssistant.validateSemanticSearch("MATCH|0|9|alias|why\nMATCH|7|0.5|x|out of range", configs: [cfg])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].relevanceScore, 1.0)

        XCTAssertThrowsError(try AIConfigAssistant.validateConfigGeneration("EXPLANATION: x", targetFile: ".zshrc"))
        XCTAssertEqual(try AIConfigAssistant.validateConfigGeneration("EXPLANATION: e\nCONFIG_START\nalias a=b\nCONFIG_END", targetFile: ".zshrc")?.generatedContent, "alias a=b")

        XCTAssertThrowsError(try AIConfigAssistant.validateMigrationPlan("EFFORT: minimal", sourceFile: ".bashrc", targetTool: "zsh"))
        let plan = try AIConfigAssistant.validateMigrationPlan("EFFORT: huge\nSTEP|9|b|NA|NA|no\nSTEP|3|a|NA|x|yes", sourceFile: ".bashrc", targetTool: "zsh")
        XCTAssertEqual(plan?.steps.map(\.order), [1, 2])
        XCTAssertEqual(plan?.steps.first?.description, "a")
        XCTAssertEqual(plan?.estimatedEffort, "moderate")

        XCTAssertThrowsError(try AIConfigAssistant.validatePriorities("all critical", knownPaths: ["/a"]))
        let p = try AIConfigAssistant.validatePriorities("PRIORITY|/a|critical\nPRIORITY|/etc/passwd|critical", knownPaths: ["/a"])
        XCTAssertEqual(p, ["/a": .critical], "only files we asked about")
    }
}

// MARK: - 5. Integration

@MainActor
final class AIKitIntegrationTests: XCTestCase {
    override func setUp() { DotSyncAIStub.reset() }

    func testAIFindingsFlowThroughWhenBackendAnswers() async {
        DotSyncAIStub.reset(replies: ["FINDING|credential|critical|2|AWS key in plain text|Move it to the Keychain"])
        let security = AISecurityAnalyzer(ai: DotSyncAITest.makeAI())
        let f = await security.detectCredentials(in: DotSyncAITest.secretConfig, filename: ".env")
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f.first?.description, "AWS key in plain text")
        XCTAssertEqual(f.first?.lineNumber, 2)
        XCTAssertEqual(security.lastSource?.isAI, true)
        XCTAssertTrue(security.lastSource?.label.contains("Ollama") ?? false)
    }

    func testSemanticSearchMergesWithKeywordResults() async throws {
        let cfg = try DotSyncAITest.configFile(".zshrc", DotSyncAITest.shellConfig)
        DotSyncAIStub.reset(replies: ["MATCH|0|0.9|source $NVM_DIR/nvm.sh|node version manager"])
        let assistant = AIConfigAssistant(ai: DotSyncAITest.makeAI(), userDefaults: DotSyncAITest.suite())
        let results = await assistant.search(query: "node", in: [cfg])
        XCTAssertTrue(results.contains { $0.matchType == .semanticMatch })
    }

    func testLegacySettingsMigrate() {
        let defaults = DotSyncAITest.suite()
        // The old AIBackendManager-era keys (backend display name, Ollama model, on/off), as NovaAIKit lists them.
        defaults.set("Ollama", forKey: NovaAILegacySettings.backendKeys[1])
        defaults.set("qwen3:8b", forKey: NovaAILegacySettings.ollamaModelKeys[1])
        defaults.set(false, forKey: NovaAILegacySettings.enabledKeys[1])
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [DotSyncAIStub.self]
        let ai = NovaAI(configuration: AppAI.configuration, storage: NovaAIMemoryStorage(), keyStore: NovaAIMemoryKeyStore(),
                        session: URLSession(configuration: cfg), sleep: { _ in })

        AppAI.migrateLegacy(ai, defaults: defaults)

        XCTAssertEqual(ai.settings.backend, .ollama)
        XCTAssertEqual(ai.settings.model(for: .ollama), "qwen3:8b")
        XCTAssertFalse(ai.settings.enabled)
    }

    func testStatusReflectsLastCall() async {
        DotSyncAIStub.reset(replies: ["SCORE: 100"])
        let ai = DotSyncAITest.makeAI()
        _ = await AIConfigInsights(ai: ai).analyzeShellConfig(content: "x", filename: ".zshrc")
        XCTAssertNotNil(ai.status.lastSource)
    }
}

// MARK: - 6. Functional

@MainActor
final class AIKitFunctionalTests: XCTestCase {
    override func setUp() { DotSyncAIStub.reset() }

    /// Feature 1+2: AI off → every AI feature still produces its built-in result; nothing is sent.
    func testEveryFeatureWorksWithAIOff() async throws {
        let ai = DotSyncAITest.makeAI(DotSyncAITest.off)
        try await assertEveryFeatureUsesBuiltIn(ai)
        XCTAssertEqual(DotSyncAIStub.chatRequests, 0)
        XCTAssertEqual(ai.status.state, .off)
    }

    /// Feature 2+7: every backend down (Auto failover over all of them) → built-in result, no hang.
    func testEveryFeatureFallsBackWhenOffline() async throws {
        let ai = DotSyncAITest.makeAI(NovaAISettings(backend: .auto))
        try await assertEveryFeatureUsesBuiltIn(ai)
    }

    func testAskAIAnswerCarriesSourceLabel() {
        let m = ChatMessage(content: "x", isUser: false, timestamp: Date(), sourceLabel: NovaAISource.fallback(.disabled).label)
        XCTAssertEqual(m.sourceLabel, "Built-in")
    }
}

// MARK: - 7. Frame / UI state

@MainActor
final class AIKitFrameTests: XCTestCase {
    func testSettingsViewRenders() {
        let host = NSHostingView(rootView: NovaAISettingsView(ai: DotSyncAITest.makeAI(), footer: AppAI.footer).frame(width: 640, height: 560))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 560)
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

    func testStatusIndicatorRendersInEveryState() {
        for settings in [DotSyncAITest.off, NovaAISettings(backend: .ollama)] {
            let ai = DotSyncAITest.makeAI(settings)
            let host = NSHostingView(rootView: NovaAIStatusIndicator(ai: ai, checksOnAppear: false))
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.width, 0)
        }
    }

    func testToggleUpdatesState() {
        let ai = DotSyncAITest.makeAI()
        ai.isEnabled = false
        XCTAssertEqual(ai.status.state, .off)
        ai.isEnabled = true
        XCTAssertNotEqual(ai.status.state, .off)
    }

    func testFooterExplainsBuiltInBehaviour() {
        XCTAssertTrue(AppAI.footer.contains("built-in"))
    }
}
