//
//  EventMapper.swift
//  ClaudeIslandBridge
//
//  Maps events from various AI tools into the unified ClaudeIsland protocol.
//  Supports: Claude, Codex, Gemini, Cursor, OpenCode, Copilot, Qoder, Droid, CodeBuddy, Trae.
//

import Foundation

enum EventMapper {

    // MARK: - Cursor Session Cache
    /// Cache the most recent Cursor conversation_id for session continuity.
    /// Cursor only provides conversation_id in beforeSubmitPrompt; other events lack a session ID.
    private static var cursorSessionCache: (conversationId: String, timestamp: Date)?

    /// Map raw hook input into the unified protocol format
    static func map(input: [String: Any], source: String, tty: String?, ppid: Int) -> [String: Any] {
        let eventName = extractEventName(from: input)
        let normalizedEvent = normalizeEventName(eventName, source: source)
        let normalizedSource = normalizeSource(input: input, requestedSource: source)
        let sessionId = extractSessionId(from: input)
        let cwd = extractCwd(from: input)

        var payload: [String: Any] = [
            "session_id": sessionId,
            "source": normalizedSource,
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
        } else {
            // Fallback: use bridge's parent PID (the CLI/IDE process that invoked us)
            // Ensures PID-based terminal focus works even when hook input lacks pid field
            payload["pid"] = getppid()
        }

        // Source-specific: infer tool name/input/prompt from event-specific fields
        if source == "cursor" {
            applyCursorFields(input: input, eventName: eventName, payload: &payload)
        } else if source == "cline" {
            applyClineFields(input: input, eventName: eventName, payload: &payload)
        } else if source == "windsurf" {
            applyWindsurfFields(input: input, eventName: eventName, payload: &payload)
        }

        // Tool info (generic extraction, won't overwrite Cursor-set fields)
        if payload["tool"] == nil, let toolName = extractToolName(from: input) {
            payload["tool"] = toolName
        }

        if payload["tool_input"] == nil,
           let toolInput = input["tool_input"] ??
                input["toolInput"] ??
                nested(input, "tool", "input") ??
                nested(input, "tool", "args") ??
                nested(input, "tool", "arguments") {
            payload["tool_input"] = toolInput
        } else if payload["tool_input"] == nil,
                  let toolArgs = input["toolArgs"] as? [String: Any] ??
                    input["tool_args"] as? [String: Any] ??
                    input["modifiedArgs"] as? [String: Any] ??
                    nested(input, "toolCall", "arguments") as? [String: Any] ??
                    nested(input, "toolCall", "args") as? [String: Any] {
            payload["tool_input"] = toolArgs
        } else if payload["tool_input"] == nil,
                  let toolArgs = firstString(
                    input["toolArgs"],
                    input["tool_args"],
                    input["modifiedArgs"],
                    nested(input, "toolCall", "arguments"),
                    nested(input, "toolCall", "args")
                  ) {
            if let data = toolArgs.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                payload["tool_input"] = json
            } else {
                payload["tool_input"] = ["raw": toolArgs]
            }
        }

        if let toolUseId = firstString(
            input["tool_use_id"],
            input["toolUseId"],
            nested(input, "tool", "id")
        ) {
            payload["tool_use_id"] = toolUseId
        }

        if source == "gemini" && normalizedEvent == "Notification" {
            if payload["tool"] == nil, let notificationToolName = extractGeminiNotificationToolName(from: input) {
                payload["tool"] = notificationToolName
            }

            if payload["tool_input"] == nil, let notificationDetails = extractGeminiNotificationDetails(from: input) {
                payload["tool_input"] = notificationDetails
            }
        }

        if let notificationType = extractNotificationType(from: input) {
            payload["notification_type"] = notificationType
        }

        if let message = extractMessage(from: input) {
            payload["message"] = String(message.prefix(500))
        }

        if let rateLimits = input["rate_limits"] ?? input["rateLimits"] {
            payload["rate_limits"] = rateLimits
        }

        if source == "gemini",
           normalizedEvent == "Notification",
           (payload["notification_type"] as? String)?.lowercased() == "toolpermission" {
            payload["status"] = "waiting_for_approval"
            payload["approval_channel"] = "terminal"

            if payload["tool_use_id"] == nil {
                payload["tool_use_id"] = "gemini-tool-permission-\(UUID().uuidString.prefix(8))"
            }
        }

        // Permission requests need socket channel
        if normalizedEvent == "PermissionRequest" {
            payload["approval_channel"] = "socket"
            payload["status"] = "waiting_for_approval"
        }

        // Event-specific content fields (for UI display)
        // UserPromptSubmit → user's prompt text
        if let prompt = extractPrompt(from: input) {
            payload["prompt"] = prompt
        }

        // PostToolUseFailure → error message (Qoder-specific)
        if let error = extractError(from: input) {
            payload["error"] = String(error.prefix(500))
        }

        // PostToolUse → tool response (brief, for status display)
        if let toolResponse = extractToolResponse(from: input) {
            payload["tool_response"] = String(toolResponse.prefix(500))
        }

        // Stop → last assistant message
        if let lastMsg = extractLastAssistantMessage(from: input) {
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
            input["type"],
            input["hookName"],
            input["agent_action_name"],
            input["notification_type"],
            input["notificationType"]
        ) ?? detectClineEventName(from: input) ?? "unknown"
    }

    private static func extractSessionId(from input: [String: Any]) -> String {
        return firstString(
            input["session_id"],
            input["sessionId"],
            nested(input, "data", "sessionId"),
            nested(input, "data", "interactionId"),
            input["taskId"],
            input["thread_id"],
            input["threadId"],
            nested(input, "session", "id"),
            nested(input, "taskStart", "taskId"),
            nested(input, "taskResume", "taskId"),
            nested(input, "taskComplete", "taskId"),
            nested(input, "taskCancel", "taskId"),
            input["trajectory_id"],
            input["execution_id"],
            input["conversation_id"],   // Cursor: conversation_id as session grouping
            input["generation_id"],     // Cursor: generation_id as fallback
            input["turn_id"],
            input["id"]
        ) ?? "unknown"
    }

    private static func extractCwd(from input: [String: Any]) -> String {
        // Try standard fields first
        if let cwd = firstString(
            input["cwd"],
            nested(input, "session", "cwd"),
            nested(input, "turn_context", "cwd"),
            input["workingDirectory"],
            input["workspace"]
        ) {
            return cwd
        }
        // Cursor: workspace_roots array
        if let roots = input["workspace_roots"] as? [String], let first = roots.first {
            return first
        }
        if let roots = input["workspaceRoots"] as? [String], let first = roots.first {
            return first
        }
        return FileManager.default.currentDirectoryPath
    }

    private static func extractToolName(from input: [String: Any]) -> String? {
        if let name = input["tool_name"] as? String { return name }
        if let name = input["toolName"] as? String { return name }
        if let name = nested(input, "preToolUse", "tool") as? String { return name }
        if let name = nested(input, "postToolUse", "tool") as? String { return name }
        if let name = nested(input, "tool_info", "tool_name") as? String { return name }
        if let name = nested(input, "tool_info", "toolName") as? String { return name }
        if let name = nested(input, "toolResult", "toolName") as? String { return name }
        if let name = nested(input, "tool_result", "toolName") as? String { return name }
        if let name = nested(input, "toolResult", "name") as? String { return name }
        if let name = nested(input, "tool_result", "name") as? String { return name }
        if let name = nested(input, "toolResult", "tool") as? String { return name }
        if let name = nested(input, "tool_result", "tool") as? String { return name }
        if let name = nested(input, "result", "toolName") as? String { return name }
        if let name = nested(input, "result", "name") as? String { return name }
        if let name = nested(input, "result", "tool") as? String { return name }
        if let tool = input["tool"] as? [String: Any], let name = tool["name"] as? String { return name }
        if let name = input["tool"] as? String { return name }
        return nil
    }

    // MARK: - Event Name Normalization

    private static func normalizeSource(input: [String: Any], requestedSource: String) -> String {
        if requestedSource == "codex_notify" {
            let client = firstString(
                input["client"],
                nested(input, "clientInfo", "name")
            )?.lowercased()

            if client == "codex-tui" || client == "codex-cli" {
                return "codex_cli"
            }

            return "codex_desktop"
        }

        return requestedSource
    }

    static func normalizeEventName(_ raw: String, source: String? = nil) -> String {
        let key = raw
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .lowercased()

        if source?.lowercased() == "gemini" {
            let geminiAliases: [String: String] = [
                "beforetool": "PreToolUse",
                "aftertool": "PostToolUse",
                "beforeagent": "UserPromptSubmit",
                "beforemodel": "Notification",
                "beforetoolselection": "Notification",
                "aftermodel": "Notification",
                "afteragent": "Stop",
                "precompress": "PreCompact",
            ]

            if let mapped = geminiAliases[key] {
                return mapped
            }
        }

        if source?.lowercased() == "cline" {
            let clineAliases: [String: String] = [
                "taskstart": "SessionStart",
                "taskresume": "SessionStart",
                "taskcomplete": "Stop",
                "taskcancel": "Stop",
            ]

            if let mapped = clineAliases[key] {
                return mapped
            }
        }

        let aliases: [String: String] = [
            // Standard Claude Code events
            "sessionstart": "SessionStart",
            "sessionend": "SessionEnd",
            "userpromptsubmitted": "UserPromptSubmit",
            "userpromptsubmit": "UserPromptSubmit",
            "pretooluse": "PreToolUse",
            "posttooluse": "PostToolUse",
            "permissionrequest": "PermissionRequest",
            "elicitation": "Notification",
            "elicitationresult": "Notification",
            "agentstop": "Stop",
            "setup": "Setup",
            "stop": "Stop",
            "postcompact": "PostCompact",
            "subagentstop": "SubagentStop",
            "subagentstart": "SubagentStart",
            "notification": "Notification",
            "precompact": "PreCompact",
            "posttoolusefailure": "PostToolUseFailure",
            "stopfailure": "Notification",
            "erroroccurred": "Notification",
            // Codex desktop / notify aliases
            "taskstarted": "UserPromptSubmit",
            "taskcomplete": "Stop",
            "agentturncomplete": "Stop",
            // Copilot-specific aliases
            "tooluse": "PreToolUse",
            "usermessage": "UserPromptSubmit",
            "assistantturnstart": "Notification",
            "assistantmessagedelta": "Notification",
            "assistantmessage": "Stop",
            "assistantturnend": "Stop",
            "sessionmcpserverstatuschanged": "Notification",
            "sessionmcpserversloaded": "Notification",
            "sessiontoolsupdated": "Notification",
            // Cursor-specific events
            "beforesubmitprompt": "UserPromptSubmit",
            "beforeshellexecution": "PermissionRequest",
            "beforemcpexecution": "PermissionRequest",
            "beforereadfile": "PreToolUse",
            "afterfileedit": "PostToolUse",
            // Windsurf-specific events
            "preuserprompt": "UserPromptSubmit",
            "preruncommand": "PreToolUse",
            "postruncommand": "PostToolUse",
            "premcptooluse": "PreToolUse",
            "postmcptooluse": "PostToolUse",
            "prereadcode": "PreToolUse",
            "postreadcode": "PostToolUse",
            "prewritecode": "PreToolUse",
            "postwritecode": "PostToolUse",
            "postcascaderesponse": "Stop",
            "postcascaderesponsewithtranscript": "Stop",
            "postsetupworktree": "Notification",
            // Kiro custom agent hooks
            "agentspawn": "SessionStart",
            "sessionclear": "Notification",
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
        case "Setup":
            return "starting"
        case "SessionStart", "Stop", "SubagentStop", "PostCompact":
            return "waiting_for_input"
        case "SessionEnd":
            return "ended"
        case "PreCompact":
            return "compacting"
        default:
            return "unknown"
        }
    }

    // MARK: - Cursor-Specific Field Extraction

    /// Extract tool name, tool_input, and other fields from Cursor's event-specific stdin format.
    /// Cursor events use different field names than Claude Code:
    /// - beforeShellExecution: {command, cwd}
    /// - beforeMCPExecution: {server, tool_name, tool_input}
    /// - beforeReadFile: {content, file_path}
    /// - afterFileEdit: {file_path, edits}
    /// - beforeSubmitPrompt: {conversation_id, generation_id, prompt, attachments, workspace_roots}
    /// - stop: {status}
    private static func applyCursorFields(input: [String: Any], eventName: String, payload: inout [String: Any]) {
        let key = eventName.lowercased()

        switch key {
        case "beforeshellexecution":
            payload["tool"] = "Bash"
            if let command = input["command"] as? String {
                payload["tool_input"] = ["command": command]
            }
            // Generate a stable tool_use_id for permission correlation
            payload["tool_use_id"] = "cursor-shell-\(UUID().uuidString.prefix(8))"

        case "beforemcpexecution":
            if let toolName = input["tool_name"] as? String {
                // Prefix with MCP server name if available
                if let server = input["server"] as? String {
                    payload["tool"] = "mcp__\(server)__\(toolName)"
                } else {
                    payload["tool"] = toolName
                }
            }
            if let toolInput = input["tool_input"] {
                payload["tool_input"] = toolInput
            }
            payload["tool_use_id"] = "cursor-mcp-\(UUID().uuidString.prefix(8))"

        case "beforereadfile":
            payload["tool"] = "Read"
            if let filePath = input["file_path"] as? String {
                payload["tool_input"] = ["file_path": filePath]
            }

        case "afterfileedit":
            payload["tool"] = "Edit"
            if let filePath = input["file_path"] as? String {
                payload["tool_input"] = ["file_path": filePath]
            }

        case "beforesubmitprompt":
            if let prompt = input["prompt"] as? String {
                payload["prompt"] = prompt
            }
            // Use conversation_id as session_id for better session grouping
            if let convId = input["conversation_id"] as? String {
                payload["session_id"] = convId
                // Cache for other Cursor events that lack conversation_id
                cursorSessionCache = (convId, Date())
            }

        case "stop":
            if let status = input["status"] as? String {
                payload["last_assistant_message"] = "Cursor agent \(status)"
            }

        default:
            break
        }

        // Extract workspace_roots for cwd if cwd is empty
        if (payload["cwd"] as? String)?.isEmpty == true,
           let roots = input["workspace_roots"] as? [String], let first = roots.first {
            payload["cwd"] = first
        }

        // Cursor session continuity: fallback to cached conversation_id (1h TTL)
        if let sid = payload["session_id"] as? String, sid == "unknown",
           let cached = cursorSessionCache,
           Date().timeIntervalSince(cached.timestamp) < 3600 {
            payload["session_id"] = cached.conversationId
        }

        // Extract edit details from afterFileEdit for richer UI
        if key == "afterfileedit",
           let edits = input["edits"] as? [[String: Any]], let first = edits.first,
           let oldStr = first["old_string"] as? String {
            payload["tool_response"] = "Changed: \(String(oldStr.prefix(100)))"
        }
    }

    /// Extract tool/prompt fields from Windsurf's hook payload.
    private static func applyWindsurfFields(input: [String: Any], eventName: String, payload: inout [String: Any]) {
        let key = eventName.lowercased()
        let toolInfo = input["tool_info"] as? [String: Any] ?? [:]
        let executionId = firstString(input["execution_id"], toolInfo["execution_id"])

        switch key {
        case "pre_user_prompt":
            if let prompt = firstString(toolInfo["user_prompt"], input["prompt"]) {
                payload["prompt"] = prompt
            }

        case "pre_run_command":
            payload["tool"] = "Bash"
            var toolInput: [String: Any] = [:]
            if let command = firstString(toolInfo["command"], input["command"]) {
                toolInput["command"] = command
            }
            if let cwd = firstString(toolInfo["cwd"]) {
                toolInput["cwd"] = cwd
                payload["cwd"] = cwd
            }
            if !toolInput.isEmpty {
                payload["tool_input"] = toolInput
            }

        case "post_run_command":
            payload["tool"] = "Bash"
            if let command = firstString(toolInfo["command"], input["command"]) {
                payload["tool_input"] = ["command": command]
            }
            if let output = firstString(toolInfo["command_output"], toolInfo["output"], input["output"]) {
                payload["tool_response"] = output
            }

        case "pre_mcp_tool_use":
            if let toolName = firstString(toolInfo["tool_name"], toolInfo["tool"], input["tool_name"]) {
                payload["tool"] = toolName
            }
            if let toolInput = toolInfo["tool_input"] ?? input["tool_input"] {
                payload["tool_input"] = toolInput
            }

        case "post_mcp_tool_use":
            if let toolName = firstString(toolInfo["tool_name"], toolInfo["tool"], input["tool_name"]) {
                payload["tool"] = toolName
            }
            if let toolInput = toolInfo["tool_input"] ?? input["tool_input"] {
                payload["tool_input"] = toolInput
            }
            if let output = firstString(toolInfo["output"], input["output"], input["message"]) {
                payload["tool_response"] = output
            }

        case "pre_read_code":
            payload["tool"] = "Read"
            if let path = firstString(toolInfo["file_path"], toolInfo["path"]) {
                payload["tool_input"] = ["file_path": path]
            }

        case "post_read_code":
            payload["tool"] = "Read"
            if let path = firstString(toolInfo["file_path"], toolInfo["path"]) {
                payload["tool_input"] = ["file_path": path]
            }
            if let output = firstString(toolInfo["output"], input["output"], input["message"]) {
                payload["tool_response"] = output
            }

        case "pre_write_code":
            payload["tool"] = "Write"
            if let path = firstString(toolInfo["file_path"], toolInfo["path"]) {
                payload["tool_input"] = ["file_path": path]
            }

        case "post_write_code":
            payload["tool"] = "Write"
            if let path = firstString(toolInfo["file_path"], toolInfo["path"]) {
                payload["tool_input"] = ["file_path": path]
            }

        case "post_cascade_response":
            if let response = firstString(toolInfo["response"], input["response"], input["message"]) {
                payload["last_assistant_message"] = response
            }

        case "post_cascade_response_with_transcript":
            if let response = firstString(toolInfo["response"], input["response"], input["message"]) {
                payload["last_assistant_message"] = response
            }
            if let transcript = toolInfo["transcript"] ?? input["transcript"] {
                payload["message"] = stringify(transcript)
            }

        case "post_setup_worktree":
            if let worktreePath = firstString(toolInfo["worktree_path"], toolInfo["path"], input["path"]) {
                payload["message"] = worktreePath
            }

        default:
            break
        }

        if let executionId {
            payload["tool_use_id"] = executionId
        }
    }

    private static func applyClineFields(input: [String: Any], eventName: String, payload: inout [String: Any]) {
        let key = eventName.lowercased()

        switch key {
        case "taskstart", "taskresume":
            if let task = firstString(nested(input, "taskStart", "task"), nested(input, "taskResume", "task")) {
                payload["message"] = task
            }
            if let taskId = firstString(nested(input, "taskStart", "taskId"), nested(input, "taskResume", "taskId")) {
                payload["session_id"] = taskId
            }

        case "userpromptsubmit":
            if let prompt = firstString(nested(input, "userPromptSubmit", "prompt")) {
                payload["prompt"] = prompt
            }

        case "pretooluse":
            if let tool = firstString(nested(input, "preToolUse", "tool")) {
                payload["tool"] = tool
            }
            if let parameters = nested(input, "preToolUse", "parameters") {
                payload["tool_input"] = parameters
            }

        case "posttooluse":
            if let tool = firstString(nested(input, "postToolUse", "tool")) {
                payload["tool"] = tool
            }
            if let parameters = nested(input, "postToolUse", "parameters") {
                payload["tool_input"] = parameters
            }
            if let result = nested(input, "postToolUse", "result") {
                payload["tool_response"] = stringify(result)
            }
            if let success = nested(input, "postToolUse", "success") as? Bool {
                payload["message"] = success ? "Tool completed" : "Tool failed"
                if success == false, payload["error"] == nil, let result = nested(input, "postToolUse", "result") {
                    payload["error"] = stringify(result)
                }
            }
            if let durationMs = nested(input, "postToolUse", "durationMs") {
                let durationText = stringify(durationMs)
                if let existing = payload["message"] as? String, !existing.isEmpty {
                    payload["message"] = "\(existing) (\(durationText)ms)"
                } else {
                    payload["message"] = "Duration: \(durationText)ms"
                }
            }

        case "precompact":
            if let trigger = firstString(nested(input, "preCompact", "trigger")) {
                payload["message"] = trigger
            }

        case "taskcomplete", "taskcancel":
            if let task = firstString(nested(input, "taskComplete", "task"), nested(input, "taskCancel", "task")) {
                payload["message"] = task
            }
            if let taskId = firstString(nested(input, "taskComplete", "taskId"), nested(input, "taskCancel", "taskId")) {
                payload["session_id"] = taskId
            }

        default:
            break
        }

        if let roots = input["workspaceRoots"] as? [String], let first = roots.first {
            payload["cwd"] = first
        }
    }

    // MARK: - Helpers

    private static func detectClineEventName(from input: [String: Any]) -> String? {
        let clineKeys = [
            "taskStart",
            "taskResume",
            "userPromptSubmit",
            "preToolUse",
            "postToolUse",
            "preCompact",
            "taskComplete",
            "taskCancel",
        ]

        return clineKeys.first { input[$0] != nil }
    }

    private static func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let str = value as? String, !str.isEmpty {
                return str
            }
        }
        return nil
    }

    private static func extractError(from input: [String: Any]) -> String? {
        firstString(
            input["error"],
            input["error_message"],
            input["errorMessage"],
            input["error_type"],
            input["errorType"],
            input["stderr"],
            nested(input, "partialResult", "error"),
            nested(input, "partialResult", "stderr"),
            nested(input, "partialResult", "errorMessage"),
            nested(input, "error", "message"),
            nested(input, "toolResult", "error"),
            nested(input, "toolResult", "stderr"),
            nested(input, "toolResult", "errorMessage"),
            nested(input, "tool_result", "error"),
            nested(input, "tool_result", "stderr"),
            nested(input, "tool_result", "errorMessage"),
            nested(input, "result", "error"),
            nested(input, "result", "stderr"),
            nested(input, "result", "errorMessage"),
            nested(input, "tool_response", "error"),
            nested(input, "toolResponse", "error")
        )
    }

    private static func extractToolResponse(from input: [String: Any]) -> String? {
        if let direct = firstString(
            input["tool_response"],
            input["toolResponse"],
            input["output"],
            input["stdout"],
            input["stderr"],
            nested(input, "partialResult", "output"),
            nested(input, "partialResult", "stdout"),
            nested(input, "partialResult", "stderr"),
            nested(input, "result", "output"),
            nested(input, "result", "stdout"),
            nested(input, "result", "stderr"),
            nested(input, "toolResult", "output"),
            nested(input, "toolResult", "stdout"),
            nested(input, "toolResult", "stderr"),
            nested(input, "tool_result", "output"),
            nested(input, "tool_result", "stdout"),
            nested(input, "tool_result", "stderr")
        ) {
            return direct
        }

        if let returnDisplay = firstString(
            stringify(nested(input, "tool_response", "returnDisplay")),
            stringify(nested(input, "toolResponse", "returnDisplay")),
            stringify(nested(input, "result", "returnDisplay"))
        ) {
            return returnDisplay
        }

        if let llmText = firstString(
            stringify(nested(input, "tool_response", "llmContent")),
            stringify(nested(input, "toolResponse", "llmContent")),
            stringify(nested(input, "result", "llmContent")),
            stringify(nested(input, "result", "textResultForLlm")),
            stringify(nested(input, "result", "textResult")),
            stringify(nested(input, "toolResult", "textResultForLlm")),
            stringify(nested(input, "tool_result", "textResultForLlm")),
            stringify(nested(input, "toolResult", "textResult"))
        ) {
            return llmText
        }

        return firstString(
            extractTextContent(from: nested(input, "partialResult", "content")),
            extractTextContent(from: nested(input, "result", "content")),
            extractTextContent(from: input["message"]),
            extractTextContent(from: input["content"]),
            extractTextContent(from: nested(input, "toolResult", "content")),
            extractTextContent(from: nested(input, "tool_result", "content"))
        )
    }

    private static func extractLastAssistantMessage(from input: [String: Any]) -> String? {
        firstString(
            input["last_assistant_message"],
            input["lastAssistantMessage"],
            input["last_agent_message"],
            input["lastAgentMessage"],
            input["prompt_response"],
            input["promptResponse"],
            input["response"]
        ) ?? firstString(
            nested(input, "assistant", "message"),
            nested(input, "result", "message"),
            nested(input, "error", "message"),
            nested(input, "data", "content")
        ) ?? extractTextContent(from: input["message"]) ??
            extractTextContent(from: nested(input, "assistant", "content")) ??
            extractTextContent(from: nested(input, "result", "content")) ??
            extractTextContent(from: nested(input, "data", "content")) ??
            extractTextContent(from: input["content"]) ??
            extractTextContent(from: nested(input, "message", "content"))
    }

    private static func extractPrompt(from input: [String: Any]) -> String? {
        if let direct = firstString(input["prompt"], input["text"], input["message"]) {
            return direct
        }

        if let copilotPrompt = firstString(
            nested(input, "data", "content"),
            nested(input, "data", "transformedContent")
        ) {
            return copilotPrompt
        }

        if let agentPrompt = firstString(input["agent_prompt"], input["agentPrompt"]) {
            return agentPrompt
        }

        if let windsurfPrompt = firstString(nested(input, "tool_info", "user_prompt")) {
            return windsurfPrompt
        }

        if let inputMessages = input["input_messages"] as? [String], let first = inputMessages.first {
            return first
        }

        if let inputMessages = input["inputMessages"] as? [String], let first = inputMessages.first {
            return first
        }

        return extractTextContent(from: input["content"]) ??
            extractTextContent(from: nested(input, "message", "content"))
    }

    private static func extractNotificationType(from input: [String: Any]) -> String? {
        firstString(
            input["notification_type"],
            input["notificationType"],
            input["severity"],
            nested(input, "details", "type")
        )
    }

    private static func extractGeminiNotificationToolName(from input: [String: Any]) -> String? {
        firstString(
            nested(input, "details", "tool_name"),
            nested(input, "details", "toolName"),
            nested(input, "details", "tool"),
            nested(input, "details", "name"),
            nested(input, "details", "function_name"),
            nested(input, "details", "functionName")
        )
    }

    private static func extractGeminiNotificationDetails(from input: [String: Any]) -> [String: Any]? {
        guard var details = input["details"] as? [String: Any], !details.isEmpty else {
            return nil
        }

        details.removeValue(forKey: "type")
        return details.isEmpty ? nil : details
    }

    private static func extractMessage(from input: [String: Any]) -> String? {
        firstString(
            input["message"],
            input["action"],
            input["mode"],
            input["agent_name"],
            input["agentName"],
            input["error_message"],
            input["errorMessage"],
            input["error_type"],
            input["errorType"],
            input["title"],
            input["body"],
            input["sink"],
            input["reason"],
            input["trigger"],
            input["source"],
            input["compact_summary"],
            input["compactSummary"],
            input["model"],
            nested(input, "assistant", "message"),
            nested(input, "result", "message"),
            nested(input, "result", "errorMessage"),
            nested(input, "error", "message"),
            nested(input, "data", "content"),
            nested(input, "data", "model"),
            nested(input, "data", "serverName"),
            nested(input, "data", "status"),
            nested(input, "details", "message"),
            nested(input, "details", "title"),
            nested(input, "details", "description")
        ) ?? stringify(input["selected_tools"]) ??
            stringify(nested(input, "assistant", "content")) ??
            stringify(nested(input, "result", "content")) ??
            stringify(nested(input, "data", "servers")) ??
            stringify(nested(input, "data", "filesModified")) ??
            stringify(input["content"]) ??
            stringify(input["selectedTools"]) ??
            stringify(input["details"])
    }

    private static func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }

        if let str = value as? String, !str.isEmpty {
            return str
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let text = String(data: data, encoding: .utf8),
           !text.isEmpty {
            return text
        }

        return nil
    }

    private static func extractTextContent(from value: Any?) -> String? {
        guard let value else { return nil }

        if let string = value as? String, !string.isEmpty {
            return string
        }

        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String, !text.isEmpty {
                return text
            }

            if let content = dict["content"] {
                return extractTextContent(from: content)
            }
        }

        if let array = value as? [[String: Any]] {
            let parts = array.compactMap { item -> String? in
                if let text = item["text"] as? String, !text.isEmpty {
                    return text
                }
                if let thinking = item["thinking"] as? String, !thinking.isEmpty {
                    return thinking
                }
                if let content = item["content"] {
                    return extractTextContent(from: content)
                }
                return nil
            }
            if !parts.isEmpty {
                return parts.joined(separator: "\n")
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
        "AMP_SETTINGS_FILE", "CLINE_DIR",
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
