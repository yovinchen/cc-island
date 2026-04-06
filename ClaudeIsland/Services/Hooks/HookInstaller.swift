//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Multi-source hook installer with protocol-based architecture.
//  Supports Claude, Codex, Gemini, Cursor, OpenCode, and Copilot.
//

import Foundation

// MARK: - Hook Source Protocol

protocol HookSource {
    var sourceType: SessionSource { get }
    var configPath: String { get }
    var managedConfigPaths: [String] { get }
    var displayName: String { get }
    func install(bridgePath: String) throws
    func uninstall() throws
    func isInstalled() -> Bool
}

extension HookSource {
    var managedConfigPaths: [String] { [configPath] }
}

// MARK: - Hook Status

enum HookStatus {
    case installed
    case notInstalled
    case disabled
    case error(String)
}

// MARK: - HookInstaller

struct HookInstaller {

    // MARK: - Sources Registry

    private static let allSources: [HookSource] = [
        ClaudeHookSource(),
        ClineHookSource(),
        CodexHookSource(),
        GeminiHookSource(),
        CursorHookSource(),
        WindsurfHookSource(),
        KimiHookSource(),
        KiroHookSource(),
        AmpHookSource(),
        OpenCodeHookSource(),
        CopilotHookSource(),
        HelperOnlySource(
            sourceType: .pi,
            displayName: "Pi Coding Agent",
            helperNames: ["claude-island-pi", "claude-island-pi-json"]
        ),
        HelperOnlySource(
            sourceType: .crush,
            displayName: "Crush",
            helperNames: ["claude-island-crush"]
        ),
        QoderHookSource(),
        DroidHookSource(),
        CodeBuddyHookSource(),
        // TraeHookSource() — Trae 暂不支持 Hooks API，待官方适配后启用
    ]

    /// Sources that are detected but not yet supported (no Hooks API)
    static let unsupportedSources: Set<SessionSource> = [.trae]

    /// Get bridge path for internal use (may contain spaces, not for hook commands)
    static func bridgePath() -> String {
        // Check for Swift bridge in app bundle (Contents/Helpers/)
        let helpersPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/claude-island-bridge").path
        if FileManager.default.fileExists(atPath: helpersPath) {
            return helpersPath
        }

        // Check for installed launcher (no spaces, safe for shell)
        let launcherPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin/claude-island-bridge-launcher.sh").path
        if FileManager.default.fileExists(atPath: launcherPath) {
            return launcherPath
        }

        // Fall back to Python script
        return "\(detectPython()) ~/.claude/hooks/claude-island-state.py"
    }

    /// Get the hook command path — must be space-free for shell execution.
    /// Always uses the launcher script at ~/.claude-island/bin/ which
    /// internally discovers the app bundle path (even with spaces).
    static func hookCommandPath() -> String {
        // Use tilde form — no spaces, shell-safe, works across app relocations
        return "~/.claude-island/bin/claude-island-bridge-launcher.sh"
    }

    /// Install the bridge launcher script to ~/.claude-island/bin/
    static func installLauncher() {
        let binDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin")
        let launcherDest = binDir.appendingPathComponent("claude-island-bridge-launcher.sh")

        try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        if let bundled = Bundle.main.url(forResource: "claude-island-bridge-launcher", withExtension: "sh") {
            try? FileManager.default.removeItem(at: launcherDest)
            try? FileManager.default.copyItem(at: bundled, to: launcherDest)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: launcherDest.path
            )
        }

        // Write current app bundle path to bridge cache so launcher can find it
        // (critical for Xcode debug builds where app isn't in /Applications)
        let cachePath = binDir.appendingPathComponent(".bridge-cache")
        let appBundlePath = Bundle.main.bundleURL.path + "\n"
        try? appBundlePath.write(to: cachePath, atomically: true, encoding: .utf8)

        // Install statusline script
        installStatusLineScript(to: binDir)
        installHelperScripts(to: binDir)
    }

    /// Install the statusline script to ~/.claude-island/bin/
    private static func installStatusLineScript(to binDir: URL) {
        let statuslineDest = binDir.appendingPathComponent("claude-island-statusline")

        if let bundled = Bundle.main.url(forResource: "claude-island-statusline", withExtension: "sh") {
            try? FileManager.default.removeItem(at: statuslineDest)
            try? FileManager.default.copyItem(at: bundled, to: statuslineDest)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: statuslineDest.path
            )
        }
    }

    private static func installHelperScripts(to binDir: URL) {
        let helperScripts: [(resource: String, ext: String, dest: String)] = [
            ("claude-island-amp", "sh", "claude-island-amp"),
            ("claude-island-amp-exec", "sh", "claude-island-amp-exec"),
            ("claude-island-amp-stream", "sh", "claude-island-amp-stream"),
            ("claude-island-copilot-json", "sh", "claude-island-copilot-json"),
            ("claude-island-kimi-print", "sh", "claude-island-kimi-print"),
            ("claude-island-kiro", "sh", "claude-island-kiro"),
            ("claude-island-pi-json", "sh", "claude-island-pi-json"),
            ("claude-island-pi", "sh", "claude-island-pi"),
            ("claude-island-crush", "sh", "claude-island-crush"),
        ]

        for helper in helperScripts {
            let destination = binDir.appendingPathComponent(helper.dest)
            if let bundled = Bundle.main.url(forResource: helper.resource, withExtension: helper.ext) {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.copyItem(at: bundled, to: destination)
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: destination.path
                )
            }
        }
    }

    // MARK: - Public API

    /// Install ONLY user-enabled integrations. Called after user completes hook setup.
    static func installEnabledOnly() {
        installLauncher()
        let bridge = hookCommandPath()
        for source in allSources {
            if AppSettings.isHookEnabled(for: source.sourceType) {
                // Auto-upgrade hooks if version mismatch
                if let claudeSource = source as? ClaudeHookSource, claudeSource.needsUpgrade() {
                    try? claudeSource.uninstall()
                    Task { await DiagnosticLogger.shared.log("Upgrading hook for \(source.displayName) to v\(ClaudeHookSource.hookVersion)", category: .hook) }
                }
                try? source.install(bridgePath: bridge)
                Task { await DiagnosticLogger.shared.log("Installed hook for \(source.displayName)", category: .hook) }
            }
        }
        // Only install Python script if Claude hook is enabled
        if AppSettings.isHookEnabled(for: .claude) {
            installClaudePythonScript()
        }
    }

    /// Legacy: install all managed integrations (kept for backward compat with the toggle in menu).
    static func installIfNeeded() {
        installEnabledOnly()
    }

    /// Check whether at least one managed integration is installed.
    static func isInstalled() -> Bool {
        allSources.contains { $0.isInstalled() }
    }

    /// Remove all managed integrations.
    static func uninstall() {
        for source in allSources {
            try? source.uninstall()
        }
    }

    /// Install a specific source (user-initiated)
    static func installSource(_ source: SessionSource) {
        installLauncher()
        let bridge = hookCommandPath()
        guard let hookSource = allSources.first(where: { $0.sourceType == source }) else { return }
        try? hookSource.install(bridgePath: bridge)
        AppSettings.setHookEnabled(true, for: source)
    }

    /// Uninstall a specific source (user-initiated)
    static func uninstallSource(_ source: SessionSource) {
        guard let hookSource = allSources.first(where: { $0.sourceType == source }) else { return }
        try? hookSource.uninstall()
        AppSettings.setHookEnabled(false, for: source)
    }

    /// Detect which AI tools are installed on the system
    static func detectInstalledTools() -> [SessionSource] {
        var installed: [SessionSource] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Claude: check ~/.claude directory
        if fm.fileExists(atPath: "\(home)/.claude") {
            installed.append(.claude)
        }

        // Cline: check ~/.cline, ~/Documents/Cline, or common executable locations
        if fm.fileExists(atPath: "\(home)/.cline") ||
           fm.fileExists(atPath: "\(home)/Documents/Cline") ||
           fm.fileExists(atPath: "/usr/local/bin/cline") ||
           fm.fileExists(atPath: "/opt/homebrew/bin/cline") {
            installed.append(.cline)
        }

        // Codex: check ~/.codex directory
        if fm.fileExists(atPath: "\(home)/.codex") {
            installed.append(.codexCLI)
        }

        // Gemini: check for gemini CLI
        if fm.fileExists(atPath: "\(home)/.gemini") ||
           fm.fileExists(atPath: "/usr/local/bin/gemini") ||
           fm.fileExists(atPath: "/opt/homebrew/bin/gemini") {
            installed.append(.gemini)
        }

        // Cursor: check ~/.cursor or /Applications/Cursor.app
        if fm.fileExists(atPath: "\(home)/.cursor") ||
           fm.fileExists(atPath: "/Applications/Cursor.app") {
            installed.append(.cursor)
        }

        // Windsurf: check ~/.codeium/windsurf or /Applications/Windsurf.app
        if fm.fileExists(atPath: "\(home)/.codeium/windsurf") ||
           fm.fileExists(atPath: "/Applications/Windsurf.app") {
            installed.append(.windsurf)
        }

        // Kimi CLI: check ~/.kimi or common executable locations
        if fm.fileExists(atPath: "\(home)/.kimi") ||
           fm.fileExists(atPath: "/usr/local/bin/kimi") ||
           fm.fileExists(atPath: "/opt/homebrew/bin/kimi") {
            installed.append(.kimiCLI)
        }

        // Kiro CLI: check ~/.kiro or common executable locations
        if fm.fileExists(atPath: "\(home)/.kiro") ||
           fm.fileExists(atPath: "/usr/local/bin/kiro-cli") ||
           fm.fileExists(atPath: "/opt/homebrew/bin/kiro-cli") {
            installed.append(.kiroCLI)
        }

        // Amp CLI: check ~/.config/amp or common executable locations
        if fm.fileExists(atPath: "\(home)/.config/amp") ||
           fm.fileExists(atPath: "/usr/local/bin/amp") ||
           fm.fileExists(atPath: "/opt/homebrew/bin/amp") {
            installed.append(.ampCLI)
        }

        // Pi Coding Agent: check ~/.pi or common executable locations
        if fm.fileExists(atPath: "\(home)/.pi") ||
           fm.fileExists(atPath: "/usr/local/bin/pi") ||
           fm.fileExists(atPath: "/opt/homebrew/bin/pi") {
            installed.append(.pi)
        }

        // Crush: check ~/.config/crush or common executable locations
        if fm.fileExists(atPath: "\(home)/.config/crush") ||
           fm.fileExists(atPath: "/usr/local/bin/crush") ||
           fm.fileExists(atPath: "/opt/homebrew/bin/crush") {
            installed.append(.crush)
        }

        // OpenCode: check ~/.config/opencode
        if fm.fileExists(atPath: "\(home)/.config/opencode") {
            installed.append(.opencode)
        }

        // Copilot: check ~/.copilot
        if fm.fileExists(atPath: "\(home)/.copilot") {
            installed.append(.copilot)
        }

        // Qoder: check ~/.qoder
        if fm.fileExists(atPath: "\(home)/.qoder") {
            installed.append(.qoder)
        }

        // Droid (Factory): check ~/.factory
        if fm.fileExists(atPath: "\(home)/.factory") {
            installed.append(.droid)
        }

        // CodeBuddy: check ~/.codebuddy
        if fm.fileExists(atPath: "\(home)/.codebuddy") {
            installed.append(.codebuddy)
        }

        // Trae: 暂不支持 Hooks API，不检测
        // if fm.fileExists(atPath: "\(home)/.trae") {
        //     installed.append(.trae)
        // }

        return installed
    }

    /// Get installation status for all sources
    static func allStatuses() -> [SessionSource: Bool] {
        var result: [SessionSource: Bool] = [:]
        for source in allSources {
            result[source.sourceType] = source.isInstalled()
        }
        return result
    }

    /// Get the HookSource for a specific type
    static func hookSource(for type: SessionSource) -> HookSource? {
        allSources.first { $0.sourceType == type }
    }

    // MARK: - Legacy Claude Support

    /// Install the Python hook script (still needed for Claude Code compatibility)
    private static func installClaudePythonScript() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("claude-island-state.py")

        try? FileManager.default.createDirectory(
            at: hooksDir,
            withIntermediateDirectories: true
        )

        if let bundled = Bundle.main.url(forResource: "claude-island-state", withExtension: "py") {
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }
    }

    // MARK: - Helpers

    static func detectPython() -> String {
        // Prefer system Python to avoid broken third-party Python installations
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") {
            return "/usr/bin/python3"
        }

        // Try common Homebrew paths
        for path in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return "python3"
    }
}

// MARK: - Claude Hook Source

struct ClaudeHookSource: HookSource {
    static let hookVersion = 2

    var sourceType: SessionSource { .claude }
    var displayName: String { "Claude Code" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json").path
    }

    func install(bridgePath: String) throws {
        let settingsURL = URL(fileURLWithPath: configPath)
        let claudeDir = settingsURL.deletingLastPathComponent()

        try? FileManager.default.createDirectory(
            at: claudeDir,
            withIntermediateDirectories: true
        )

        // Install Python hook script
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        try? FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)

        if let bundled = Bundle.main.url(forResource: "claude-island-state", withExtension: "py") {
            let pythonScript = hooksDir.appendingPathComponent("claude-island-state.py")
            try? FileManager.default.removeItem(at: pythonScript)
            try? FileManager.default.copyItem(at: bundled, to: pythonScript)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: pythonScript.path
            )
        }

        updateClaudeSettings(at: settingsURL)
    }

    func uninstall() throws {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("claude-island-state.py")
        let settingsURL = URL(fileURLWithPath: configPath)

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settingsURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else {
            return
        }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { hook in
                            let cmd = hook["command"] as? String ?? ""
                            return cmd.contains("claude-island")
                        }
                    }
                    return false
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }

        if hooks.isEmpty {
            json.removeValue(forKey: "hooks")
        } else {
            json["hooks"] = hooks
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }

    func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        for hook in entryHooks {
                            if let cmd = hook["command"] as? String,
                               cmd.contains("claude-island") {
                                return true
                            }
                        }
                    }
                }
            }
        }

        return false
    }

    /// Check if the installed hook version matches current version
    func needsUpgrade() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        let installedVersion = json["_claude_island_hook_version"] as? Int ?? 0
        return isInstalled() && installedVersion < Self.hookVersion
    }

    private func updateClaudeSettings(at settingsURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        // Use shell-safe launcher path (no spaces) — it discovers the app bundle internally
        let command = HookInstaller.hookCommandPath() + " --source claude"
        let hookEntry: [[String: Any]] = [["type": "command", "command": command]]
        let hookEntryWithTimeout: [[String: Any]] = [["type": "command", "command": command, "timeout": 86400]]
        let withMatcher: [[String: Any]] = [["matcher": "*", "hooks": hookEntry]]
        let withMatcherAndTimeout: [[String: Any]] = [["matcher": "*", "hooks": hookEntryWithTimeout]]
        let withoutMatcher: [[String: Any]] = [["hooks": hookEntry]]
        let preCompactConfig: [[String: Any]] = [
            ["matcher": "auto", "hooks": hookEntry],
            ["matcher": "manual", "hooks": hookEntry]
        ]

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        let hookEvents: [(String, [[String: Any]])] = [
            ("Setup", withoutMatcher),
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Elicitation", withoutMatcher),
            ("ElicitationResult", withoutMatcher),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
            ("PostCompact", withoutMatcher),
        ]

        for (event, config) in hookEvents {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                // Remove ALL old claude-island entries (stale paths, python, etc.)
                existingEvent.removeAll { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains("claude-island")
                        }
                    }
                    return false
                }
                // Add the current correct hook entry
                existingEvent.append(contentsOf: config)
                hooks[event] = existingEvent
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks
        json["_claude_island_hook_version"] = Self.hookVersion

        // Write statusLine config if not already set by user
        if json["statusLine"] == nil {
            json["statusLine"] = [
                "command": "~/.claude-island/bin/claude-island-statusline",
                "type": "command"
            ] as [String: Any]
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }
}

// MARK: - Cline Hook Source

struct ClineHookSource: HookSource {
    private static let previousHooksEnabledKey = "_claude_island_previous_hooks_enabled"
    private static let hookNames = [
        "TaskStart",
        "TaskResume",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PreCompact",
        "TaskComplete",
        "TaskCancel",
    ]

    var sourceType: SessionSource { .cline }
    var displayName: String { "Cline" }

    var configPath: String { globalStateURL.path }

    var managedConfigPaths: [String] {
        [globalStateURL.path] + Self.hookNames.map { hooksDirectoryURL.appendingPathComponent($0).path }
    }

    private var hooksDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Cline/Hooks")
    }

    private var globalStateURL: URL {
        let env = Foundation.ProcessInfo.processInfo.environment
        if let customDir = env["CLINE_DIR"], !customDir.isEmpty {
            return URL(fileURLWithPath: customDir).appendingPathComponent("data/globalState.json")
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cline/data/globalState.json")
    }

    func install(bridgePath: String) throws {
        try FileManager.default.createDirectory(at: hooksDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: globalStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let command = HookInstaller.hookCommandPath() + " --source cline"

        for hookName in Self.hookNames {
            let hookURL = hooksDirectoryURL.appendingPathComponent(hookName)
            let script = """
            #!/bin/zsh
            RESPONSE="$(\(command) 2>/dev/null)" || true
            if [ -n "$RESPONSE" ]; then
              print -r -- "$RESPONSE"
            else
              print -r -- '{"cancel":false,"contextModification":""}'
            fi
            """
            try script.write(to: hookURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookURL.path)
        }

        updateGlobalState()
    }

    func uninstall() throws {
        for path in managedConfigPaths.dropFirst() {
            try? FileManager.default.removeItem(atPath: path)
        }

        restoreGlobalState()
    }

    func isInstalled() -> Bool {
        guard hooksEnabledInGlobalState() else { return false }

        return Self.hookNames.allSatisfy { hookName in
            let path = hooksDirectoryURL.appendingPathComponent(hookName).path
            guard FileManager.default.isExecutableFile(atPath: path),
                  let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return false
            }
            return content.contains("--source cline")
        }
    }

    private func hooksEnabledInGlobalState() -> Bool {
        guard let data = try? Data(contentsOf: globalStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        return json["hooks-enabled"] as? Bool == true
    }

    private func updateGlobalState() {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: globalStateURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        if json[Self.previousHooksEnabledKey] == nil {
            json[Self.previousHooksEnabledKey] = json["hooks-enabled"] ?? NSNull()
        }
        json["hooks-enabled"] = true

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: globalStateURL)
        }
    }

    private func restoreGlobalState() {
        guard let data = try? Data(contentsOf: globalStateURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let previous = json[Self.previousHooksEnabledKey] {
            if previous is NSNull {
                json.removeValue(forKey: "hooks-enabled")
            } else {
                json["hooks-enabled"] = previous
            }
            json.removeValue(forKey: Self.previousHooksEnabledKey)
        }

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: globalStateURL)
        }
    }
}

private struct HelperOnlySource: HookSource {
    let sourceType: SessionSource
    let displayName: String
    let helperNames: [String]

    var configPath: String {
        helperPaths.first ?? helperRoot.appendingPathComponent(".placeholder").path
    }

    var managedConfigPaths: [String] {
        helperPaths
    }

    private var helperRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin")
    }

    private var helperPaths: [String] {
        helperNames.map { helperRoot.appendingPathComponent($0).path }
    }

    func install(bridgePath: String) throws {
        // Helper-backed integrations are repaired by refreshing the centrally
        // managed launcher/helper bundle.
        HookInstaller.installLauncher()
    }

    func uninstall() throws {
        // Keep helper scripts managed centrally; disabling the wrapper-based
        // source only changes app-level affordances and status.
    }

    func isInstalled() -> Bool {
        guard AppSettings.isHookEnabled(for: sourceType) else { return false }
        return helperPaths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }
}

// MARK: - Codex Hook Source

struct CodexHookSource: HookSource {
    private struct EventConfig {
        let name: String
        let matcher: String?

        init(_ name: String, matcher: String? = nil) {
            self.name = name
            self.matcher = matcher
        }
    }

    /// Codex's current official hook surface (5 events as of 2026-04).
    /// PreToolUse/PostToolUse currently only support Bash tool.
    private static let events: [EventConfig] = [
        .init("SessionStart", matcher: "startup|resume"),
        .init("UserPromptSubmit"),
        .init("PreToolUse", matcher: "Bash"),
        .init("PostToolUse", matcher: "Bash"),
        .init("Stop"),
    ]

    var sourceType: SessionSource { .codexCLI }
    var displayName: String { "Codex CLI" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json").path
    }

    var managedConfigPaths: [String] {
        [configPath, codexConfigURL.path]
    }

    private var codexConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
    }

    private var launcherURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin/claude-island-bridge-launcher.sh")
    }

    private var legacyNotifyScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/claude-island/codex-notify.py")
    }

    private var notifyChainURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/claude-island/notify-chain.json")
    }

    func install(bridgePath: String) throws {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/claude-island")

        try? FileManager.default.createDirectory(
            at: codexDir,
            withIntermediateDirectories: true
        )

        try? FileManager.default.removeItem(at: legacyNotifyScriptURL)
        updateCodexHooks(at: URL(fileURLWithPath: configPath), bridgePath: bridgePath)
        updateCodexConfig(at: codexConfigURL)
    }

    func uninstall() throws {
        let hooksURL = URL(fileURLWithPath: configPath)

        if let data = try? Data(contentsOf: hooksURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var hooks = json["hooks"] as? [String: Any] {
            removeManagedHooks(from: &hooks)

            if hooks.isEmpty {
                json.removeValue(forKey: "hooks")
            } else {
                json["hooks"] = hooks
            }

            if let updated = try? JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                try? updated.write(to: hooksURL)
            }
        }

        restoreCodexConfig(at: codexConfigURL)

        try? FileManager.default.removeItem(at: legacyNotifyScriptURL)
        try? FileManager.default.removeItem(at: notifyChainURL)
    }

    func isInstalled() -> Bool {
        let hooksURL = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: hooksURL.path),
              let data = try? Data(contentsOf: hooksURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        guard containsManagedHook(in: hooks) else { return false }

        let configContent = (try? String(contentsOf: codexConfigURL, encoding: .utf8)) ?? ""
        guard parseBool(inSection: "features", key: "codex_hooks", from: configContent) == true else {
            return false
        }

        guard let notify = extractTopLevelArray(for: "notify", from: configContent) else {
            return false
        }

        return isManagedNotifyCommand(notify)
    }
    private func updateCodexHooks(at hooksURL: URL, bridgePath: String) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: hooksURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        removeManagedHooks(from: &hooks)

        let command = "\(bridgePath) --source codex"
        let hookCommand: [String: Any] = ["type": "command", "command": command]

        for event in Self.events {
            var entry: [String: Any] = ["hooks": [hookCommand]]
            if let matcher = event.matcher {
                entry["matcher"] = matcher
            }

            if var existingEntries = hooks[event.name] as? [[String: Any]] {
                existingEntries.append(entry)
                hooks[event.name] = existingEntries
            } else {
                hooks[event.name] = [entry]
            }
        }

        json["version"] = json["version"] as? Int ?? 1
        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: hooksURL)
        }
    }

    private func updateCodexConfig(at configURL: URL) {
        let current = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let existingNotify = extractTopLevelArray(for: "notify", from: current)

        if let existingNotify, !existingNotify.isEmpty, !isManagedNotifyCommand(existingNotify) {
            if let data = try? JSONSerialization.data(withJSONObject: existingNotify, options: [.prettyPrinted]) {
                try? data.write(to: notifyChainURL)
            }
        } else if existingNotify == nil || existingNotify?.isEmpty == true {
            try? FileManager.default.removeItem(at: notifyChainURL)
        }

        var updated = setBool(inSection: "features", key: "codex_hooks", value: true, in: current)
        updated = setTopLevelArray(
            for: "notify",
            values: [launcherURL.path, "--source", "codex_notify"],
            in: updated
        )

        if !updated.hasSuffix("\n") {
            updated.append("\n")
        }

        try? updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func restoreCodexConfig(at configURL: URL) {
        guard var current = try? String(contentsOf: configURL, encoding: .utf8) else { return }

        if let notify = extractTopLevelArray(for: "notify", from: current), isManagedNotifyCommand(notify) {
            if let data = try? Data(contentsOf: notifyChainURL),
               let previous = try? JSONSerialization.jsonObject(with: data) as? [String],
               !previous.isEmpty {
                current = setTopLevelArray(for: "notify", values: previous, in: current)
            } else {
                current = removeTopLevelValue(for: "notify", in: current)
            }

            if !current.hasSuffix("\n") {
                current.append("\n")
            }
            try? current.write(to: configURL, atomically: true, encoding: .utf8)
        }
    }

    private func containsManagedHook(in hooks: [String: Any]) -> Bool {
        hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains(where: Self.isManagedHookEntry)
        }
    }

    private func removeManagedHooks(from hooks: inout [String: Any]) {
        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll(where: Self.isManagedHookEntry)
                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }
    }

    nonisolated private static func isManagedHookEntry(_ entry: [String: Any]) -> Bool {
        if let command = entry["command"] as? String {
            return command.contains("claude-island") && command.contains("--source codex")
        }

        if let hooks = entry["hooks"] as? [[String: Any]] {
            return hooks.contains {
                (($0["command"] as? String)?.contains("claude-island") == true) &&
                (($0["command"] as? String)?.contains("--source codex") == true)
            }
        }

        return false
    }

    private func isManagedNotifyCommand(_ command: [String]) -> Bool {
        guard let executable = command.first else { return false }

        if executable == legacyNotifyScriptURL.path || executable.hasSuffix("/codex-notify.py") {
            return true
        }

        let isBridgeLauncher = executable == launcherURL.path ||
            executable.hasSuffix("/claude-island-bridge-launcher.sh")

        return isBridgeLauncher &&
            command.contains("--source") &&
            command.contains("codex_notify")
    }

    private func extractTopLevelArray(for key: String, from content: String) -> [String]? {
        let lines = content.components(separatedBy: .newlines)
        var startLine: Int?
        var collected: [String] = []
        var bracketBalance = 0
        var currentTable: String?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentTable = String(trimmed.dropFirst().dropLast())
            }

            if startLine == nil,
               currentTable == nil,
               hasKeyAssignment(trimmed, key: key) {
                startLine = index
            }

            if let startLine, index >= startLine {
                collected.append(line)
                bracketBalance += line.filter { $0 == "[" }.count
                bracketBalance -= line.filter { $0 == "]" }.count
                if bracketBalance <= 0 {
                    break
                }
            }
        }

        guard !collected.isEmpty else { return nil }

        let arrayText = collected.joined(separator: "\n")
        guard let start = arrayText.firstIndex(of: "["),
              let end = arrayText.lastIndex(of: "]"),
              start < end else {
            return nil
        }

        let inner = arrayText[arrayText.index(after: start)..<end]
        let pattern = #""((?:\\.|[^"])*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(inner.startIndex..<inner.endIndex, in: inner)

        return regex.matches(in: String(inner), options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: inner) else {
                return nil
            }

            let raw = String(inner[range])
            let json = "\"\(raw)\""
            if let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(String.self, from: data) {
                return decoded
            }
            return raw
        }
    }

    private func setTopLevelArray(for key: String, values: [String], in content: String) -> String {
        let replacement = "\(key) = [\(values.map(tomlString).joined(separator: ", "))]"
        return replaceTopLevelValue(for: key, replacement: replacement, in: content)
    }

    private func removeTopLevelValue(for key: String, in content: String) -> String {
        replaceTopLevelValue(for: key, replacement: nil, in: content)
    }

    private func replaceTopLevelValue(for key: String, replacement: String?, in content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var startIndex: Int?
        var endIndex: Int?
        var bracketBalance = 0
        var currentTable: String?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentTable = String(trimmed.dropFirst().dropLast())
            }

            if startIndex == nil,
               currentTable == nil,
               hasKeyAssignment(trimmed, key: key) {
                startIndex = index
                bracketBalance += line.filter { $0 == "[" }.count
                bracketBalance -= line.filter { $0 == "]" }.count
                if bracketBalance <= 0 {
                    endIndex = index
                    break
                }
                continue
            }

            if let startIndex, index > startIndex {
                bracketBalance += line.filter { $0 == "[" }.count
                bracketBalance -= line.filter { $0 == "]" }.count
                if bracketBalance <= 0 {
                    endIndex = index
                    break
                }
            }
        }

        var outputLines = lines
        if let startIndex, let endIndex {
            let replacementLines = replacement.map { [$0] } ?? []
            outputLines.replaceSubrange(startIndex...endIndex, with: replacementLines)
            return outputLines.joined(separator: "\n")
        }

        guard let replacement else { return content }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return replacement
        }

        if let firstTableIndex = lines.firstIndex(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }) {
            outputLines.insert("", at: firstTableIndex)
            outputLines.insert(replacement, at: firstTableIndex)
        } else {
            outputLines.append(replacement)
        }

        return outputLines.joined(separator: "\n")
    }

    private func parseBool(inSection section: String, key: String, from content: String) -> Bool? {
        let lines = content.components(separatedBy: .newlines)
        var currentSection: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }

            guard currentSection == section,
                  hasKeyAssignment(trimmed, key: key),
                  let rawValue = trimmed.split(separator: "=", maxSplits: 1).last else {
                continue
            }

            return rawValue.trimmingCharacters(in: .whitespaces).lowercased() == "true"
        }

        return nil
    }

    private func setBool(inSection section: String, key: String, value: Bool, in content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var output = lines
        var sectionIndex: Int?
        var insertIndex: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "[\(section)]" {
                sectionIndex = index
                insertIndex = index + 1
                continue
            }

            if let sectionIndex, index > sectionIndex,
               trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                insertIndex = index
                break
            }

            if let sectionIndex, index > sectionIndex,
               hasKeyAssignment(trimmed, key: key) {
                output[index] = "\(key) = \(value ? "true" : "false")"
                return output.joined(separator: "\n")
            }
        }

        if let insertIndex {
            output.insert("\(key) = \(value ? "true" : "false")", at: insertIndex)
            return output.joined(separator: "\n")
        }

        var result = content
        if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !result.hasSuffix("\n") {
            result.append("\n")
        }
        if !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append("\n")
        }
        result.append("[\(section)]\n\(key) = \(value ? "true" : "false")")
        return result
    }

    private func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func hasKeyAssignment(_ trimmedLine: String, key: String) -> Bool {
        trimmedLine.hasPrefix("\(key) ") || trimmedLine.hasPrefix("\(key)=")
    }
}

// MARK: - Gemini Hook Source

struct GeminiHookSource: HookSource {
    private struct EventConfig {
        let name: String
        let matcher: String?

        init(_ name: String, matcher: String? = nil) {
            self.name = name
            self.matcher = matcher
        }
    }

    /// Gemini's native hook events. These must match the official Gemini CLI docs.
    private static let events: [EventConfig] = [
        .init("SessionStart"),
        .init("BeforeAgent"),
        .init("BeforeTool", matcher: "*"),
        .init("AfterTool", matcher: "*"),
        .init("BeforeModel"),
        .init("BeforeToolSelection"),
        .init("AfterModel"),
        .init("AfterAgent"),
        .init("Notification"),
        .init("PreCompress"),
        .init("SessionEnd"),
    ]

    var sourceType: SessionSource { .gemini }
    var displayName: String { "Gemini CLI" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/settings.json").path
    }

    func install(bridgePath: String) throws {
        let configURL = URL(fileURLWithPath: configPath)
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        removeClaudeIslandHooks(from: &hooks)

        let command = "\(bridgePath) --source gemini"

        for event in Self.events {
            let hookCommand: [String: Any] = ["type": "command", "command": command]

            var entry: [String: Any] = ["hooks": [hookCommand]]
            if let matcher = event.matcher {
                entry["matcher"] = matcher
            }

            if var existingEntries = hooks[event.name] as? [[String: Any]] {
                existingEntries.append(entry)
                hooks[event.name] = existingEntries
            } else {
                hooks[event.name] = [entry]
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try data.write(to: configURL)
        }
    }

    func uninstall() throws {
        let configURL = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }

        removeClaudeIslandHooks(from: &hooks)

        if hooks.isEmpty { json.removeValue(forKey: "hooks") } else { json["hooks"] = hooks }

        if let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try updated.write(to: configURL)
        }
    }

    func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        return hooks.values.contains { value in
            if let entries = value as? [[String: Any]] {
                return entries.contains(where: Self.isClaudeIslandHookEntry)
            }
            return false
        }
    }

    private func removeClaudeIslandHooks(from hooks: inout [String: Any]) {
        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll(where: Self.isClaudeIslandHookEntry)
                if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
            }
        }
    }

    nonisolated private static func isClaudeIslandHookEntry(_ entry: [String: Any]) -> Bool {
        if let command = entry["command"] as? String {
            return command.contains("claude-island")
        }

        if let hooks = entry["hooks"] as? [[String: Any]] {
            return hooks.contains { ($0["command"] as? String)?.contains("claude-island") == true }
        }

        return false
    }
}

// MARK: - Cursor Hook Source

/// Cursor hook source
/// Config: ~/.cursor/hooks.json
/// Format: {"version": 1, "hooks": {"eventName": [{"command": "..."}]}}
/// Events: beforeSubmitPrompt, beforeShellExecution, beforeMCPExecution, beforeReadFile, afterFileEdit, stop
/// Docs: https://cursor.com/docs/hooks
struct CursorHookSource: HookSource {
    var sourceType: SessionSource { .cursor }
    var displayName: String { "Cursor" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json").path
    }

    /// Cursor hook events and their timeout settings
    private static let events: [(name: String, timeout: Int?)] = [
        ("beforeSubmitPrompt", nil),
        ("beforeShellExecution", 30),
        ("beforeMCPExecution", 30),
        ("beforeReadFile", nil),
        ("afterFileEdit", nil),
        ("stop", nil),
    ]

    func install(bridgePath: String) throws {
        let configURL = URL(fileURLWithPath: configPath)
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        json["version"] = 1

        var hooks = json["hooks"] as? [String: Any] ?? [:]

        for event in Self.events {
            let command = "\(bridgePath) --source cursor --event \(event.name)"
            var hookEntry: [String: Any] = ["command": command]
            if let timeout = event.timeout {
                hookEntry["timeout"] = timeout
            }

            if var existing = hooks[event.name] as? [[String: Any]] {
                let hasOur = existing.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                if !hasOur {
                    existing.append(hookEntry)
                    hooks[event.name] = existing
                }
            } else {
                hooks[event.name] = [hookEntry]
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try data.write(to: configURL)
        }
    }

    func uninstall() throws {
        let configURL = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { ($0["command"] as? String)?.contains("claude-island") == true }
                if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
            }
        }

        if hooks.isEmpty { json.removeValue(forKey: "hooks") } else { json["hooks"] = hooks }

        if let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try updated.write(to: configURL)
        }
    }

    func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        return hooks.values.contains { value in
            if let entries = value as? [[String: Any]] {
                return entries.contains { ($0["command"] as? String)?.contains("claude-island") == true }
            }
            return false
        }
    }
}

// MARK: - Windsurf Hook Source

struct WindsurfHookSource: HookSource {
    var sourceType: SessionSource { .windsurf }
    var displayName: String { "Windsurf" }

    var configPath: String {
        userConfigURL.path
    }

    var managedConfigPaths: [String] {
        configURLsForManagement().map(\.path)
    }

    private static let events = [
        "pre_user_prompt",
        "post_read_code",
        "pre_run_command",
        "post_run_command",
        "pre_mcp_tool_use",
        "post_mcp_tool_use",
        "pre_read_code",
        "pre_write_code",
        "post_write_code",
        "post_cascade_response",
        "post_cascade_response_with_transcript",
        "post_setup_worktree"
    ]

    private var userConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codeium/windsurf/hooks.json")
    }

    private var workspaceConfigURL: URL? {
        let workspaceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let workspaceDir = workspaceRoot.appendingPathComponent(".windsurf")
        let workspaceHooks = workspaceDir.appendingPathComponent("hooks.json")
        guard FileManager.default.fileExists(atPath: workspaceDir.path) ||
                FileManager.default.fileExists(atPath: workspaceHooks.path) else {
            return nil
        }
        return workspaceHooks
    }

    private func configURLsForManagement() -> [URL] {
        var urls = [userConfigURL]
        if let workspaceConfigURL {
            urls.append(workspaceConfigURL)
        }
        return urls
    }

    func install(bridgePath: String) throws {
        HookInstaller.installLauncher()
        for configURL in configURLsForManagement() {
            try? FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var json: [String: Any] = [:]
            if let data = try? Data(contentsOf: configURL),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json = existing
            }

            var hooks = json["hooks"] as? [String: Any] ?? [:]
            let command = "\(HookInstaller.hookCommandPath()) --source windsurf"

            for event in Self.events {
                let hookEntry: [String: Any] = [
                    "command": command,
                    "show_output": false
                ]

                if var existing = hooks[event] as? [[String: Any]] {
                    existing.removeAll { ($0["command"] as? String)?.contains("claude-island") == true }
                    existing.append(hookEntry)
                    hooks[event] = existing
                } else {
                    hooks[event] = [hookEntry]
                }
            }

            json["hooks"] = hooks

            if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try data.write(to: configURL)
            }
        }
    }

    func uninstall() throws {
        for configURL in configURLsForManagement() {
            guard let data = try? Data(contentsOf: configURL),
                  var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var hooks = json["hooks"] as? [String: Any] else { continue }

            for (event, value) in hooks {
                if var entries = value as? [[String: Any]] {
                    entries.removeAll { ($0["command"] as? String)?.contains("claude-island") == true }
                    if entries.isEmpty {
                        hooks.removeValue(forKey: event)
                    } else {
                        hooks[event] = entries
                    }
                }
            }

            if hooks.isEmpty { json.removeValue(forKey: "hooks") } else { json["hooks"] = hooks }

            if let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try updated.write(to: configURL)
            }
        }
    }

    func isInstalled() -> Bool {
        for configURL in configURLsForManagement() {
            guard let data = try? Data(contentsOf: configURL),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = json["hooks"] as? [String: Any] else { continue }

            let hasManagedHook = hooks.values.contains { value in
                if let entries = value as? [[String: Any]] {
                    return entries.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                }
                return false
            }
            if hasManagedHook {
                return true
            }
        }
        return false
    }
}

// MARK: - Kimi Hook Source

struct KimiHookSource: HookSource {
    var sourceType: SessionSource { .kimiCLI }
    var displayName: String { "Kimi CLI" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kimi/config.toml").path
    }

    private let blockStart = "# claude-island-kimi-hooks:start"
    private let blockEnd = "# claude-island-kimi-hooks:end"

    var managedConfigPaths: [String] {
        [configPath, helperRoot.appendingPathComponent("claude-island-kimi-print").path]
    }

    private var helperRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin")
    }

    func install(bridgePath: String) throws {
        HookInstaller.installLauncher()
        let configURL = URL(fileURLWithPath: configPath)
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let current = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let cleaned = removeManagedBlock(from: current)
        let merged = appendManagedBlock(to: cleaned, command: "\(HookInstaller.hookCommandPath()) --source kimi_cli")
        try merged.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func uninstall() throws {
        let configURL = URL(fileURLWithPath: configPath)
        let current = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let cleaned = removeManagedBlock(from: current)
        try cleaned.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func isInstalled() -> Bool {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return false }
        return content.contains(blockStart) && content.contains("--source kimi_cli")
    }

    private func removeManagedBlock(from content: String) -> String {
        guard let start = content.range(of: blockStart),
              let end = content.range(of: blockEnd) else {
            return content
        }

        let removeRange = start.lowerBound..<end.upperBound
        var updated = content.replacingCharacters(in: removeRange, with: "")
        while updated.contains("\n\n\n") {
            updated = updated.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return updated.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendManagedBlock(to content: String, command: String) -> String {
        let events: [(String, Int?)] = [
            ("SessionStart", nil),
            ("SessionEnd", nil),
            ("UserPromptSubmit", nil),
            ("PreToolUse", 120),
            ("PostToolUse", nil),
            ("PostToolUseFailure", nil),
            ("Notification", nil),
            ("Stop", nil),
            ("StopFailure", nil),
            ("PreCompact", nil),
            ("PostCompact", nil),
            ("SubagentStart", nil),
            ("SubagentStop", nil),
        ]

        var lines = [blockStart]
        for (index, event) in events.enumerated() {
            if index > 0 {
                lines.append("")
            }
            lines.append("[[hooks]]")
            lines.append("event = \"\(event.0)\"")
            lines.append("command = \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"")
            if let timeout = event.1 {
                lines.append("timeout = \(timeout)")
            }
        }
        lines.append(blockEnd)

        let block = lines.joined(separator: "\n")
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return block + "\n"
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + block + "\n"
    }
}

// MARK: - Kiro Hook Source

struct KiroHookSource: HookSource {
    var sourceType: SessionSource { .kiroCLI }
    var displayName: String { "Kiro CLI" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kiro/agents/claude-island.json").path
    }

    var managedConfigPaths: [String] {
        [configPath, helperRoot.appendingPathComponent("claude-island-kiro").path]
    }

    private var helperRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin")
    }

    func install(bridgePath: String) throws {
        HookInstaller.installLauncher()
        let configURL = URL(fileURLWithPath: configPath)
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let command = "\(HookInstaller.hookCommandPath()) --source kiro_cli"
        let hookEntry: [String: Any] = [
            "type": "command",
            "command": command
        ]

        let json: [String: Any] = [
            "name": "claude-island",
            "description": "Claude Island integration agent",
            "hooks": [
                "agentSpawn": [hookEntry],
                "userPromptSubmit": [hookEntry],
                "preToolUse": [[
                    "type": "command",
                    "command": command,
                    "timeout": 120
                ]],
                "postToolUse": [hookEntry],
                "notification": [hookEntry],
                "stop": [hookEntry],
                "sessionEnd": [hookEntry],
                "sessionClear": [hookEntry]
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try data.write(to: configURL)
        }
    }

    func uninstall() throws {
        try? FileManager.default.removeItem(atPath: configPath)
    }

    func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        return hooks.values.contains { value in
            if let entries = value as? [[String: Any]] {
                return entries.contains { ($0["command"] as? String)?.contains("claude-island") == true }
            }
            return false
        }
    }
}

// MARK: - Amp Hook Source

struct AmpHookSource: HookSource {
    var sourceType: SessionSource { .ampCLI }
    var displayName: String { "Amp CLI" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/amp/plugins/claude-island.ts").path
    }

    var managedConfigPaths: [String] {
        [
            configPath,
            helperRoot.appendingPathComponent("claude-island-amp").path,
            helperRoot.appendingPathComponent("claude-island-amp-exec").path,
            helperRoot.appendingPathComponent("claude-island-amp-stream").path
        ]
    }

    private var helperRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin")
    }

    func install(bridgePath: String) throws {
        HookInstaller.installLauncher()
        let configURL = URL(fileURLWithPath: configPath)
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let launcher = HookInstaller.hookCommandPath()
        let script = """
        // @i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now
        import type { PluginAPI } from '@ampcode/plugin'
        import { randomUUID } from 'node:crypto'
        import { spawnSync } from 'node:child_process'
        import process from 'node:process'

        export default function (amp: PluginAPI) {
          let sessionId = nextSessionId()

          amp.on('session.start', (event) => {
            sessionId = stableSessionId(event) || nextSessionId()
            send({
              hook_event_name: 'SessionStart',
              session_id: sessionId,
              cwd: process.cwd(),
            })
          })

          amp.on('agent.start', (event) => {
            send({
              hook_event_name: 'UserPromptSubmit',
              session_id: sessionId,
              cwd: process.cwd(),
              prompt: event.message,
            })
          })

          amp.on('tool.call', (event) => {
            const result = sendAndReceive({
              hook_event_name: 'PreToolUse',
              session_id: sessionId,
              cwd: process.cwd(),
              tool_name: event.tool,
              tool_input: event.input,
              tool_use_id: event.toolUseID,
            })

            if (result?.permissionDecision === 'deny') {
              return {
                action: 'reject-and-continue',
                message: result.permissionDecisionReason || `Claude Island rejected ${event.tool}.`,
              }
            }

            return { action: 'allow' }
          })

          amp.on('tool.result', (event) => {
            send({
              hook_event_name: event.status === 'error' ? 'PostToolUseFailure' : 'PostToolUse',
              session_id: sessionId,
              cwd: process.cwd(),
              tool_name: event.tool,
              tool_input: event.input,
              tool_use_id: event.toolUseID,
              tool_response: stringify(event.output),
              error: event.error,
            })
          })

          amp.on('agent.end', (event) => {
            const lastText = extractLastAssistantText(event.messages)
            send({
              hook_event_name: 'Stop',
              session_id: sessionId,
              cwd: process.cwd(),
              last_assistant_message: lastText,
              message: event.status,
            })
          })
        }

        function nextSessionId() {
          return `amp-${randomUUID()}`
        }

        function stableSessionId(event) {
          const candidates = [
            event?.sessionID,
            event?.sessionId,
            event?.threadID,
            event?.threadId,
            event?.thread?.id,
            event?.trajectoryID,
            event?.trajectoryId,
          ]
          const value = candidates.find((candidate) => typeof candidate === 'string' && candidate.length > 0)
          return value ? `amp-${value}` : undefined
        }

        function spawnBridge(input) {
          return spawnSync(process.env.SHELL || '/bin/sh', ['-lc', '\(launcher) --source amp_cli'], {
            input: JSON.stringify(input),
            encoding: 'utf8',
          })
        }

        function send(input) {
          spawnBridge(input)
        }

        function sendAndReceive(input) {
          const result = spawnBridge(input)
          if (!result.stdout) return null
          try {
            return JSON.parse(result.stdout)
          } catch {
            return null
          }
        }

        function stringify(value) {
          if (value == null) return undefined
          if (typeof value === 'string') return value
          try {
            return JSON.stringify(value)
          } catch {
            return String(value)
          }
        }

        function extractLastAssistantText(messages) {
          if (!Array.isArray(messages)) return undefined
          const assistant = [...messages].reverse().find((m) => m && m.role === 'assistant')
          if (!assistant || !Array.isArray(assistant.content)) return undefined
          const parts = assistant.content
            .filter((block) => block && block.type === 'text' && typeof block.text === 'string')
            .map((block) => block.text)
          return parts.length > 0 ? parts.join('\\n') : undefined
        }
        """

        try script.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func uninstall() throws {
        try? FileManager.default.removeItem(atPath: configPath)
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: configPath)
    }
}

// MARK: - OpenCode Hook Source

struct OpenCodeHookSource: HookSource {
    var sourceType: SessionSource { .opencode }
    var displayName: String { "OpenCode" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/plugins/claude-island.js").path
    }

    func install(bridgePath: String) throws {
        let configURL = URL(fileURLWithPath: configPath)
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let script = """
        // Claude Island integration for OpenCode
        const { execSync } = require('child_process');

        module.exports = {
          name: 'claude-island',
          hooks: {
            onSessionStart(session) {
              notify('SessionStart', session);
            },
            onSessionEnd(session) {
              notify('SessionEnd', session);
            },
            onToolStart(tool, session) {
              notify('PreToolUse', session, tool);
            },
            onToolEnd(tool, session) {
              notify('PostToolUse', session, tool);
            },
            onStop(session) {
              notify('Stop', session);
            }
          }
        };

        function notify(event, session, tool) {
          const payload = {
            hook_event_name: event,
            session_id: session?.id || 'unknown',
            cwd: session?.cwd || process.cwd(),
            tool_name: tool?.name,
            tool_input: tool?.input,
            tool_use_id: tool?.id,
            tool_response: tool?.result || tool?.output,
            pid: process.pid
          };
          try {
            execSync('\(bridgePath) --source opencode', {
              input: JSON.stringify(payload),
              timeout: 5000,
              stdio: ['pipe', 'pipe', 'pipe']
            });
          } catch (e) {
            if (process.env.CLAUDE_ISLAND_DEBUG) {
              console.error('[claude-island]', e.message);
            }
          }
        }
        """

        try script.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func uninstall() throws {
        try? FileManager.default.removeItem(atPath: configPath)
    }

    func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: configPath)
    }
}

// MARK: - Copilot Hook Source

struct CopilotHookSource: HookSource {
    var sourceType: SessionSource { .copilot }
    var displayName: String { "Copilot" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/config.json").path
    }

    var managedConfigPaths: [String] {
        [configPath, helperRoot.appendingPathComponent("claude-island-copilot-json").path]
    }

    private var helperRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-island/bin")
    }

    func install(bridgePath: String) throws {
        HookInstaller.installLauncher()
        let configURL = URL(fileURLWithPath: configPath)
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        let command = "\(HookInstaller.hookCommandPath()) --source copilot"
        let events: [(String, Int?)] = [
            ("sessionStart", nil),
            ("sessionEnd", nil),
            ("preToolUse", 120),
            ("postToolUse", nil),
            ("postToolUseFailure", nil),
            ("userPromptSubmitted", nil),
            ("errorOccurred", nil),
            ("preCompact", nil),
            ("notification", nil),
            ("stop", nil),
        ]

        for (event, timeoutSec) in events {
            var hookEntry: [String: Any] = ["type": "command", "command": command]
            if let timeoutSec {
                hookEntry["timeoutSec"] = timeoutSec
            }
            if var existing = hooks[event] as? [[String: Any]] {
                existing.removeAll { isObsoleteCopilotEntry($0) }
                let hasOur = existing.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                if !hasOur {
                    existing.append(hookEntry)
                    hooks[event] = existing
                } else {
                    hooks[event] = existing
                }
            } else {
                hooks[event] = [hookEntry]
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try data.write(to: configURL)
        }
    }

    func uninstall() throws {
        let configURL = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll {
                    ($0["command"] as? String)?.contains("claude-island") == true || isObsoleteCopilotEntry($0)
                }
                if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
            }
        }

        if hooks.isEmpty { json.removeValue(forKey: "hooks") } else { json["hooks"] = hooks }

        if let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try updated.write(to: configURL)
        }
    }

    func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        return hooks.values.contains { value in
            if let entries = value as? [[String: Any]] {
                return entries.contains { ($0["command"] as? String)?.contains("claude-island") == true }
            }
            return false
        }
    }

    private func isObsoleteCopilotEntry(_ entry: [String: Any]) -> Bool {
        let candidates: [String?] = [
            entry["command"] as? String,
            entry["bash"] as? String,
            entry["powershell"] as? String
        ]
        return candidates.contains { $0?.contains("vibe-island") == true }
    }
}

// MARK: - Claude-Compatible Settings Hook Source (shared by CodeBuddy, Qoder, Droid)
//
// These CLIs use the same settings.json format as Claude Code:
//   PascalCase event names, nested { matcher?, hooks: [{ type, command, timeout? }] } structure.
// Each source can customize which events to register.

private struct GenericSettingsHookSource: HookSource {
    /// Describes a single hook event to register.
    struct EventConfig {
        let name: String       // PascalCase event name, e.g. "PreToolUse"
        let matcher: String?   // nil = no matcher, "*" = wildcard
        let timeout: Int?      // nil = use CLI default

        init(_ name: String, matcher: String? = nil, timeout: Int? = nil) {
            self.name = name
            self.matcher = matcher
            self.timeout = timeout
        }
    }

    let sourceType: SessionSource
    let displayName: String
    let configPath: String
    private let sourceName: String
    private let events: [EventConfig]

    /// Standard event set for Claude Code-compatible CLIs.
    static let defaultEvents: [EventConfig] = [
        EventConfig("SessionStart"),
        EventConfig("SessionEnd"),
        EventConfig("PreToolUse", matcher: "*"),
        EventConfig("PostToolUse", matcher: "*"),
        EventConfig("UserPromptSubmit"),
        EventConfig("Stop"),
        EventConfig("Notification", matcher: "*"),
        EventConfig("PreCompact"),
    ]

    init(sourceType: SessionSource, displayName: String, configDir: String,
         sourceName: String, events: [EventConfig]? = nil) {
        self.sourceType = sourceType
        self.displayName = displayName
        self.configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("\(configDir)/settings.json").path
        self.sourceName = sourceName
        self.events = events ?? Self.defaultEvents
    }

    func install(bridgePath: String) throws {
        let configURL = URL(fileURLWithPath: configPath)
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        // Use shell-safe launcher path (same as Claude Code)
        let command = HookInstaller.hookCommandPath() + " --source \(sourceName)"
        var hooks = json["hooks"] as? [String: Any] ?? [:]

        for event in events {
            // Build hook command entry
            var hookCmd: [String: Any] = ["type": "command", "command": command]
            if let timeout = event.timeout {
                hookCmd["timeout"] = timeout
            }

            // Build event entry: { matcher?, hooks: [hookCmd] }
            var entry: [String: Any] = ["hooks": [hookCmd]]
            if let matcher = event.matcher {
                entry["matcher"] = matcher
            }

            if var existingEntries = hooks[event.name] as? [[String: Any]] {
                // Remove old claude-island entries (stale paths, upgrades, etc.)
                existingEntries.removeAll { e in
                    if let entryHooks = e["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                    }
                    return false
                }
                existingEntries.append(entry)
                hooks[event.name] = existingEntries
            } else {
                hooks[event.name] = [entry]
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try data.write(to: configURL)
        }
    }

    func uninstall() throws {
        let configURL = URL(fileURLWithPath: configPath)
        guard let data = try? Data(contentsOf: configURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }

        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    // Check nested hooks array for claude-island commands
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                    }
                    return false
                }
                if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
            }
        }

        if hooks.isEmpty { json.removeValue(forKey: "hooks") } else { json["hooks"] = hooks }

        if let updated = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try updated.write(to: configURL)
        }
    }

    func isInstalled() -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        return hooks.values.contains { value in
            if let entries = value as? [[String: Any]] {
                return entries.contains { entry in
                    // Check nested hooks array
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                    }
                    return false
                }
            }
            return false
        }
    }
}

// MARK: - Qoder Hook Source

struct QoderHookSource: HookSource {
    /// Qoder supports only 5 events (no SessionStart/End, Notification, PreCompact, SubagentStop).
    /// Includes PostToolUseFailure which is unique to Qoder.
    /// Permissions handled via PreToolUse's `permissionDecision`, no PermissionRequest event.
    /// See: https://docs.qoder.com/zh/extensions/hooks
    private static let qoderEvents: [GenericSettingsHookSource.EventConfig] = [
        .init("UserPromptSubmit"),
        .init("PreToolUse", matcher: "*", timeout: 120),  // Extended for implicit permission approval
        .init("PostToolUse", matcher: "*"),
        .init("PostToolUseFailure", matcher: "*"),
        .init("Stop"),
    ]

    private let inner = GenericSettingsHookSource(
        sourceType: .qoder, displayName: "Qoder", configDir: ".qoder",
        sourceName: "qoder", events: qoderEvents
    )
    var sourceType: SessionSource { inner.sourceType }
    var displayName: String { inner.displayName }
    var configPath: String { inner.configPath }
    func install(bridgePath: String) throws { try inner.install(bridgePath: bridgePath) }
    func uninstall() throws { try inner.uninstall() }
    func isInstalled() -> Bool { inner.isInstalled() }
}

// MARK: - Droid Hook Source

struct DroidHookSource: HookSource {
    /// Droid is Claude Code-compatible and already in hookSpecificOutputSources,
    /// so adding PermissionRequest enables Notch-based permission approval.
    private static let droidEvents: [GenericSettingsHookSource.EventConfig] =
        GenericSettingsHookSource.defaultEvents + [
            .init("SubagentStop"),
            .init("PermissionRequest", matcher: "*", timeout: 86400),
        ]

    private let inner = GenericSettingsHookSource(
        sourceType: .droid, displayName: "Droid", configDir: ".factory", sourceName: "droid",
        events: droidEvents
    )
    var sourceType: SessionSource { inner.sourceType }
    var displayName: String { inner.displayName }
    var configPath: String { inner.configPath }
    func install(bridgePath: String) throws { try inner.install(bridgePath: bridgePath) }
    func uninstall() throws { try inner.uninstall() }
    func isInstalled() -> Bool { inner.isInstalled() }
}

// MARK: - CodeBuddy Hook Source

struct CodeBuddyHookSource: HookSource {
    /// CodeBuddy supports 7 events (no Notification, no SubagentStop, no PermissionRequest).
    /// Permissions are handled via PreToolUse's `permissionDecision` field, not a separate event.
    /// See: https://www.codebuddy.ai/docs/ide/Features/hooks
    private static let codeBuddyEvents: [GenericSettingsHookSource.EventConfig] = [
        .init("SessionStart"),
        .init("SessionEnd"),
        .init("PreToolUse", matcher: "*", timeout: 120),  // Extended for implicit permission approval
        .init("PostToolUse", matcher: "*"),
        .init("UserPromptSubmit"),
        .init("Stop"),
        .init("PreCompact"),
    ]

    private let inner = GenericSettingsHookSource(
        sourceType: .codebuddy, displayName: "CodeBuddy", configDir: ".codebuddy",
        sourceName: "codebuddy", events: codeBuddyEvents
    )
    var sourceType: SessionSource { inner.sourceType }
    var displayName: String { inner.displayName }
    var configPath: String { inner.configPath }
    func install(bridgePath: String) throws { try inner.install(bridgePath: bridgePath) }
    func uninstall() throws { try inner.uninstall() }
    func isInstalled() -> Bool { inner.isInstalled() }
}

// MARK: - Trae Hook Source

struct TraeHookSource: HookSource {
    private let inner = GenericSettingsHookSource(
        sourceType: .trae, displayName: "Trae", configDir: ".trae", sourceName: "trae"
    )
    var sourceType: SessionSource { inner.sourceType }
    var displayName: String { inner.displayName }
    var configPath: String { inner.configPath }
    func install(bridgePath: String) throws { try inner.install(bridgePath: bridgePath) }
    func uninstall() throws { try inner.uninstall() }
    func isInstalled() -> Bool { inner.isInstalled() }
}
