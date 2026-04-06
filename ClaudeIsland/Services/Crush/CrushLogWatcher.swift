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
            emitNotification(message: String(line.prefix(500)))
        }
    }

    private func emitNotification(message: String) {
        let event = HookEvent(
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
        )

        Task {
            await SessionStore.shared.process(.hookReceived(event))
        }
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
