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
    var displayName: String { get }
    func install(bridgePath: String) throws
    func uninstall() throws
    func isInstalled() -> Bool
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
        CodexHookSource(),
        GeminiHookSource(),
        CursorHookSource(),
        OpenCodeHookSource(),
        CopilotHookSource(),
        QoderHookSource(),
        DroidHookSource(),
        CodeBuddyHookSource(),
        TraeHookSource()
    ]

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

        // Droid: check ~/.droid
        if fm.fileExists(atPath: "\(home)/.droid") {
            installed.append(.droid)
        }

        // CodeBuddy: check ~/.codebuddy
        if fm.fileExists(atPath: "\(home)/.codebuddy") {
            installed.append(.codebuddy)
        }

        // Trae: check ~/.trae
        if fm.fileExists(atPath: "\(home)/.trae") {
            installed.append(.trae)
        }

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
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompactConfig),
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

// MARK: - Codex Hook Source

struct CodexHookSource: HookSource {
    var sourceType: SessionSource { .codexCLI }
    var displayName: String { "Codex CLI" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/hooks.json").path
    }

    private var scriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/claude-island/codex-island-hook.py")
    }

    func install(bridgePath: String) throws {
        let codexDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/claude-island")
        let binDir = codexDir.appendingPathComponent("bin")

        try? FileManager.default.createDirectory(
            at: binDir,
            withIntermediateDirectories: true
        )

        writeCodexHookScript(at: scriptURL)
        updateCodexHooks(at: URL(fileURLWithPath: configPath), scriptURL: scriptURL)
    }

    func uninstall() throws {
        let hooksURL = URL(fileURLWithPath: configPath)

        if let data = try? Data(contentsOf: hooksURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var hooks = json["hooks"] as? [String: Any] {
            removeManagedHooks(from: &hooks, scriptPath: scriptURL.path)

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

        try? FileManager.default.removeItem(at: scriptURL)
    }

    func isInstalled() -> Bool {
        let hooksURL = URL(fileURLWithPath: configPath)
        guard FileManager.default.fileExists(atPath: hooksURL.path),
              FileManager.default.fileExists(atPath: scriptURL.path),
              let data = try? Data(contentsOf: hooksURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        return containsManagedHook(in: hooks, scriptPath: scriptURL.path)
    }

    private func writeCodexHookScript(at url: URL) {
        let script = """
        #!/usr/bin/env python3
        import json, os, socket, sys

        SOCKET_PATH = os.environ.get("CLAUDE_ISLAND_SOCKET_PATH", "/tmp/claude-island.sock")

        def first_string(*values):
            for v in values:
                if isinstance(v, str) and v: return v
            return None

        def nested(obj, *keys):
            c = obj
            for k in keys:
                if not isinstance(c, dict): return None
                c = c.get(k)
            return c

        def normalize(name):
            v = (name or "").strip()
            if not v: return "unknown"
            a = {"sessionstart":"SessionStart","sessionend":"SessionEnd","userpromptsubmitted":"UserPromptSubmit",
                 "pretooluse":"PreToolUse","posttooluse":"PostToolUse","permissionrequest":"PermissionRequest",
                 "agentstop":"Stop","subagentstop":"SubagentStop","notification":"Notification",
                 "precompact":"PreCompact","erroroccurred":"Notification"}
            return a.get(v.replace("_","").replace("-","").lower(), v)

        def infer_status(n):
            m = {"PreToolUse":"running_tool","PostToolUse":"processing","UserPromptSubmit":"processing",
                 "PermissionRequest":"waiting_for_approval","SessionStart":"waiting_for_input",
                 "Stop":"waiting_for_input","SubagentStop":"waiting_for_input",
                 "SessionEnd":"ended","PreCompact":"compacting"}
            return m.get(n, "unknown")

        def build(data):
            ev = normalize(first_string(data.get("hook_event_name"),data.get("hookEventName"),data.get("event"),data.get("type")))
            sid = first_string(data.get("session_id"),data.get("sessionId"),nested(data,"session","id"),data.get("id")) or "unknown"
            cwd = first_string(data.get("cwd"),nested(data,"session","cwd"),data.get("workingDirectory")) or ""
            p = {"session_id":sid,"source":"codex_cli","cwd":cwd,"event":ev,"status":infer_status(ev),"approval_channel":"none"}
            ti = data.get("tool_input") or data.get("toolInput") or (data.get("tool",{}).get("input") if isinstance(data.get("tool"),dict) else None)
            tn = first_string(data.get("tool_name"),data.get("toolName"),nested(data,"tool","name"),data.get("tool") if isinstance(data.get("tool"),str) else None)
            tuid = first_string(data.get("tool_use_id"),data.get("toolUseId"),nested(data,"tool","id"))
            pid = data.get("pid") or nested(data,"session","pid")
            tty = first_string(data.get("tty"),nested(data,"session","tty"))
            if pid: p["pid"]=pid
            if tty: p["tty"]=tty
            if tn: p["tool"]=tn
            if ti: p["tool_input"]=ti
            if tuid: p["tool_use_id"]=tuid
            if p["status"]=="waiting_for_approval": p["approval_channel"]="socket"
            return p

        def send(payload):
            try:
                s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.settimeout(5)
                s.connect(SOCKET_PATH);s.sendall(json.dumps(payload).encode());s.close()
            except: pass

        try: data=json.load(sys.stdin)
        except: sys.exit(0)
        if isinstance(data,dict): send(build(data))
        """
        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func updateCodexHooks(at hooksURL: URL, scriptURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: hooksURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        let command = scriptURL.path
        let commonHook: [String: Any] = [
            "type": "command", "bash": command, "timeoutSec": 30,
            "env": ["CLAUDE_ISLAND_SOURCE": "codex_cli", "CLAUDE_ISLAND_SOCKET_PATH": "/tmp/claude-island.sock"]
        ]

        let events = ["sessionStart", "sessionEnd", "userPromptSubmitted", "preToolUse",
                       "postToolUse", "agentStop", "subagentStop", "errorOccurred"]

        for event in events {
            if var existing = hooks[event] as? [[String: Any]] {
                let hasOur = existing.contains { ($0["bash"] as? String) == command }
                if !hasOur {
                    existing.append(commonHook)
                    hooks[event] = existing
                }
            } else {
                hooks[event] = [commonHook]
            }
        }

        json["version"] = json["version"] as? Int ?? 1
        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: hooksURL)
        }
    }

    private func containsManagedHook(in hooks: [String: Any], scriptPath: String) -> Bool {
        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if (entry["bash"] as? String) == scriptPath || (entry["command"] as? String) == scriptPath {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func removeManagedHooks(from hooks: inout [String: Any], scriptPath: String) {
        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    (entry["bash"] as? String) == scriptPath || (entry["command"] as? String) == scriptPath
                }
                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }
    }
}

// MARK: - Gemini Hook Source

struct GeminiHookSource: HookSource {
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
        let command = "\(bridgePath) --source gemini"
        let hookEntry: [String: Any] = ["type": "command", "command": command]

        let events = ["sessionStart", "sessionEnd", "preToolUse", "postToolUse",
                       "stop", "notification"]

        for event in events {
            if var existing = hooks[event] as? [[String: Any]] {
                let hasOur = existing.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                if !hasOur {
                    existing.append(hookEntry)
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
                return entries.contains { ($0["command"] as? String)?.contains("claude-island") == true }
            }
            return false
        }
    }

    private func removeClaudeIslandHooks(from hooks: inout [String: Any]) {
        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { ($0["command"] as? String)?.contains("claude-island") == true }
                if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
            }
        }
    }
}

// MARK: - Cursor Hook Source

struct CursorHookSource: HookSource {
    var sourceType: SessionSource { .cursor }
    var displayName: String { "Cursor" }

    var configPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/hooks.json").path
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
        let command = "\(bridgePath) --source cursor"
        let hookEntry: [String: Any] = ["type": "command", "command": command, "timeoutSec": 30]

        let events = ["sessionStart", "sessionEnd", "preToolUse", "postToolUse", "agentStop"]

        for event in events {
            if var existing = hooks[event] as? [[String: Any]] {
                let hasOur = existing.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                if !hasOur {
                    existing.append(hookEntry)
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
            pid: process.pid
          };
          try {
            execSync(`echo '${JSON.stringify(payload)}' | \(bridgePath) --source opencode`, {
              timeout: 5000,
              stdio: 'pipe'
            });
          } catch {}
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
        let command = "\(bridgePath) --source copilot"
        let hookEntry: [String: Any] = ["type": "command", "command": command]

        let events = ["sessionStart", "sessionEnd", "toolUse", "stop"]

        for event in events {
            if var existing = hooks[event] as? [[String: Any]] {
                let hasOur = existing.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                if !hasOur {
                    existing.append(hookEntry)
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

// MARK: - Generic JSON Settings Hook Source (shared by Qoder, Droid, CodeBuddy, Trae)

private struct GenericSettingsHookSource: HookSource {
    let sourceType: SessionSource
    let displayName: String
    let configPath: String
    private let sourceName: String

    init(sourceType: SessionSource, displayName: String, configDir: String, sourceName: String) {
        self.sourceType = sourceType
        self.displayName = displayName
        self.configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("\(configDir)/settings.json").path
        self.sourceName = sourceName
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
        let command = "\(bridgePath) --source \(sourceName)"
        let hookEntry: [String: Any] = ["type": "command", "command": command]

        let events = ["sessionStart", "sessionEnd", "preToolUse", "postToolUse", "stop", "notification"]

        for event in events {
            if var existing = hooks[event] as? [[String: Any]] {
                let hasOur = existing.contains { ($0["command"] as? String)?.contains("claude-island") == true }
                if !hasOur {
                    existing.append(hookEntry)
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

// MARK: - Qoder Hook Source

struct QoderHookSource: HookSource {
    private let inner = GenericSettingsHookSource(
        sourceType: .qoder, displayName: "Qoder", configDir: ".qoder", sourceName: "qoder"
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
    private let inner = GenericSettingsHookSource(
        sourceType: .droid, displayName: "Droid", configDir: ".droid", sourceName: "droid"
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
    private let inner = GenericSettingsHookSource(
        sourceType: .codebuddy, displayName: "CodeBuddy", configDir: ".codebuddy", sourceName: "codebuddy"
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
