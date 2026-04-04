//
//  HookInstaller.swift
//  ClaudeIsland
//
//  Multi-source hook installer skeleton.
//  Claude stays fully supported; Codex is installed as a safe, reversible groundwork.
//

import Foundation

struct HookInstaller {

    // MARK: - Public API

    /// Install all managed integrations on app launch.
    static func installIfNeeded() {
        installClaudeIfNeeded()
        installCodexIfNeeded()
    }

    /// Check whether at least one managed integration is installed.
    static func isInstalled() -> Bool {
        isClaudeInstalled() || isCodexInstalled()
    }

    /// Remove all managed integrations.
    static func uninstall() {
        uninstallClaude()
        uninstallCodex()
    }

    /// Install the Codex groundwork only.
    static func installCodexIfNeeded() {
        installCodexIntegration()
    }

    /// Check whether the Codex groundwork is installed.
    static func isCodexInstalled() -> Bool {
        let hooksURL = codexHooksURL()
        let scriptURL = codexHookScriptURL()

        guard FileManager.default.fileExists(atPath: hooksURL.path),
              FileManager.default.fileExists(atPath: scriptURL.path),
              let data = try? Data(contentsOf: hooksURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        return containsManagedCodexHook(in: hooks, scriptPath: scriptURL.path)
    }

    /// Remove the Codex groundwork only.
    static func uninstallCodex() {
        let hooksURL = codexHooksURL()
        let scriptURL = codexHookScriptURL()
        let codexDir = codexIntegrationRootURL()

        if let data = try? Data(contentsOf: hooksURL),
           var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           var hooks = json["hooks"] as? [String: Any] {
            removeManagedCodexHooks(from: &hooks, scriptPath: scriptURL.path)

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
        try? FileManager.default.removeItem(at: codexDir)
    }

    // MARK: - Claude Integration

    /// Install hook script and update settings.json on app launch.
    static func installClaudeIfNeeded() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("claude-island-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

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

        updateClaudeSettings(at: settings)
    }

    /// Check whether the Claude integration is installed.
    static func isClaudeInstalled() -> Bool {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let settings = claudeDir.appendingPathComponent("settings.json")

        guard let data = try? Data(contentsOf: settings),
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
                               cmd.contains("claude-island-state.py") {
                                return true
                            }
                        }
                    }
                }
            }
        }

        return false
    }

    /// Uninstall the Claude integration.
    static func uninstallClaude() {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        let hooksDir = claudeDir.appendingPathComponent("hooks")
        let pythonScript = hooksDir.appendingPathComponent("claude-island-state.py")
        let settings = claudeDir.appendingPathComponent("settings.json")

        try? FileManager.default.removeItem(at: pythonScript)

        guard let data = try? Data(contentsOf: settings),
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
                            return cmd.contains("claude-island-state.py")
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
            try? data.write(to: settings)
        }
    }

    // MARK: - Codex Groundwork

    private static func installCodexIntegration() {
        let codexDir = codexIntegrationRootURL()
        let binDir = codexDir.appendingPathComponent("bin")
        let scriptURL = codexHookScriptURL()
        let hooksURL = codexHooksURL()

        try? FileManager.default.createDirectory(
            at: binDir,
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: codexDir.path) {
            try? FileManager.default.createDirectory(
                at: codexDir,
                withIntermediateDirectories: true
            )
        }

        writeCodexHookScript(at: scriptURL)
        updateCodexHooks(at: hooksURL, scriptURL: scriptURL)
    }

    private static func updateCodexHooks(at hooksURL: URL, scriptURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: hooksURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        let command = scriptURL.path
        let codexHooks = codexHookDefinitions(command: command)

        for (event, config) in codexHooks {
            if var existingEvent = hooks[event] as? [[String: Any]] {
                let hasOurHook = existingEvent.contains { entry in
                    guard let entryCommand = codexCommand(from: entry) else { return false }
                    return entryCommand == command
                }
                if !hasOurHook {
                    existingEvent.append(config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = [config]
            }
        }

        json["version"] = json["version"] as? Int ?? 1
        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: hooksURL)
        }
    }

    private static func writeCodexHookScript(at url: URL) {
        let script = """
        #!/usr/bin/env python3
        import json
        import os
        import socket
        import sys

        SOCKET_PATH = os.environ.get("CLAUDE_ISLAND_SOCKET_PATH", "/tmp/claude-island.sock")

        def first_string(*values):
            for value in values:
                if isinstance(value, str) and value:
                    return value
            return None

        def nested_value(obj, *keys):
            current = obj
            for key in keys:
                if not isinstance(current, dict):
                    return None
                current = current.get(key)
            return current

        def normalize_event_name(event_name):
            value = (event_name or "").strip()
            if not value:
                return "unknown"
            aliases = {
                "sessionstart": "SessionStart",
                "sessionend": "SessionEnd",
                "userpromptsubmitted": "UserPromptSubmit",
                "pretooluse": "PreToolUse",
                "posttooluse": "PostToolUse",
                "permissionrequest": "PermissionRequest",
                "agentstop": "Stop",
                "subagentstop": "SubagentStop",
                "notification": "Notification",
                "precompact": "PreCompact",
                "erroroccurred": "Notification",
            }
            key = value.replace("_", "").replace("-", "").lower()
            return aliases.get(key, value)

        def infer_status(event_name):
            name = normalize_event_name(event_name)
            if name in ("PreToolUse",):
                return "running_tool"
            if name in ("PostToolUse", "UserPromptSubmit"):
                return "processing"
            if name in ("PermissionRequest",):
                return "waiting_for_approval"
            if name in ("SessionStart", "Stop", "SubagentStop"):
                return "waiting_for_input"
            if name == "SessionEnd":
                return "ended"
            if name == "PreCompact":
                return "compacting"
            return "unknown"

        def build_payload(data):
            event_name = first_string(
                data.get("hook_event_name"),
                data.get("hookEventName"),
                data.get("event"),
                data.get("type"),
            )
            session_id = first_string(
                data.get("session_id"),
                data.get("sessionId"),
                nested_value(data, "session", "id"),
                data.get("id"),
            ) or "unknown"
            cwd = first_string(
                data.get("cwd"),
                nested_value(data, "session", "cwd"),
                data.get("workingDirectory"),
                data.get("workspace"),
            ) or ""
            tool_input = data.get("tool_input")
            if tool_input is None:
                tool_input = data.get("toolInput")
            if tool_input is None and isinstance(data.get("tool"), dict):
                tool_input = data.get("tool", {}).get("input")

            tool_name = first_string(
                data.get("tool_name"),
                data.get("toolName"),
                nested_value(data, "tool", "name"),
                data.get("tool"),
            )
            tool_use_id = first_string(
                data.get("tool_use_id"),
                data.get("toolUseId"),
                nested_value(data, "tool", "id"),
            )
            tty = first_string(
                data.get("tty"),
                nested_value(data, "session", "tty"),
            )
            pid = data.get("pid") or nested_value(data, "session", "pid")

            payload = {
                "session_id": session_id,
                "source": "codex_cli",
                "cwd": cwd,
                "event": normalize_event_name(event_name),
                "status": infer_status(event_name),
                "pid": pid,
                "tty": tty,
                "approval_channel": "none",
            }

            if tool_name is not None:
                payload["tool"] = tool_name
            if tool_input is not None:
                payload["tool_input"] = tool_input
            if tool_use_id is not None:
                payload["tool_use_id"] = tool_use_id

            if payload["status"] == "waiting_for_approval":
                payload["approval_channel"] = "socket"

            return payload

        def send_event(payload):
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.settimeout(5)
                sock.connect(SOCKET_PATH)
                sock.sendall(json.dumps(payload).encode("utf-8"))
                sock.close()
            except Exception:
                return

        def main():
            try:
                data = json.load(sys.stdin)
            except Exception:
                sys.exit(0)

            if not isinstance(data, dict):
                sys.exit(0)

            payload = build_payload(data)
            send_event(payload)
            sys.exit(0)

        if __name__ == "__main__":
            main()
        """

        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private static func codexHookDefinitions(command: String) -> [String: [String: Any]] {
        let commonHook: [String: Any] = [
            "type": "command",
            "bash": command,
            "timeoutSec": 30,
            "env": [
                "CLAUDE_ISLAND_SOURCE": "codex_cli",
                "CLAUDE_ISLAND_SOCKET_PATH": "/tmp/claude-island.sock"
            ]
        ]

        return [
            "sessionStart": commonHook,
            "sessionEnd": commonHook,
            "userPromptSubmitted": commonHook,
            "preToolUse": commonHook,
            "postToolUse": commonHook,
            "agentStop": commonHook,
            "subagentStop": commonHook,
            "errorOccurred": commonHook
        ]
    }

    private static func containsManagedCodexHook(in hooks: [String: Any], scriptPath: String) -> Bool {
        for (_, value) in hooks {
            if let entries = value as? [[String: Any]] {
                for entry in entries {
                    if let command = codexCommand(from: entry), command == scriptPath {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func removeManagedCodexHooks(from hooks: inout [String: Any], scriptPath: String) {
        for (event, value) in hooks {
            if var entries = value as? [[String: Any]] {
                entries.removeAll { entry in
                    guard let command = codexCommand(from: entry) else { return false }
                    return command == scriptPath
                }

                if entries.isEmpty {
                    hooks.removeValue(forKey: event)
                } else {
                    hooks[event] = entries
                }
            }
        }
    }

    private static func codexCommand(from entry: [String: Any]) -> String? {
        if let command = entry["bash"] as? String {
            return command
        }
        if let command = entry["command"] as? String {
            return command
        }
        return nil
    }

    private static func codexIntegrationRootURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/claude-island")
    }

    private static func codexHookScriptURL() -> URL {
        codexIntegrationRootURL().appendingPathComponent("codex-island-hook.py")
    }

    private static func codexHooksURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
    }

    // MARK: - Claude Helpers

    private static func updateClaudeSettings(at settingsURL: URL) {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        let python = detectPython()
        let command = "\(python) ~/.claude/hooks/claude-island-state.py"
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
                let hasOurHook = existingEvent.contains { entry in
                    if let entryHooks = entry["hooks"] as? [[String: Any]] {
                        return entryHooks.contains { h in
                            let cmd = h["command"] as? String ?? ""
                            return cmd.contains("claude-island-state.py")
                        }
                    }
                    return false
                }
                if !hasOurHook {
                    existingEvent.append(contentsOf: config)
                    hooks[event] = existingEvent
                }
            } else {
                hooks[event] = config
            }
        }

        json["hooks"] = hooks

        if let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: settingsURL)
        }
    }

    private static func detectPython() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return "python3"
            }
        } catch {}

        return "python"
    }
}
