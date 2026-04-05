//
//  EventMapper.swift
//  ClaudeIslandBridge
//
//  Maps events from various AI tools into the unified ClaudeIsland protocol.
//  Supports: Claude, Codex, Gemini, Cursor, OpenCode, Copilot, Qoder, Droid, CodeBuddy, Trae.
//

import Foundation

enum EventMapper {

    /// Map raw hook input into the unified protocol format
    static func map(input: [String: Any], source: String, tty: String?, ppid: Int) -> [String: Any] {
        let eventName = extractEventName(from: input)
        let normalizedEvent = normalizeEventName(eventName)
        let sessionId = extractSessionId(from: input)
        let cwd = extractCwd(from: input)

        var payload: [String: Any] = [
            "session_id": sessionId,
            "source": source,
            "cwd": cwd,
            "event": normalizedEvent,
            "status": inferStatus(normalizedEvent),
            "approval_channel": "none",
            "_ppid": ppid
        ]

        if let tty = tty {
            payload["tty"] = tty
        }

        if let pid = input["pid"] ?? nested(input, "session", "pid") {
            payload["pid"] = pid
        }

        // Tool info
        if let toolName = extractToolName(from: input) {
            payload["tool"] = toolName
        }

        if let toolInput = input["tool_input"] ?? input["toolInput"] ?? nested(input, "tool", "input") {
            payload["tool_input"] = toolInput
        }

        if let toolUseId = firstString(
            input["tool_use_id"],
            input["toolUseId"],
            nested(input, "tool", "id")
        ) {
            payload["tool_use_id"] = toolUseId
        }

        // Permission requests need socket channel
        if normalizedEvent == "PermissionRequest" {
            payload["approval_channel"] = "socket"
            payload["status"] = "waiting_for_approval"
        }

        // Event-specific content fields (for UI display)
        // UserPromptSubmit → user's prompt text
        if let prompt = firstString(input["prompt"], input["text"]) {
            payload["prompt"] = prompt
        }

        // PostToolUseFailure → error message (Qoder-specific)
        if let error = firstString(input["error"], input["error_message"]) {
            payload["error"] = error
        }

        // PostToolUse → tool response (brief, for status display)
        if let toolResponse = input["tool_response"] as? String {
            payload["tool_response"] = String(toolResponse.prefix(500))
        }

        // Stop → last assistant message
        if let lastMsg = firstString(input["last_assistant_message"], input["lastAssistantMessage"]) {
            payload["last_assistant_message"] = String(lastMsg.prefix(500))
        }

        // Collect terminal environment variables for TTY/session correlation
        payload["_env"] = collectEnv()

        return payload
    }

    // MARK: - Event Name Extraction

    private static func extractEventName(from input: [String: Any]) -> String {
        return firstString(
            input["hook_event_name"],
            input["hookEventName"],
            input["event"],
            input["type"]
        ) ?? "unknown"
    }

    private static func extractSessionId(from input: [String: Any]) -> String {
        return firstString(
            input["session_id"],
            input["sessionId"],
            nested(input, "session", "id"),
            input["id"]
        ) ?? "unknown"
    }

    private static func extractCwd(from input: [String: Any]) -> String {
        return firstString(
            input["cwd"],
            nested(input, "session", "cwd"),
            input["workingDirectory"],
            input["workspace"]
        ) ?? ""
    }

    private static func extractToolName(from input: [String: Any]) -> String? {
        if let name = input["tool_name"] as? String { return name }
        if let name = input["toolName"] as? String { return name }
        if let tool = input["tool"] as? [String: Any], let name = tool["name"] as? String { return name }
        if let name = input["tool"] as? String { return name }
        return nil
    }

    // MARK: - Event Name Normalization

    static func normalizeEventName(_ raw: String) -> String {
        let key = raw
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()

        let aliases: [String: String] = [
            "sessionstart": "SessionStart",
            "sessionend": "SessionEnd",
            "userpromptsubmitted": "UserPromptSubmit",
            "userpromptsubmit": "UserPromptSubmit",
            "pretooluse": "PreToolUse",
            "posttooluse": "PostToolUse",
            "permissionrequest": "PermissionRequest",
            "agentstop": "Stop",
            "stop": "Stop",
            "subagentstop": "SubagentStop",
            "notification": "Notification",
            "precompact": "PreCompact",
            "posttoolusefailure": "PostToolUseFailure",
            "erroroccurred": "Notification",
        ]

        return aliases[key] ?? raw
    }

    // MARK: - Status Inference

    static func inferStatus(_ event: String) -> String {
        switch event {
        case "PreToolUse":
            return "running_tool"
        case "PostToolUse", "PostToolUseFailure", "UserPromptSubmit":
            return "processing"
        case "PermissionRequest":
            return "waiting_for_approval"
        case "SessionStart", "Stop", "SubagentStop":
            return "waiting_for_input"
        case "SessionEnd":
            return "ended"
        case "PreCompact":
            return "compacting"
        default:
            return "unknown"
        }
    }

    // MARK: - Helpers

    private static func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let str = value as? String, !str.isEmpty {
                return str
            }
        }
        return nil
    }

    private static func nested(_ dict: [String: Any], _ keys: String...) -> Any? {
        var current: Any = dict
        for key in keys {
            guard let d = current as? [String: Any] else { return nil }
            guard let next = d[key] else { return nil }
            current = next
        }
        return current
    }

    // MARK: - Environment Collection

    private static let envKeys = [
        "TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID",
        "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID", "__CFBundleIdentifier",
        "CONDUCTOR_WORKSPACE_NAME", "CONDUCTOR_PORT", "CURSOR_TRACE_ID",
        "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID", "CMUX_SOCKET_PATH",
    ]

    private static func collectEnv() -> [String: String] {
        var env: [String: String] = [:]
        let processEnv = ProcessInfo.processInfo.environment
        for key in envKeys {
            if let value = processEnv[key] {
                env[key] = value
            }
        }
        return env
    }
}
