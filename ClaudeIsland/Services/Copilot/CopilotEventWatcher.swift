//
//  CopilotEventWatcher.swift
//  ClaudeIsland
//
//  Watches the latest ~/.copilot/session-state/*/events.jsonl file for
//  supplemental hook diagnostics, especially hook failures that are otherwise
//  easy to miss from the CLI surface alone.
//

import Foundation
import os.log

private let copilotWatcherLogger = Logger(subsystem: "com.claudeisland", category: "CopilotWatcher")

final class CopilotEventWatcher {
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0
    private var lastSignature: String?
    private let sessionId: String
    private let startedAt: Date
    private let queue = DispatchQueue(label: "com.claudeisland.copilotwatcher", qos: .utility)

    init(sessionId: String) {
        self.sessionId = sessionId
        self.startedAt = Date()
    }

    func start() {
        queue.async { [weak self] in
            self?.startWatching()
        }
    }

    private func startWatching() {
        stopInternal()

        guard let path = latestEventsPath(),
              let handle = FileHandle(forReadingAtPath: path) else {
            copilotWatcherLogger.debug("Copilot session-state log not found for session \(self.sessionId.prefix(8), privacy: .public)")
            return
        }

        fileHandle = handle

        do {
            lastOffset = try handle.seekToEnd()
        } catch {
            copilotWatcherLogger.error("Failed to seek Copilot events log: \(error.localizedDescription, privacy: .public)")
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
    }

    private func latestEventsPath() -> String? {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".copilot/session-state")

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = children
            .map { $0.appendingPathComponent("events.jsonl") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let recentCandidates = candidates.filter { candidate in
            let modifiedAt = (try? candidate.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return modifiedAt >= startedAt.addingTimeInterval(-300)
        }

        let preferredCandidates = recentCandidates.isEmpty ? candidates : recentCandidates

        let sorted = preferredCandidates.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        return sorted.first?.path
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
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let eventName = firstString(json["event"], json["type"], json["name"])?.lowercased()
        guard eventName == "hook.end" else { return }

        let success = firstBool(json["success"], json["ok"]) ?? true
        guard success == false else { return }

        let hookType = firstString(json["hookType"], json["hook_type"], nested(json, "hook", "type")) ?? "unknown"
        let errorMessage = firstString(
            nested(json, "error", "message"),
            json["message"],
            json["error_message"],
            json["error"]
        ) ?? "Copilot hook failed"

        let signature = "\(hookType)|\(errorMessage)"
        guard signature != lastSignature else { return }
        lastSignature = signature

        emitNotification(message: "Copilot hook \(hookType) failed: \(String(errorMessage.prefix(300)))")
    }

    private func emitNotification(message: String) {
        let event = HookEvent(
            sessionId: sessionId,
            source: .copilot,
            cwd: FileManager.default.currentDirectoryPath,
            event: "Notification",
            status: "unknown",
            pid: nil,
            tty: nil,
            approvalChannel: .none,
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: "copilot_events",
            message: message
        )

        Task {
            await SessionStore.shared.process(.hookReceived(event))
        }
    }

    private func nested(_ dict: [String: Any], _ keys: String...) -> Any? {
        var current: Any = dict
        for key in keys {
            guard let dictionary = current as? [String: Any], let next = dictionary[key] else { return nil }
            current = next
        }
        return current
    }

    private func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let text = value as? String, !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private func firstBool(_ values: Any?...) -> Bool? {
        for value in values {
            if let bool = value as? Bool {
                return bool
            }
            if let number = value as? NSNumber {
                return number.boolValue
            }
        }
        return nil
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
final class CopilotEventWatcherManager {
    static let shared = CopilotEventWatcherManager()

    private var watchers: [String: CopilotEventWatcher] = [:]

    private init() {}

    func startWatching(sessionId: String) {
        guard watchers[sessionId] == nil else { return }

        let watcher = CopilotEventWatcher(sessionId: sessionId)
        watcher.start()
        watchers[sessionId] = watcher
    }

    func stopWatching(sessionId: String) {
        watchers[sessionId]?.stop()
        watchers.removeValue(forKey: sessionId)
    }
}
