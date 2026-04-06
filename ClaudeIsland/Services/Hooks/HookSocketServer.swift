//
//  HookSocketServer.swift
//  ClaudeIsland
//
//  Unix domain socket server for real-time hook events
//  Supports request/response for permission decisions
//

import Foundation
import os.log

/// Logger for hook socket server
private let logger = Logger(subsystem: "com.claudeisland", category: "Hooks")

/// Event received from supported AI coding tool hooks
struct HookEvent: Decodable, Sendable {
    let sessionId: String
    let source: SessionSource
    let cwd: String
    let event: String
    let status: String
    let pid: Int?
    let tty: String?
    let approvalChannel: ApprovalChannel
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let notificationType: String?
    let message: String?
    let rateLimits: [String: AnyCodable]?
    let env: [String: String]?

    // Event-specific content fields (extracted from hook stdin for UI display)
    let prompt: String?                        // UserPromptSubmit: user's prompt text
    let error: String?                         // PostToolUseFailure: error message
    let toolResponse: String?                  // PostToolUse: tool execution result (truncated)
    let lastAssistantMessage: String?          // Stop: last AI response (truncated)

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case source
        case legacySource = "_source"
        case cwd, event, status, pid, tty, tool
        case approvalChannel = "approval_channel"
        case approvalChannelCamel = "approvalChannel"
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case notificationType = "notification_type"
        case message, prompt, error
        case toolResponse = "tool_response"
        case lastAssistantMessage = "last_assistant_message"
        case rateLimits = "rate_limits"
        case env = "_env"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        sessionId = try container.decode(String.self, forKey: .sessionId)
        let rawSource = try container.decodeIfPresent(String.self, forKey: .source) ??
            (try container.decodeIfPresent(String.self, forKey: .legacySource))
        source = SessionSource(rawSource: rawSource)
        cwd = try container.decode(String.self, forKey: .cwd)
        event = try container.decode(String.self, forKey: .event)
        status = try container.decode(String.self, forKey: .status)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        tty = try container.decodeIfPresent(String.self, forKey: .tty)

        let rawApprovalChannel = try container.decodeIfPresent(String.self, forKey: .approvalChannel) ??
            (try container.decodeIfPresent(String.self, forKey: .approvalChannelCamel))
        approvalChannel = ApprovalChannel(rawChannel: rawApprovalChannel, defaultSource: source)

        tool = try container.decodeIfPresent(String.self, forKey: .tool)
        toolInput = try container.decodeIfPresent([String: AnyCodable].self, forKey: .toolInput)
        toolUseId = try container.decodeIfPresent(String.self, forKey: .toolUseId)
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        rateLimits = try container.decodeIfPresent([String: AnyCodable].self, forKey: .rateLimits)
        env = try container.decodeIfPresent([String: String].self, forKey: .env)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        toolResponse = try container.decodeIfPresent(String.self, forKey: .toolResponse)
        lastAssistantMessage = try container.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
    }

    /// Create a copy with updated toolUseId
    init(sessionId: String, source: SessionSource, cwd: String, event: String, status: String, pid: Int?, tty: String?, approvalChannel: ApprovalChannel, tool: String?, toolInput: [String: AnyCodable]?, toolUseId: String?, notificationType: String?, message: String?, rateLimits: [String: AnyCodable]? = nil, env: [String: String]? = nil, prompt: String? = nil, error: String? = nil, toolResponse: String? = nil, lastAssistantMessage: String? = nil) {
        self.sessionId = sessionId
        self.source = source
        self.cwd = cwd
        self.event = event
        self.status = status
        self.pid = pid
        self.tty = tty
        self.approvalChannel = approvalChannel
        self.tool = tool
        self.toolInput = toolInput
        self.toolUseId = toolUseId
        self.notificationType = notificationType
        self.message = message
        self.rateLimits = rateLimits
        self.env = env
        self.prompt = prompt
        self.error = error
        self.toolResponse = toolResponse
        self.lastAssistantMessage = lastAssistantMessage
    }

    nonisolated var sessionPhase: SessionPhase {
        if event == "PreCompact" {
            return .compacting
        }

        switch status {
        case "waiting_for_approval":
            // Note: Full PermissionContext is constructed by SessionStore, not here
            // This is just for quick phase checks
            return .waitingForApproval(PermissionContext(
                toolUseId: toolUseId ?? "",
                toolName: tool ?? "unknown",
                toolInput: toolInput,
                receivedAt: Date()
            ))
        case "waiting_for_input":
            return .waitingForInput
        case "running_tool", "processing", "starting":
            return .processing
        case "compacting":
            return .compacting
        default:
            return .idle
        }
    }

    /// Whether this event expects a response (permission request)
    nonisolated var expectsResponse: Bool {
        event == "PermissionRequest" && status == "waiting_for_approval"
    }

    /// Resolved approval channel for the event.
    /// Claude permission requests still default to socket when the payload omitted a channel.
    nonisolated var resolvedApprovalChannel: ApprovalChannel {
        if expectsResponse && approvalChannel == .none && source == .claude {
            return .socket
        }
        return approvalChannel
    }
}

/// Response to send back to the hook
struct HookResponse: Codable {
    let decision: String // "allow", "deny", or "ask"
    let reason: String?
}

/// Pending permission request waiting for user decision
struct PendingPermission: Sendable {
    let sessionId: String
    let toolUseId: String
    let clientSocket: Int32
    let event: HookEvent
    let receivedAt: Date
}

/// Callback for hook events
typealias HookEventHandler = @Sendable (HookEvent) -> Void

/// Callback for permission response failures (socket died)
typealias PermissionFailureHandler = @Sendable (_ sessionId: String, _ toolUseId: String) -> Void

/// Unix domain socket server that receives events from Claude Code hooks
/// Uses GCD DispatchSource for non-blocking I/O
class HookSocketServer {
    static let shared = HookSocketServer()
    static let socketPath = "/tmp/claude-island.sock"

    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var eventHandler: HookEventHandler?
    private var permissionFailureHandler: PermissionFailureHandler?
    private let queue = DispatchQueue(label: "com.claudeisland.socket", qos: .userInitiated)

    /// Pending permission requests indexed by toolUseId
    private var pendingPermissions: [String: PendingPermission] = [:]
    private let permissionsLock = NSLock()

    /// Cache tool_use_id from PreToolUse to correlate with PermissionRequest
    /// Key: "sessionId:toolName:serializedInput" -> Queue of tool_use_ids (FIFO)
    /// PermissionRequest events don't include tool_use_id, so we cache from PreToolUse
    private var toolUseIdCache: [String: [String]] = [:]
    private let cacheLock = NSLock()

    private init() {}

    /// Start the socket server
    func start(onEvent: @escaping HookEventHandler, onPermissionFailure: PermissionFailureHandler? = nil) {
        queue.async { [weak self] in
            self?.startServer(onEvent: onEvent, onPermissionFailure: onPermissionFailure)
        }
    }

    private func startServer(onEvent: @escaping HookEventHandler, onPermissionFailure: PermissionFailureHandler?) {
        guard serverSocket < 0 else { return }

        eventHandler = onEvent
        permissionFailureHandler = onPermissionFailure

        unlink(Self.socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket: \(errno)")
            return
        }

        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBufferPtr = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strcpy(pathBufferPtr, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        chmod(Self.socketPath, 0o777)

        guard listen(serverSocket, 10) == 0 else {
            logger.error("Failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        logger.info("Listening on \(Self.socketPath, privacy: .public)")
        Task { await DiagnosticLogger.shared.log("Socket server started on \(Self.socketPath)", category: .socket) }

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        acceptSource?.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        acceptSource?.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
                self?.serverSocket = -1
            }
        }
        acceptSource?.resume()
    }

    /// Stop the socket server
    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(Self.socketPath)

        permissionsLock.lock()
        for (_, pending) in pendingPermissions {
            close(pending.clientSocket)
        }
        pendingPermissions.removeAll()
        permissionsLock.unlock()
    }

    /// Respond to a pending permission request by toolUseId
    func respondToPermission(toolUseId: String, decision: String, reason: String? = nil,
                             alwaysAllow: Bool = false, allowAll: Bool = false, autoApprove: Bool = false,
                             toolName: String? = nil, source: SessionSource = .claude) {
        queue.async { [weak self] in
            self?.sendPermissionResponse(toolUseId: toolUseId, decision: decision, reason: reason,
                                         alwaysAllow: alwaysAllow, allowAll: allowAll, autoApprove: autoApprove,
                                         toolName: toolName, source: source)
        }
    }

    /// Respond to permission by sessionId (finds the most recent pending for that session)
    func respondToPermissionBySession(sessionId: String, decision: String, reason: String? = nil,
                                      alwaysAllow: Bool = false, allowAll: Bool = false, autoApprove: Bool = false,
                                      toolName: String? = nil, source: SessionSource = .claude) {
        queue.async { [weak self] in
            self?.sendPermissionResponseBySession(sessionId: sessionId, decision: decision, reason: reason,
                                                  alwaysAllow: alwaysAllow, allowAll: allowAll, autoApprove: autoApprove,
                                                  toolName: toolName, source: source)
        }
    }

    /// Cancel all pending permissions for a session (when Claude stops waiting)
    func cancelPendingPermissions(sessionId: String) {
        queue.async { [weak self] in
            self?.cleanupPendingPermissions(sessionId: sessionId)
        }
    }

    /// Check if there's a pending permission request for a session
    func hasPendingPermission(sessionId: String) -> Bool {
        permissionsLock.lock()
        defer { permissionsLock.unlock() }
        return pendingPermissions.values.contains { $0.sessionId == sessionId }
    }

    /// Get the pending permission details for a session (if any)
    func getPendingPermission(sessionId: String) -> (toolName: String?, toolId: String?, toolInput: [String: AnyCodable]?)? {
        permissionsLock.lock()
        defer { permissionsLock.unlock() }
        guard let pending = pendingPermissions.values.first(where: { $0.sessionId == sessionId }) else {
            return nil
        }
        return (pending.event.tool, pending.toolUseId, pending.event.toolInput)
    }

    /// Cancel a specific pending permission by toolUseId (when tool completes via terminal approval)
    func cancelPendingPermission(toolUseId: String) {
        queue.async { [weak self] in
            self?.cleanupSpecificPermission(toolUseId: toolUseId)
        }
    }

    private func cleanupSpecificPermission(toolUseId: String) {
        permissionsLock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
            permissionsLock.unlock()
            return
        }
        permissionsLock.unlock()

        logger.debug("Tool completed externally, closing socket for \(pending.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")
        close(pending.clientSocket)
    }

    private func cleanupPendingPermissions(sessionId: String) {
        permissionsLock.lock()
        let matching = pendingPermissions.filter { $0.value.sessionId == sessionId }
        for (toolUseId, pending) in matching {
            logger.debug("Cleaning up stale permission for \(sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")
            close(pending.clientSocket)
            pendingPermissions.removeValue(forKey: toolUseId)
        }
        permissionsLock.unlock()
    }

    // MARK: - Tool Use ID Cache

    /// Encoder with sorted keys for deterministic cache keys
    private static let sortedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    /// Generate cache key from event properties
    private func cacheKey(sessionId: String, toolName: String?, toolInput: [String: AnyCodable]?) -> String {
        let inputStr: String
        if let input = toolInput,
           let data = try? Self.sortedEncoder.encode(input),
           let str = String(data: data, encoding: .utf8) {
            inputStr = str
        } else {
            inputStr = "{}"
        }
        return "\(sessionId):\(toolName ?? "unknown"):\(inputStr)"
    }

    /// Cache tool_use_id from PreToolUse event (FIFO queue per key)
    private func cacheToolUseId(event: HookEvent) {
        guard let toolUseId = event.toolUseId else { return }

        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        if toolUseIdCache[key] == nil {
            toolUseIdCache[key] = []
        }
        toolUseIdCache[key]?.append(toolUseId)
        cacheLock.unlock()

        logger.debug("Cached tool_use_id for \(event.sessionId.prefix(8), privacy: .public) tool:\(event.tool ?? "?", privacy: .public) id:\(toolUseId.prefix(12), privacy: .public)")
    }

    /// Pop and return cached tool_use_id for PermissionRequest (FIFO)
    private func popCachedToolUseId(event: HookEvent) -> String? {
        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard var queue = toolUseIdCache[key], !queue.isEmpty else {
            return nil
        }

        let toolUseId = queue.removeFirst()

        if queue.isEmpty {
            toolUseIdCache.removeValue(forKey: key)
        } else {
            toolUseIdCache[key] = queue
        }

        logger.debug("Retrieved cached tool_use_id for \(event.sessionId.prefix(8), privacy: .public) tool:\(event.tool ?? "?", privacy: .public) id:\(toolUseId.prefix(12), privacy: .public)")
        return toolUseId
    }

    /// Clean up cache entries for a session (on session end)
    private func cleanupCache(sessionId: String) {
        cacheLock.lock()
        let keysToRemove = toolUseIdCache.keys.filter { $0.hasPrefix("\(sessionId):") }
        for key in keysToRemove {
            toolUseIdCache.removeValue(forKey: key)
        }
        cacheLock.unlock()

        if !keysToRemove.isEmpty {
            logger.debug("Cleaned up \(keysToRemove.count) cache entries for session \(sessionId.prefix(8), privacy: .public)")
        }
    }

    // MARK: - Private

    private func acceptConnection() {
        let clientSocket = accept(serverSocket, nil, nil)
        guard clientSocket >= 0 else { return }

        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        handleClient(clientSocket)
    }

    private func handleClient(_ clientSocket: Int32) {
        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        var allData = Data()
        var buffer = [UInt8](repeating: 0, count: 131072)
        var pollFd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)

        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 0.5 {
            let pollResult = poll(&pollFd, 1, 50)

            if pollResult > 0 && (pollFd.revents & Int16(POLLIN)) != 0 {
                let bytesRead = read(clientSocket, &buffer, buffer.count)

                if bytesRead > 0 {
                    allData.append(contentsOf: buffer[0..<bytesRead])
                } else if bytesRead == 0 {
                    break
                } else if errno != EAGAIN && errno != EWOULDBLOCK {
                    break
                }
            } else if pollResult == 0 {
                if !allData.isEmpty {
                    break
                }
            } else {
                break
            }
        }

        guard !allData.isEmpty else {
            close(clientSocket)
            return
        }

        let data = allData

        guard let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
            logger.warning("Failed to parse event: \(String(data: data, encoding: .utf8) ?? "?", privacy: .public)")
            close(clientSocket)
            return
        }

        logger.debug("Received: \(event.event, privacy: .public) for \(event.sessionId.prefix(8), privacy: .public)")
        Task { await DiagnosticLogger.shared.log("Received \(event.event) from \(event.source.rawValue) session:\(event.sessionId.prefix(8))", category: .socket) }

        if event.event == "PreToolUse" {
            cacheToolUseId(event: event)
        }

        if event.event == "SessionEnd" {
            cleanupCache(sessionId: event.sessionId)
        }

        if event.expectsResponse {
            let toolUseId: String
            if let eventToolUseId = event.toolUseId {
                toolUseId = eventToolUseId
            } else if let cachedToolUseId = popCachedToolUseId(event: event) {
                toolUseId = cachedToolUseId
            } else {
                logger.warning("Permission request missing tool_use_id for \(event.sessionId.prefix(8), privacy: .public) - no cache hit")
                close(clientSocket)
                eventHandler?(event)
                return
            }

            logger.debug("Permission request - keeping socket open for \(event.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public)")

            let updatedEvent = HookEvent(
                sessionId: event.sessionId,
                source: event.source,
                cwd: event.cwd,
                event: event.event,
                status: event.status,
                pid: event.pid,
                tty: event.tty,
                approvalChannel: event.resolvedApprovalChannel,
                tool: event.tool,
                toolInput: event.toolInput,
                toolUseId: toolUseId,  // Use resolved toolUseId
                notificationType: event.notificationType,
                message: event.message,
                rateLimits: event.rateLimits,
                env: event.env
            )

            let pending = PendingPermission(
                sessionId: event.sessionId,
                toolUseId: toolUseId,
                clientSocket: clientSocket,
                event: updatedEvent,
                receivedAt: Date()
            )
            permissionsLock.lock()
            pendingPermissions[toolUseId] = pending
            permissionsLock.unlock()

            eventHandler?(updatedEvent)

            // Send macOS system notification for permission requests
            Task { @MainActor in
                NotificationManager.shared.sendPermissionNotification(
                    sessionId: event.sessionId,
                    toolName: event.tool ?? "Tool",
                    projectName: event.cwd.components(separatedBy: "/").last
                )
            }
            return
        } else {
            close(clientSocket)
        }

        eventHandler?(event)
    }

    /// Sources that use Claude Code-compatible hookSpecificOutput response format for PermissionRequest.
    /// These CLIs have a dedicated PermissionRequest event and accept
    /// { hookSpecificOutput: { decision: { behavior, updatedPermissions } } } structure.
    /// Note: CodeBuddy and Qoder handle permissions via PreToolUse's `permissionDecision` field,
    /// so they use the generic response format here.
    private static let hookSpecificOutputSources: Set<SessionSource> = [
        .claude, .droid
    ]

    /// Build response JSON data based on source type
    private func buildResponseData(decision: String, reason: String?, alwaysAllow: Bool, allowAll: Bool, autoApprove: Bool, toolName: String?, source: SessionSource) -> Data? {
        if Self.hookSpecificOutputSources.contains(source) {
            return buildHookSpecificOutputResponse(decision: decision, reason: reason, alwaysAllow: alwaysAllow, allowAll: allowAll, autoApprove: autoApprove, toolName: toolName)
        } else if source == .cursor {
            return buildCursorResponse(decision: decision, alwaysAllow: alwaysAllow)
        } else if source == .copilot || source == .ampCLI {
            return buildCopilotResponse(decision: decision, reason: reason)
        } else if source == .cline {
            return buildClineResponse(decision: decision, reason: reason)
        } else if source == .windsurf {
            return buildBlockingMessageResponse(decision: decision, reason: reason)
        } else if source == .qoder || source == .codebuddy || source == .codexCLI || source == .kimiCLI {
            return buildPreToolUsePermissionResponse(decision: decision, reason: reason)
        } else {
            let response = HookResponse(decision: decision, reason: reason)
            return try? JSONEncoder().encode(response)
        }
    }

    /// Build Cursor-specific permission response format
    /// Cursor expects: {"continue": true/false, "permission": "allow|deny|ask"}
    /// - Allow Once: {"continue": true}
    /// - Always Allow: {"continue": true, "permission": "allow"}
    /// - Deny: {"continue": false}
    private func buildCursorResponse(decision: String, alwaysAllow: Bool) -> Data? {
        var response: [String: Any] = [:]

        if decision == "allow" {
            response["continue"] = true
            if alwaysAllow {
                response["permission"] = "allow"
            }
        } else {
            response["continue"] = false
        }

        return try? JSONSerialization.data(withJSONObject: response, options: [])
    }

    /// Build Copilot CLI preToolUse response format.
    /// Copilot expects a flat JSON object rather than Claude-style hookSpecificOutput.
    /// {"permissionDecision":"allow|deny|ask","permissionDecisionReason":"..."}
    private func buildCopilotResponse(decision: String, reason: String?) -> Data? {
        let response: [String: Any] = [
            "permissionDecision": decision == "allow" ? "allow" : "deny",
            "permissionDecisionReason": reason ?? (decision == "allow" ? "Approved by user" : "Denied by user")
        ]
        return try? JSONSerialization.data(withJSONObject: response, options: [])
    }

    /// Build a plain blocking message payload for CLIs that only care about stderr + exit 2.
    private func buildBlockingMessageResponse(decision: String, reason: String?) -> Data? {
        guard decision != "allow" else { return Data() }
        let message = reason ?? "Denied by Claude Island"
        return message.data(using: .utf8)
    }

    /// Build Cline hook response format.
    /// Cline pre-tool hooks use stdout JSON like {"cancel":true|false,"errorMessage":"..."}.
    private func buildClineResponse(decision: String, reason: String?) -> Data? {
        var response: [String: Any] = [
            "cancel": decision != "allow"
        ]

        if decision != "allow" {
            response["errorMessage"] = reason ?? "Cancelled by Claude Island"
        }

        return try? JSONSerialization.data(withJSONObject: response, options: [])
    }

    /// Build Qoder/CodeBuddy PreToolUse permission response format.
    /// These CLIs use PreToolUse's `permissionDecision` field instead of a dedicated PermissionRequest event.
    /// Expected format:
    /// { "hookSpecificOutput": { "hookEventName": "PreToolUse", "permissionDecision": "allow|deny", "permissionDecisionReason": "..." } }
    private func buildPreToolUsePermissionResponse(decision: String, reason: String?) -> Data? {
        let hookSpecificOutput: [String: Any] = [
            "hookEventName": "PreToolUse",
            "permissionDecision": decision == "allow" ? "allow" : "deny",
            "permissionDecisionReason": reason ?? (decision == "allow" ? "Approved by user" : "Denied by user")
        ]
        let responseDict: [String: Any] = [
            "hookSpecificOutput": hookSpecificOutput
        ]
        return try? JSONSerialization.data(withJSONObject: responseDict, options: [])
    }

    /// Build hookSpecificOutput format for Claude Code-compatible CLIs
    /// See: https://code.claude.com/docs/en/hooks
    ///
    /// Correct format:
    /// {
    ///   "hookSpecificOutput": {
    ///     "hookEventName": "PermissionRequest",
    ///     "decision": {
    ///       "behavior": "allow" | "deny",
    ///       "message": "...",              // deny only
    ///       "updatedPermissions": [        // allow only, INSIDE decision
    ///         {
    ///           "type": "addRules" | "setMode",
    ///           "behavior": "allow",       // for addRules
    ///           "destination": "session",
    ///           "rules": [{ "toolName": "Bash" }],  // for addRules
    ///           "mode": "bypassPermissions"          // for setMode
    ///         }
    ///       ]
    ///     }
    ///   }
    /// }
    private func buildHookSpecificOutputResponse(decision: String, reason: String?, alwaysAllow: Bool, allowAll: Bool, autoApprove: Bool, toolName: String?) -> Data? {
        var decisionDict: [String: Any] = [
            "behavior": decision == "allow" ? "allow" : "deny"
        ]

        if decision == "deny" {
            decisionDict["message"] = reason ?? "Denied by user"
        }

        if decision == "allow" {
            if autoApprove {
                // Bypass: setMode to bypass all permission checks
                decisionDict["updatedPermissions"] = [
                    [
                        "type": "setMode",
                        "mode": "bypassPermissions",
                        "destination": "session"
                    ] as [String: Any]
                ]
            } else if allowAll {
                // Allow All: setMode to accept edits without asking
                decisionDict["updatedPermissions"] = [
                    [
                        "type": "setMode",
                        "mode": "acceptEdits",
                        "destination": "session"
                    ] as [String: Any]
                ]
            } else if alwaysAllow, let tool = toolName {
                // Always Allow: addRules for the specific tool
                decisionDict["updatedPermissions"] = [
                    [
                        "type": "addRules",
                        "behavior": "allow",
                        "destination": "session",
                        "rules": [["toolName": tool]]
                    ] as [String: Any]
                ]
            }
            // Allow Once: no updatedPermissions needed
        }

        let hookSpecificOutput: [String: Any] = [
            "hookEventName": "PermissionRequest",
            "decision": decisionDict
        ]

        let responseDict: [String: Any] = [
            "hookSpecificOutput": hookSpecificOutput
        ]

        return try? JSONSerialization.data(withJSONObject: responseDict, options: [])
    }

    private func sendPermissionResponse(toolUseId: String, decision: String, reason: String?,
                                        alwaysAllow: Bool = false, allowAll: Bool = false, autoApprove: Bool = false,
                                        toolName: String? = nil, source: SessionSource = .claude) {
        permissionsLock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
            permissionsLock.unlock()
            logger.debug("No pending permission for toolUseId: \(toolUseId.prefix(12), privacy: .public)")
            return
        }
        permissionsLock.unlock()

        guard let data = buildResponseData(decision: decision, reason: reason, alwaysAllow: alwaysAllow, allowAll: allowAll, autoApprove: autoApprove, toolName: toolName, source: source) else {
            close(pending.clientSocket)
            return
        }

        let suffix = autoApprove ? " (bypass)" : (allowAll ? " (allow-all)" : (alwaysAllow ? " (always)" : ""))
        let age = Date().timeIntervalSince(pending.receivedAt)
        logger.info("Sending response: \(decision, privacy: .public)\(suffix, privacy: .public) for \(pending.sessionId.prefix(8), privacy: .public) tool:\(toolUseId.prefix(12), privacy: .public) (age: \(String(format: "%.1f", age), privacy: .public)s)")

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                logger.error("Failed to get data buffer address")
                return
            }
            let result = write(pending.clientSocket, baseAddress, data.count)
            if result < 0 {
                logger.error("Write failed with errno: \(errno)")
            } else {
                logger.debug("Write succeeded: \(result) bytes")
            }
        }

        close(pending.clientSocket)
    }

    private func sendPermissionResponseBySession(sessionId: String, decision: String, reason: String?,
                                                  alwaysAllow: Bool = false, allowAll: Bool = false, autoApprove: Bool = false,
                                                  toolName: String? = nil, source: SessionSource = .claude) {
        permissionsLock.lock()
        let matchingPending = pendingPermissions.values
            .filter { $0.sessionId == sessionId }
            .sorted { $0.receivedAt > $1.receivedAt }
            .first

        guard let pending = matchingPending else {
            permissionsLock.unlock()
            logger.debug("No pending permission for session: \(sessionId.prefix(8), privacy: .public)")
            return
        }

        pendingPermissions.removeValue(forKey: pending.toolUseId)
        permissionsLock.unlock()

        guard let data = buildResponseData(decision: decision, reason: reason, alwaysAllow: alwaysAllow, allowAll: allowAll, autoApprove: autoApprove, toolName: toolName, source: source) else {
            close(pending.clientSocket)
            permissionFailureHandler?(sessionId, pending.toolUseId)
            return
        }

        let suffix = autoApprove ? " (bypass)" : (allowAll ? " (allow-all)" : (alwaysAllow ? " (always)" : ""))
        let age = Date().timeIntervalSince(pending.receivedAt)
        logger.info("Sending response: \(decision, privacy: .public)\(suffix, privacy: .public) for \(sessionId.prefix(8), privacy: .public) tool:\(pending.toolUseId.prefix(12), privacy: .public) (age: \(String(format: "%.1f", age), privacy: .public)s)")

        var writeSuccess = false
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                logger.error("Failed to get data buffer address")
                return
            }
            let result = write(pending.clientSocket, baseAddress, data.count)
            if result < 0 {
                logger.error("Write failed with errno: \(errno)")
            } else {
                logger.debug("Write succeeded: \(result) bytes")
                writeSuccess = true
            }
        }

        close(pending.clientSocket)

        if !writeSuccess {
            permissionFailureHandler?(sessionId, pending.toolUseId)
        }
    }
}

// MARK: - AnyCodable for tool_input

/// Type-erasing codable wrapper for heterogeneous values
/// Used to decode JSON objects with mixed value types
struct AnyCodable: Codable, @unchecked Sendable {
    /// The underlying value (nonisolated(unsafe) because Any is not Sendable)
    nonisolated(unsafe) let value: Any

    /// Initialize with any value
    init(_ value: Any) {
        self.value = value
    }

    /// Decode from JSON
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    /// Encode to JSON
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Cannot encode value"))
        }
    }
}
