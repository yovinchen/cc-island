//
//  AgentFileWatcher.swift
//  ClaudeIsland
//
//  Watches agent JSONL files for real-time subagent tool updates.
//  Each Task tool gets its own watcher for its agent file.
//

import Foundation
import os.log

/// Logger for agent file watcher
private let logger = Logger(subsystem: "com.claudeisland", category: "AgentFileWatcher")

/// Protocol for receiving agent file update notifications
protocol AgentFileWatcherDelegate: AnyObject {
    func didUpdateAgentTools(sessionId: String, taskToolId: String, tools: [SubagentToolInfo])
}

/// Watches a single agent JSONL file for tool updates
class AgentFileWatcher {
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var lastOffset: UInt64 = 0
    private let sessionId: String
    private let taskToolId: String
    private let agentId: String
    private let sessionSource: SessionSource
    private let cwd: String
    private let filePath: String
    private let queue = DispatchQueue(label: "com.claudeisland.agentfilewatcher", qos: .userInitiated)

    /// Track seen tool IDs to avoid duplicates
    private var seenToolIds: Set<String> = []

    weak var delegate: AgentFileWatcherDelegate?

    init(sessionId: String, taskToolId: String, agentId: String, cwd: String, source: SessionSource = .claude) {
        self.sessionId = sessionId
        self.taskToolId = taskToolId
        self.agentId = agentId
        self.sessionSource = source
        self.cwd = cwd
        self.filePath = ConversationParser.agentFilePath(agentId: agentId, cwd: cwd, source: source) ?? ""
    }

    /// Start watching the agent file
    func start() {
        queue.async { [weak self] in
            self?.startWatching()
        }
    }

    private func startWatching() {
        stopInternal()

        guard FileManager.default.fileExists(atPath: filePath),
              let handle = FileHandle(forReadingAtPath: filePath) else {
            logger.warning("Failed to open agent file: \(self.filePath, privacy: .public)")
            return
        }

        fileHandle = handle
        lastOffset = 0
        parseTools()

        do {
            lastOffset = try handle.seekToEnd()
        } catch {
            logger.error("Failed to seek to end: \(error.localizedDescription, privacy: .public)")
            return
        }

        let fd = handle.fileDescriptor
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        newSource.setEventHandler { [weak self] in
            self?.parseTools()
        }

        newSource.setCancelHandler { [weak self] in
            try? self?.fileHandle?.close()
            self?.fileHandle = nil
        }

        source = newSource
        newSource.resume()

        logger.debug("Started watching agent file: \(self.agentId.prefix(8), privacy: .public) for task: \(self.taskToolId.prefix(12), privacy: .public)")
    }

    private func parseTools() {
        let tools = ConversationParser.parseSubagentToolsSync(agentId: agentId, cwd: cwd, source: sessionSource)

        let newTools = tools.filter { !seenToolIds.contains($0.id) }
        guard !newTools.isEmpty || tools.count != seenToolIds.count else { return }

        seenToolIds = Set(tools.map { $0.id })
        logger.debug("Agent \(self.agentId.prefix(8), privacy: .public) has \(tools.count) tools")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.didUpdateAgentTools(
                sessionId: self.sessionId,
                taskToolId: self.taskToolId,
                tools: tools
            )
        }
    }

    /// Stop watching
    func stop() {
        queue.async { [weak self] in
            self?.stopInternal()
        }
    }

    private func stopInternal() {
        if source != nil {
            logger.debug("Stopped watching agent file: \(self.agentId.prefix(8), privacy: .public)")
        }
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }
}

// MARK: - Agent File Watcher Manager

/// Manages agent file watchers for active Task tools
@MainActor
class AgentFileWatcherManager {
    static let shared = AgentFileWatcherManager()

    /// Active watchers keyed by "sessionId-taskToolId"
    private var watchers: [String: AgentFileWatcher] = [:]

    weak var delegate: AgentFileWatcherDelegate?

    private init() {}

    private func watcherKey(sessionId: String, taskToolId: String, source: SessionSource) -> String {
        "\(source.rawValue)|\(sessionId)|\(taskToolId)"
    }

    func startWatching(sessionId: String, taskToolId: String, agentId: String, cwd: String, source: SessionSource = .claude) {
        let key = watcherKey(sessionId: sessionId, taskToolId: taskToolId, source: source)
        guard watchers[key] == nil else { return }

        let watcher = AgentFileWatcher(
            sessionId: sessionId,
            taskToolId: taskToolId,
            agentId: agentId,
            cwd: cwd,
            source: source
        )
        watcher.delegate = delegate
        watcher.start()
        watchers[key] = watcher

        logger.info("Started agent watcher for task \(taskToolId.prefix(12), privacy: .public)")
    }

    /// Stop watching a specific Task's agent file
    func stopWatching(sessionId: String, taskToolId: String) {
        let matchingKeys = watchers.keys.filter { $0.contains("|\(sessionId)|\(taskToolId)") }
        for key in matchingKeys {
            watchers[key]?.stop()
            watchers.removeValue(forKey: key)
        }
    }

    /// Stop all watchers for a session
    func stopWatchingSession(sessionId: String) {
        let keysToRemove = watchers.keys.filter { $0.contains("|\(sessionId)|") }
        for key in keysToRemove {
            watchers[key]?.stop()
            watchers.removeValue(forKey: key)
        }
    }

    /// Stop all watchers
    func stopAll() {
        for (_, watcher) in watchers {
            watcher.stop()
        }
        watchers.removeAll()
    }

    /// Check if we're watching a Task's agent file
    func isWatching(sessionId: String, taskToolId: String) -> Bool {
        watchers.keys.contains { $0.contains("|\(sessionId)|\(taskToolId)") }
    }
}

// MARK: - Agent File Watcher Bridge

/// Bridge between AgentFileWatcherManager and SessionStore
/// Converts delegate callbacks into SessionEvent processing
@MainActor
class AgentFileWatcherBridge: AgentFileWatcherDelegate {
    static let shared = AgentFileWatcherBridge()

    private init() {}

    func didUpdateAgentTools(sessionId: String, taskToolId: String, tools: [SubagentToolInfo]) {
        Task {
            await SessionStore.shared.process(
                .agentFileUpdated(sessionId: sessionId, taskToolId: taskToolId, tools: tools)
            )
        }
    }
}
