//
//  SyncHookTests.swift
//  Dot Sync Tests
//
//  Created by Jordan Koch on 5/1/26.
//

import XCTest
@testable import Dot_Sync

final class SyncHookTests: XCTestCase {

    // MARK: - Hook Matching

    func testHookMatchesExactFilename() {
        let hook = SyncHook(
            name: "Test", command: "echo test", enabled: true,
            filePattern: ".zshrc", continueOnError: true
        )

        let file = makeFile(filename: ".zshrc")
        XCTAssertTrue(hook.matches(file: file))
    }

    func testHookDoesNotMatchDifferentFile() {
        let hook = SyncHook(
            name: "Test", command: "echo test", enabled: true,
            filePattern: ".bashrc", continueOnError: true
        )

        let file = makeFile(filename: ".zshrc")
        XCTAssertFalse(hook.matches(file: file))
    }

    func testHookMatchesWildcard() {
        let hook = SyncHook(
            name: "Test", command: "echo test", enabled: true,
            filePattern: "*", continueOnError: true
        )

        let file = makeFile(filename: ".anything")
        XCTAssertTrue(hook.matches(file: file))
    }

    func testHookMatchesEmptyPattern() {
        let hook = SyncHook(
            name: "Test", command: "echo test", enabled: true,
            filePattern: "", continueOnError: true
        )

        let file = makeFile(filename: ".anything")
        XCTAssertTrue(hook.matches(file: file))
    }

    func testHookPartialFilenameMatch() {
        let hook = SyncHook(
            name: "Test", command: "echo test", enabled: true,
            filePattern: "zsh", continueOnError: true
        )

        let file = makeFile(filename: ".zshrc")
        XCTAssertTrue(hook.matches(file: file), "Partial match should work (contains)")
    }

    func testHookMatchesPath() {
        let hook = SyncHook(
            name: "Test", command: "echo test", enabled: true,
            filePattern: "config", continueOnError: true
        )

        let file = makeFile(filename: "settings.json", path: "/Users/test/.config/settings.json")
        XCTAssertTrue(hook.matches(file: file), "Should match against path too")
    }

    // MARK: - Hook Execution

    func testExecuteSimpleCommand() async throws {
        let hook = SyncHook(
            name: "Echo", command: "echo hello", enabled: true,
            filePattern: "*", continueOnError: true
        )

        let result = try await hook.execute()

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("hello"))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.skipped)
    }

    func testExecuteDisabledHook() async throws {
        let hook = SyncHook(
            name: "Disabled", command: "echo should-not-run", enabled: false,
            filePattern: "*", continueOnError: true
        )

        let result = try await hook.execute()

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.skipped)
        XCTAssertFalse(result.output.contains("should-not-run"))
    }

    func testExecuteFailingCommand() async throws {
        let hook = SyncHook(
            name: "Fail", command: "exit 1", enabled: true,
            filePattern: "*", continueOnError: true
        )

        let result = try await hook.execute()

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.exitCode, 1)
    }

    func testExecutePassesEnvironmentVariables() async throws {
        let hook = SyncHook(
            name: "EnvTest", command: "echo $SYNC_FILENAME", enabled: true,
            filePattern: "*", continueOnError: true
        )

        let file = makeFile(filename: ".zshrc")
        let result = try await hook.execute(for: file)

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains(".zshrc"),
                      "Environment variable SYNC_FILENAME should be set")
    }

    func testExecutePassesCategoryEnv() async throws {
        let hook = SyncHook(
            name: "CatTest", command: "echo $SYNC_CATEGORY", enabled: true,
            filePattern: "*", continueOnError: true
        )

        let file = makeFile(filename: ".zshrc", category: .shell)
        let result = try await hook.execute(for: file)

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("Shell"))
    }

    // MARK: - Command Injection Prevention (Security)

    func testCommandInjectionViaFilename() async throws {
        // The hook command should NOT be vulnerable to injection through filenames
        // because filenames are passed via environment variables, not interpolated
        let hook = SyncHook(
            name: "Safe", command: "echo safe", enabled: true,
            filePattern: "*", continueOnError: true
        )

        // Malicious filename with shell injection attempt
        let maliciousFile = makeFile(filename: "$(rm -rf /tmp/test)")
        let result = try await hook.execute(for: maliciousFile)

        XCTAssertTrue(result.success, "Hook should execute safely despite malicious filename")
        XCTAssertTrue(result.output.contains("safe"),
                      "Only the intended command should execute")
    }

    func testCommandInjectionViaSemicolon() async throws {
        let hook = SyncHook(
            name: "Safe", command: "echo safe", enabled: true,
            filePattern: "*", continueOnError: true
        )

        let maliciousFile = makeFile(filename: "test; echo hacked")
        let result = try await hook.execute(for: maliciousFile)

        XCTAssertTrue(result.success)
        XCTAssertFalse(result.output.contains("hacked"),
                       "Semicolon injection should not work")
    }

    // MARK: - HookResult

    func testHookResultStatusIconSuccess() {
        let result = HookResult(success: true, output: "ok")
        XCTAssertEqual(result.statusIcon, "checkmark.circle.fill")
        XCTAssertEqual(result.statusColor, "green")
    }

    func testHookResultStatusIconFailure() {
        let result = HookResult(success: false, output: "error")
        XCTAssertEqual(result.statusIcon, "xmark.circle.fill")
        XCTAssertEqual(result.statusColor, "red")
    }

    func testHookResultStatusIconSkipped() {
        let result = HookResult(success: true, output: "skipped", skipped: true)
        XCTAssertEqual(result.statusIcon, "minus.circle")
        XCTAssertEqual(result.statusColor, "gray")
    }

    // MARK: - Default Hooks

    func testDefaultHooksExist() {
        let hooks = SyncHooks.default
        XCTAssertFalse(hooks.preSyncHooks.isEmpty, "Should have default pre-sync hooks")
        XCTAssertFalse(hooks.postSyncHooks.isEmpty, "Should have default post-sync hooks")
    }

    func testDefaultPreSyncHooksValidateShellConfig() {
        let hooks = SyncHooks.default
        let zshHook = hooks.preSyncHooks.first { $0.filePattern == ".zshrc" }
        XCTAssertNotNil(zshHook, "Should have a pre-sync hook for .zshrc")
        XCTAssertTrue(zshHook!.command.contains("zsh -n"))
    }

    func testDefaultPreSyncHooksValidateBashConfig() {
        let hooks = SyncHooks.default
        let bashHook = hooks.preSyncHooks.first { $0.filePattern == ".bashrc" }
        XCTAssertNotNil(bashHook, "Should have a pre-sync hook for .bashrc")
        XCTAssertTrue(bashHook!.command.contains("bash -n"))
    }

    // MARK: - SyncHooks Codable

    func testSyncHooksCodable() throws {
        let original = SyncHooks.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncHooks.self, from: data)

        XCTAssertEqual(decoded.preSyncHooks.count, original.preSyncHooks.count)
        XCTAssertEqual(decoded.postSyncHooks.count, original.postSyncHooks.count)
    }

    // MARK: - Helpers

    private func makeFile(
        filename: String = ".zshrc",
        path: String? = nil,
        category: ConfigCategory = .shell
    ) -> ConfigFile {
        let resolvedPath = path ?? "/Users/test/\(filename)"
        return ConfigFile(
            path: resolvedPath,
            relativePath: filename,
            filename: filename,
            category: category,
            size: 100,
            lastModified: Date(),
            checksum: "abc",
            isSafeToSync: true,
            syncPriority: .critical
        )
    }
}
