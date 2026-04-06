//
//  CodexSessionWatcher.swift
//  ClaudeIsland
//
//  Monitors ~/.codex/session_index.jsonl and Codex transcript deltas to synthesize
//  session lifecycle events for Codex App/Desktop.
//

import Foundation
import os.log

class CodexSessionWatcher {
    static let shared = CodexSessionWatcher()

    private struct TranscriptState {
        let path: String
        var cwd: String
        var lastOffset: UInt64
        var callMetadata: [String: CallMetadata]
    }

    private struct CallMetadata {
        let toolName: String
        let toolInput: [String: AnyCodable]?
    }

    private let logger = Logger(subsystem: "com.claudeisland", category: "CodexWatcher")
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var knownEntries: [String: CodexSessionEntry] = [:]
    private var transcriptStates: [String: TranscriptState] = [:]
    private let queue = DispatchQueue(label: "com.claudeisland.codex-watcher", qos: .utility)

    private init() {}

    func start() {
        guard CodexSessionIndexStore.indexFileExists else {
            logger.debug("Codex session_index.jsonl not found, skipping watcher")
            return
        }

        stop()

        let path = CodexSessionIndexStore.indexFilePath
        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            logger.warning("Failed to open session_index.jsonl for watching")
            return
        }

        let initialEntries = CodexSessionIndexStore.parse()
        knownEntries = entryMap(initialEntries)

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleFileChange()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        dispatchSource = source
        source.resume()

        logger.info("Codex session watcher started, tracking \(initialEntries.count) indexed sessions")
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        knownEntries.removeAll()
        transcriptStates.removeAll()
    }

    private func handleFileChange() {
        let entries = CodexSessionIndexStore.parse()
        let currentEntries = entryMap(entries)

        let newIds = Set(currentEntries.keys).subtracting(knownEntries.keys)
        let removedIds = Set(knownEntries.keys).subtracting(currentEntries.keys)
        let updatedIds = currentEntries.compactMap { sessionId, entry -> String? in
            guard let previous = knownEntries[sessionId] else { return nil }
            guard previous.updatedAt != entry.updatedAt else { return nil }
            return sessionId
        }

        for sessionId in newIds.sorted() {
            guard let entry = currentEntries[sessionId] else { continue }
            bootstrapSession(entry, isNewSession: true)
        }

        for sessionId in updatedIds.sorted() {
            guard let entry = currentEntries[sessionId] else { continue }
            processTranscriptDelta(for: entry)
        }

        for sessionId in removedIds {
            transcriptStates.removeValue(forKey: sessionId)
            Task {
                await SessionStore.shared.process(.sessionEnded(sessionId: sessionId))
            }
        }

        knownEntries = currentEntries
    }

    private func bootstrapSession(_ entry: CodexSessionEntry, isNewSession: Bool) {
        guard var state = resolveTranscriptState(for: entry.sessionId) else {
            if isNewSession {
                emitSessionStart(sessionId: entry.sessionId, cwd: "")
            }
            return
        }

        if isNewSession {
            emitSessionStart(sessionId: entry.sessionId, cwd: state.cwd)
        }

        if let event = latestRelevantEvent(
            in: state.path,
            sessionId: entry.sessionId,
            cwd: state.cwd,
            callMetadata: &state.callMetadata
        ) {
            if state.cwd.isEmpty, !event.cwd.isEmpty {
                state.cwd = event.cwd
            }
            emit(event)
        }

        state.lastOffset = fileSize(at: state.path)
        transcriptStates[entry.sessionId] = state
    }

    private func processTranscriptDelta(for entry: CodexSessionEntry) {
        if transcriptStates[entry.sessionId] == nil {
            bootstrapSession(entry, isNewSession: false)
            return
        }

        guard var state = transcriptStates[entry.sessionId] else { return }

        if !FileManager.default.fileExists(atPath: state.path),
           let refreshed = resolveTranscriptState(for: entry.sessionId) {
            state = refreshed
        }

        let result = readTranscriptEvents(
            in: state.path,
            fromOffset: state.lastOffset,
            sessionId: entry.sessionId,
            cwd: state.cwd,
            callMetadata: &state.callMetadata
        )

        if !result.cwd.isEmpty {
            state.cwd = result.cwd
        }
        state.lastOffset = result.nextOffset
        transcriptStates[entry.sessionId] = state

        for event in result.events {
            emit(event)
        }
    }

    private func resolveTranscriptState(for sessionId: String) -> TranscriptState? {
        guard let path = CodexSessionIndexStore.transcriptPath(for: sessionId) else {
            return nil
        }

        let metadata = CodexSessionIndexStore.transcriptMetadata(for: sessionId)
        return TranscriptState(
            path: path,
            cwd: metadata?.cwd ?? "",
            lastOffset: 0,
            callMetadata: [:]
        )
    }

    private func latestRelevantEvent(in path: String, sessionId: String, cwd: String, callMetadata: inout [String: CallMetadata]) -> HookEvent? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        var resolvedCwd = cwd
        var latest: HookEvent?

        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            if let contextCwd = contextCwd(from: line), resolvedCwd.isEmpty {
                resolvedCwd = contextCwd
            }
            if let event = desktopEvent(from: line, sessionId: sessionId, cwd: resolvedCwd, callMetadata: &callMetadata) {
                if resolvedCwd.isEmpty, !event.cwd.isEmpty {
                    resolvedCwd = event.cwd
                }
                latest = event
            }
        }

        return latest
    }

    private func readTranscriptEvents(
        in path: String,
        fromOffset: UInt64,
        sessionId: String,
        cwd: String,
        callMetadata: inout [String: CallMetadata]
    ) -> (events: [HookEvent], nextOffset: UInt64, cwd: String) {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            return ([], fromOffset, cwd)
        }
        defer { try? fileHandle.close() }

        let currentSize: UInt64
        do {
            currentSize = try fileHandle.seekToEnd()
        } catch {
            return ([], fromOffset, cwd)
        }

        let safeOffset = min(fromOffset, currentSize)

        do {
            try fileHandle.seek(toOffset: safeOffset)
        } catch {
            return ([], currentSize, cwd)
        }

        guard let data = try? fileHandle.readToEnd(),
              let content = String(data: data, encoding: .utf8) else {
            return ([], currentSize, cwd)
        }

        var resolvedCwd = cwd
        var events: [HookEvent] = []

        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            if let contextCwd = contextCwd(from: line), resolvedCwd.isEmpty {
                resolvedCwd = contextCwd
            }
            if let event = desktopEvent(from: line, sessionId: sessionId, cwd: resolvedCwd, callMetadata: &callMetadata) {
                if resolvedCwd.isEmpty, !event.cwd.isEmpty {
                    resolvedCwd = event.cwd
                }
                events.append(event)
            }
        }

        return (events, currentSize, resolvedCwd)
    }

    private func desktopEvent(from line: String, sessionId: String, cwd: String, callMetadata: inout [String: CallMetadata]) -> HookEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        if type == "response_item",
           let payload = json["payload"] as? [String: Any],
           let itemType = payload["type"] as? String {
            return desktopResponseItemEvent(from: payload, itemType: itemType, sessionId: sessionId, cwd: cwd, callMetadata: &callMetadata)
        }

        guard type == "event_msg",
              let payload = json["payload"] as? [String: Any],
              let eventType = payload["type"] as? String else {
            return nil
        }

        let resolvedCwd = cwd

        switch eventType {
        case "user_message":
            let prompt = payload["message"] as? String
            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: resolvedCwd,
                event: "UserPromptSubmit",
                status: "processing",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: nil,
                toolInput: nil,
                toolUseId: nil,
                notificationType: nil,
                message: nil,
                prompt: prompt
            )

        case "task_started":
            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: resolvedCwd,
                event: "UserPromptSubmit",
                status: "processing",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: nil,
                toolInput: nil,
                toolUseId: nil,
                notificationType: nil,
                message: nil
            )

        case "task_complete":
            let lastMessage = payload["last_agent_message"] as? String
            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: resolvedCwd,
                event: "Stop",
                status: "waiting_for_input",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: nil,
                toolInput: nil,
                toolUseId: nil,
                notificationType: nil,
                message: nil,
                lastAssistantMessage: lastMessage
            )

        case "agent_message":
            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: resolvedCwd,
                event: "Notification",
                status: "unknown",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: nil,
                toolInput: nil,
                toolUseId: nil,
                notificationType: "assistant_message",
                message: payload["message"] as? String
            )

        case "turn_aborted":
            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: resolvedCwd,
                event: "Notification",
                status: "unknown",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: nil,
                toolInput: nil,
                toolUseId: nil,
                notificationType: "turn_aborted",
                message: payload["reason"] as? String
            )

        case "thread_rolled_back":
            let count = payload["num_turns"] as? Int
            let message = count.map { "Thread rolled back \($0) turns" } ?? "Thread rolled back"
            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: resolvedCwd,
                event: "Notification",
                status: "unknown",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: nil,
                toolInput: nil,
                toolUseId: nil,
                notificationType: "thread_rolled_back",
                message: message
            )

        case "compaction":
            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: resolvedCwd,
                event: "PreCompact",
                status: "compacting",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: nil,
                toolInput: nil,
                toolUseId: nil,
                notificationType: "compaction",
                message: payload["summary"] as? String
            )

        case "context_compacted", "compacted":
            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: resolvedCwd,
                event: "PostCompact",
                status: "waiting_for_input",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: nil,
                toolInput: nil,
                toolUseId: nil,
                notificationType: "compaction_complete",
                message: payload["summary"] as? String
            )

        default:
            return nil
        }
    }

    private func desktopResponseItemEvent(
        from payload: [String: Any],
        itemType: String,
        sessionId: String,
        cwd: String,
        callMetadata: inout [String: CallMetadata]
    ) -> HookEvent? {
        switch itemType {
        case "function_call":
            guard let toolName = payload["name"] as? String,
                  let callId = payload["call_id"] as? String else {
                return nil
            }

            let toolInput = decodeToolInput(payload["arguments"])
            callMetadata[callId] = CallMetadata(toolName: toolName, toolInput: toolInput)

            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: cwd,
                event: "PreToolUse",
                status: "running_tool",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: toolName,
                toolInput: toolInput,
                toolUseId: callId,
                notificationType: nil,
                message: nil
            )

        case "function_call_output":
            guard let callId = payload["call_id"] as? String else {
                return nil
            }
            let metadata = callMetadata[callId]

            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: cwd,
                event: "PostToolUse",
                status: "processing",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: metadata?.toolName,
                toolInput: metadata?.toolInput,
                toolUseId: callId,
                notificationType: nil,
                message: nil,
                toolResponse: payload["output"] as? String
            )

        case "custom_tool_call":
            guard let toolName = payload["name"] as? String,
                  let callId = payload["call_id"] as? String else {
                return nil
            }

            let toolInput = decodeToolInput(payload["input"])
            callMetadata[callId] = CallMetadata(toolName: toolName, toolInput: toolInput)

            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: cwd,
                event: "PreToolUse",
                status: "running_tool",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: toolName,
                toolInput: toolInput,
                toolUseId: callId,
                notificationType: nil,
                message: nil
            )

        case "custom_tool_call_output":
            guard let callId = payload["call_id"] as? String else {
                return nil
            }
            let metadata = callMetadata[callId]

            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: cwd,
                event: "PostToolUse",
                status: "processing",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: metadata?.toolName,
                toolInput: metadata?.toolInput,
                toolUseId: callId,
                notificationType: nil,
                message: nil,
                toolResponse: extractCustomToolOutput(payload["output"])
            )

        case "message":
            guard let role = payload["role"] as? String, role == "assistant",
                  let content = payload["content"] as? [[String: Any]] else {
                return nil
            }

            let text = content
                .filter { ($0["type"] as? String) == "output_text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")

            guard !text.isEmpty else { return nil }

            return HookEvent(
                sessionId: sessionId,
                source: .codexDesktop,
                cwd: cwd,
                event: "Notification",
                status: "unknown",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: nil,
                toolInput: nil,
                toolUseId: nil,
                notificationType: "assistant_message",
                message: text,
                lastAssistantMessage: text
            )

        default:
            return nil
        }
    }

    private func decodeToolInput(_ raw: Any?) -> [String: AnyCodable]? {
        if let dict = raw as? [String: Any] {
            return dict.reduce(into: [String: AnyCodable]()) { partialResult, entry in
                partialResult[entry.key] = AnyCodable(entry.value)
            }
        }

        if let jsonString = raw as? String,
           let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return dict.reduce(into: [String: AnyCodable]()) { partialResult, entry in
                partialResult[entry.key] = AnyCodable(entry.value)
            }
        }

        return nil
    }

    private func extractCustomToolOutput(_ raw: Any?) -> String? {
        if let str = raw as? String {
            if let data = str.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let output = json["output"] as? String {
                return output
            }
            return str
        }

        return nil
    }

    private func emitSessionStart(sessionId: String, cwd: String) {
        emit(HookEvent(
            sessionId: sessionId,
            source: .codexDesktop,
            cwd: cwd,
            event: "SessionStart",
            status: "waiting_for_input",
            pid: nil,
            tty: nil,
            approvalChannel: .none,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: nil,
            message: nil
        ))
    }

    private func emit(_ event: HookEvent) {
        logger.debug("Codex desktop event \(event.event, privacy: .public) for session \(event.sessionId.prefix(8), privacy: .public)")
        Task {
            await SessionStore.shared.process(.hookReceived(event))
        }
    }

    private func fileSize(at path: String) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.uint64Value
    }

    private func contextCwd(from line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              type == "turn_context",
              let payload = json["payload"] as? [String: Any],
              let cwd = payload["cwd"] as? String,
              !cwd.isEmpty else {
            return nil
        }
        return cwd
    }

    private func entryMap(_ entries: [CodexSessionEntry]) -> [String: CodexSessionEntry] {
        entries.reduce(into: [:]) { result, entry in
            result[entry.sessionId] = entry
        }
    }
}
