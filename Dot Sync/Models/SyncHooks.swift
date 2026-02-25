//
//  SyncHooks.swift
//  Dot Sync
//
//  Created by Jordan Koch on 1/6/26.
//

import Foundation

/// Sync hooks for pre/post sync automation
struct SyncHooks: Codable {
    var preSyncHooks: [SyncHook]
    var postSyncHooks: [SyncHook]

    static var `default`: SyncHooks {
        SyncHooks(
            preSyncHooks: [
                SyncHook(
                    name: "Validate Shell Config",
                    command: "zsh -n ~/.zshrc",
                    enabled: true,
                    filePattern: ".zshrc",
                    continueOnError: false
                ),
                SyncHook(
                    name: "Validate Bash Config",
                    command: "bash -n ~/.bashrc",
                    enabled: true,
                    filePattern: ".bashrc",
                    continueOnError: false
                )
            ],
            postSyncHooks: [
                SyncHook(
                    name: "Reload Shell Config",
                    command: "source ~/.zshrc",
                    enabled: false,
                    filePattern: ".zshrc",
                    continueOnError: true
                ),
                SyncHook(
                    name: "Reload Git Config",
                    command: "git config --list > /dev/null",
                    enabled: true,
                    filePattern: ".gitconfig",
                    continueOnError: true
                )
            ]
        )
    }
}

/// Individual sync hook
struct SyncHook: Identifiable, Codable {
    let id: UUID
    var name: String
    var command: String
    var enabled: Bool
    var filePattern: String // Regex pattern for matching files
    var continueOnError: Bool // If false, sync aborts on hook failure

    init(id: UUID = UUID(), name: String, command: String, enabled: Bool,
         filePattern: String, continueOnError: Bool) {
        self.id = id
        self.name = name
        self.command = command
        self.enabled = enabled
        self.filePattern = filePattern
        self.continueOnError = continueOnError
    }

    /// Check if hook applies to file
    func matches(file: ConfigFile) -> Bool {
        if filePattern.isEmpty { return true }
        if filePattern == "*" { return true }

        // Simple pattern matching
        return file.filename.contains(filePattern) ||
               file.path.contains(filePattern)
    }

    /// Execute hook
    func execute(for file: ConfigFile? = nil) async throws -> HookResult {
        guard enabled else {
            return HookResult(success: true, output: "Hook disabled", skipped: true)
        }

        // Pass file metadata via environment variables to prevent command injection
        // Instead of interpolating filenames into the shell command (which allows injection
        // via crafted filenames), we set environment variables that the command can reference
        // as $SYNC_FILENAME, $SYNC_FILEPATH, $SYNC_CATEGORY
        let expandedCommand = command

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", expandedCommand]

        // Merge file metadata into environment variables safely
        var env = ProcessInfo.processInfo.environment
        if let file = file {
            env["SYNC_FILENAME"] = file.filename
            env["SYNC_FILEPATH"] = file.path
            env["SYNC_CATEGORY"] = file.category.rawValue
        }
        process.environment = env

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let startTime = Date()

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""

            let duration = Date().timeIntervalSince(startTime)
            let success = process.terminationStatus == 0

            let fullOutput = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")

            return HookResult(
                success: success,
                output: fullOutput.isEmpty ? "No output" : fullOutput,
                exitCode: Int(process.terminationStatus),
                duration: duration,
                skipped: false
            )
        } catch {
            return HookResult(
                success: false,
                output: "Failed to execute: \(error.localizedDescription)",
                exitCode: -1,
                duration: Date().timeIntervalSince(startTime),
                skipped: false
            )
        }
    }
}

/// Result of hook execution
struct HookResult {
    let success: Bool
    let output: String
    let exitCode: Int?
    let duration: TimeInterval?
    let skipped: Bool

    init(success: Bool, output: String, exitCode: Int? = nil, duration: TimeInterval? = nil, skipped: Bool = false) {
        self.success = success
        self.output = output
        self.exitCode = exitCode
        self.duration = duration
        self.skipped = skipped
    }

    var statusIcon: String {
        if skipped { return "minus.circle" }
        return success ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var statusColor: String {
        if skipped { return "gray" }
        return success ? "green" : "red"
    }
}

/// Hook manager for loading/saving hooks
@MainActor
class HookManager: ObservableObject {
    static let shared = HookManager()

    @Published var hooks: SyncHooks

    private let storageKey = "syncHooks"
    private let defaults = UserDefaults.standard

    init() {
        // Load from UserDefaults or use default hooks
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(SyncHooks.self, from: data) {
            self.hooks = decoded
        } else {
            self.hooks = .default
            save()
        }
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(hooks) {
            defaults.set(encoded, forKey: storageKey)
        }
    }

    /// Execute pre-sync hooks for a file
    func executePreSyncHooks(for file: ConfigFile) async -> [HookResult] {
        var results: [HookResult] = []

        for hook in hooks.preSyncHooks where hook.matches(file: file) {
            let result = try? await hook.execute(for: file)
            if let result = result {
                results.append(result)

                // Abort if critical hook fails
                if !result.success && !hook.continueOnError {
                    print("[Hooks] ❌ Pre-sync hook failed: \(hook.name)")
                    break
                }
            }
        }

        return results
    }

    /// Execute post-sync hooks for a file
    func executePostSyncHooks(for file: ConfigFile) async -> [HookResult] {
        var results: [HookResult] = []

        for hook in hooks.postSyncHooks where hook.matches(file: file) {
            let result = try? await hook.execute(for: file)
            if let result = result {
                results.append(result)
            }
        }

        return results
    }
}
