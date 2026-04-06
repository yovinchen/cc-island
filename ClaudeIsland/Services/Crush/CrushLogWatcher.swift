//
//  CrushLogWatcher.swift
//  ClaudeIsland
//
//  Watches ./.crush/logs/crush.log for appended lines and surfaces them as
//  lightweight notifications for wrapper-based Crush sessions.
//

import Foundation
import os.log

private let crushLogger = Logger(subsystem: "com.claudeisland", category: "CrushWatcher")

final class CrushLogWatcher {
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0
    private let sessionId: String
    private let cwd: String
    private let logPath: String
    private let queue = DispatchQueue(label: "com.claudeisland.crushwatcher", qos: .utility)

    init(sessionId: String, cwd: String) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.logPath = URL(fileURLWithPath: cwd)
            .appendingPathComponent(".crush/logs/crush.log")
            .path
    }

    func start() {
        queue.async { [weak self] in
            self?.startWatching()
        }
    }

    private func startWatching() {
        stopInternal()

        guard FileManager.default.fileExists(atPath: logPath),
              let handle = FileHandle(forReadingAtPath: logPath) else {
            crushLogger.debug("Crush log not found for session \(self.sessionId.prefix(8), privacy: .public)")
            return
        }

        fileHandle = handle

        do {
            lastOffset = try handle.seekToEnd()
        } catch {
            crushLogger.error("Failed to seek crush log: \(error.localizedDescription, privacy: .public)")
            return
        }

        let fd = handle.fileDescriptor
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        newSource.setEventHandler { [weak self] in
            self?.consumeDelta()
        }

        newSource.setCancelHandler { [weak self] in
            try? self?.fileHandle?.close()
            self?.fileHandle = nil
        }

        source = newSource
        newSource.resume()

        crushLogger.info("Started watching crush log for session \(self.sessionId.prefix(8), privacy: .public)")
    }

    private func consumeDelta() {
        guard let handle = fileHandle else { return }

        let currentSize: UInt64
        do {
            currentSize = try handle.seekToEnd()
        } catch {
            return
        }

        guard currentSize > lastOffset else { return }

        do {
            try handle.seek(toOffset: lastOffset)
        } catch {
            return
        }

        guard let newData = try? handle.readToEnd(),
              let newContent = String(data: newData, encoding: .utf8) else {
            return
        }

        lastOffset = currentSize

        let lines = newContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        if let data = line.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           emitStructuredEvent(from: json) {
            return
        }

        emitNotification(message: String(line.prefix(500)))
    }

    @discardableResult
    private func emitStructuredEvent(from json: [String: Any]) -> Bool {
        let eventKey = firstString(
            json["event"],
            json["type"],
            json["kind"],
            json["name"],
            json["action"]
        )?.lowercased()

        let toolName = firstString(
            json["tool_name"],
            json["tool"],
            json["name"],
            nested(json, "tool", "name")
        )

        let toolInput = anyCodableMap(
            json["tool_input"] as? [String: Any] ??
            json["input"] as? [String: Any] ??
            nested(json, "tool", "input") as? [String: Any]
        )

        let toolUseId = firstString(
            json["tool_use_id"],
            json["toolUseId"],
            json["id"],
            json["call_id"]
        )

        if let eventKey, isPreToolEvent(eventKey), let toolName {
            emit(event: HookEvent(
                sessionId: sessionId,
                source: .crush,
                cwd: cwd,
                event: "PreToolUse",
                status: "running_tool",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: toolName,
                toolInput: toolInput,
                toolUseId: toolUseId,
                notificationType: "crush_log",
                message: nil
            ))
            return true
        }

        if let eventKey, isPostToolEvent(eventKey), let toolName {
            let output = firstString(
                json["output"],
                json["stdout"],
                json["message"],
                json["msg"],
                nested(json, "result", "output"),
                nested(json, "result", "message")
            )
            emit(event: HookEvent(
                sessionId: sessionId,
                source: .crush,
                cwd: cwd,
                event: "PostToolUse",
                status: "processing",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: toolName,
                toolInput: toolInput,
                toolUseId: toolUseId,
                notificationType: "crush_log",
                message: nil,
                toolResponse: output
            ))
            return true
        }

        if let eventKey, isFailedToolEvent(eventKey), let toolName {
            let error = firstString(
                json["error"],
                json["stderr"],
                json["message"],
                json["msg"],
                nested(json, "result", "error"),
                nested(json, "result", "stderr")
            )
            emit(event: HookEvent(
                sessionId: sessionId,
                source: .crush,
                cwd: cwd,
                event: "PostToolUseFailure",
                status: "processing",
                pid: nil,
                tty: nil,
                approvalChannel: .none,
                tool: toolName,
                toolInput: toolInput,
                toolUseId: toolUseId,
                notificationType: "crush_log",
                message: error,
                error: error
            ))
            return true
        }

        if let message = firstString(
            json["message"],
            json["msg"],
            json["text"],
            stringify(json["details"])
        ) {
            emitNotification(message: String(message.prefix(500)))
            return true
        }

        return false
    }

    private func emitNotification(message: String) {
        emit(event: HookEvent(
            sessionId: sessionId,
            source: .crush,
            cwd: cwd,
            event: "Notification",
            status: "unknown",
            pid: nil,
            tty: nil,
            approvalChannel: .none,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: "crush_log",
            message: message
        ))
    }

    private func emit(event: HookEvent) {
        Task {
            await SessionStore.shared.process(.hookReceived(event))
        }
    }

    private func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let str = value as? String, !str.isEmpty {
                return str
            }
        }
        return nil
    }

    private func nested(_ dict: [String: Any], _ keys: String...) -> Any? {
        var current: Any = dict
        for key in keys {
            guard let d = current as? [String: Any], let next = d[key] else { return nil }
            current = next
        }
        return current
    }

    private func anyCodableMap(_ dict: [String: Any]?) -> [String: AnyCodable]? {
        guard let dict else { return nil }
        return dict.reduce(into: [String: AnyCodable]()) { partialResult, entry in
            partialResult[entry.key] = AnyCodable(entry.value)
        }
    }

    private func stringify(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String, !text.isEmpty { return text }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return nil
    }

    private func isPreToolEvent(_ key: String) -> Bool {
        key.contains("tool_start") || key.contains("toolstart") || key.contains("tool_begin") || key.contains("toolbegin")
    }

    private func isPostToolEvent(_ key: String) -> Bool {
        key.contains("tool_end") || key.contains("toolend") || key.contains("tool_finish") || key.contains("toolfinish") || key.contains("tool_result")
    }

    private func isFailedToolEvent(_ key: String) -> Bool {
        key.contains("tool_error") || key.contains("toolerror") || key.contains("tool_fail") || key.contains("toolfail")
    }


    func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func stopInternal() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }
}

@MainActor
final class CrushLogWatcherManager {
    static let shared = CrushLogWatcherManager()

    private var watchers: [String: CrushLogWatcher] = [:]

    private init() {}

    func startWatching(sessionId: String, cwd: String) {
        guard watchers[sessionId] == nil else { return }

        let watcher = CrushLogWatcher(sessionId: sessionId, cwd: cwd)
        watcher.start()
        watchers[sessionId] = watcher
    }

    func stopWatching(sessionId: String) {
        watchers[sessionId]?.stop()
        watchers.removeValue(forKey: sessionId)
    }
}
