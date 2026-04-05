//
//  PermissionHandler.swift
//  ClaudeIslandBridge
//
//  Handles permission request events that require a synchronous response.
//

import Foundation

enum PermissionHandler {
    static func isPermissionRequest(payload: [String: Any]) -> Bool {
        let event = payload["event"] as? String ?? ""
        let status = payload["status"] as? String ?? ""
        return event == "PermissionRequest" && status == "waiting_for_approval"
    }

    /// Check if a PreToolUse event should be treated as an implicit permission request.
    /// Qoder and CodeBuddy don't have a dedicated PermissionRequest event;
    /// permissions are handled via PreToolUse hook's stdout `permissionDecision` field.
    static func isImplicitPermissionRequest(payload: [String: Any]) -> Bool {
        let event = payload["event"] as? String ?? ""
        let source = payload["source"] as? String ?? ""

        guard event == "PreToolUse" else { return false }
        guard source == "qoder" || source == "codebuddy" || source == "codex_cli" || source == "codex" || source == "kimi_cli" || source == "copilot" || source == "amp_cli" || source == "windsurf" else {
            return false
        }

        let tool = payload["tool"] as? String ?? ""
        let dangerousTools: Set<String> = [
            "Bash", "Write", "Edit",
            "run_in_terminal", "create_file", "search_replace",
            "execute_command", "write_to_file",
            "Shell", "WriteFile", "StrReplaceFile",
            "bash", "edit", "write", "create"
        ]
        return dangerousTools.contains(tool)
    }

    static func handle(client: SocketClient, data: Data, source: String) -> Int32 {
        if let responseData = client.sendAndReceive(data: data, timeout: 86400) {
            writeResponse(responseData, source: source)
            return exitCode(for: responseData, source: source)
        }
        return 0
    }

    /// Handle implicit permission requests (Qoder/CodeBuddy PreToolUse on dangerous tools).
    /// Mutates the payload to set approval_channel and status before sending.
    static func handleImplicit(client: SocketClient, payload: [String: Any]) -> Int32 {
        var mutablePayload = payload
        mutablePayload["approval_channel"] = "socket"
        mutablePayload["status"] = "waiting_for_approval"

        // Generate a tool_use_id if missing
        if mutablePayload["tool_use_id"] == nil {
            let source = payload["source"] as? String ?? "unknown"
            mutablePayload["tool_use_id"] = "\(source)-pretool-\(UUID().uuidString.prefix(8))"
        }

        guard let data = try? JSONSerialization.data(withJSONObject: mutablePayload, options: []) else {
            return 0
        }

        if let responseData = client.sendAndReceive(data: data, timeout: 120) {
            let source = payload["source"] as? String ?? ""
            writeResponse(responseData, source: source)
            return exitCode(for: responseData, source: source)
        }
        return 0
    }

    private static func writeResponse(_ responseData: Data, source: String) {
        guard !responseData.isEmpty else { return }

        if source == "windsurf" {
            FileHandle.standardError.write(responseData)
        } else {
            FileHandle.standardOutput.write(responseData)
        }
    }

    private static func exitCode(for responseData: Data, source: String) -> Int32 {
        guard sourceSupportsBlockingExitCode(source),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return 0
        }

        if let hookSpecific = json["hookSpecificOutput"] as? [String: Any],
           let permissionDecision = hookSpecific["permissionDecision"] as? String,
           permissionDecision == "deny" {
            return 2
        }

        if let hookSpecific = json["hookSpecificOutput"] as? [String: Any],
           let decision = hookSpecific["decision"] as? [String: Any],
           let behavior = decision["behavior"] as? String,
           behavior == "deny" {
            return 2
        }

        return 0
    }

    private static func sourceSupportsBlockingExitCode(_ source: String) -> Bool {
        switch source {
        case "qoder", "codebuddy", "codex_cli", "codex", "droid", "kimi_cli", "amp_cli", "windsurf":
            return true
        default:
            return false
        }
    }
}
