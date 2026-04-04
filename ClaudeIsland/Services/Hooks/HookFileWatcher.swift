//
//  HookFileWatcher.swift
//  ClaudeIsland
//
//  Monitors hook configuration files for changes using DispatchSource.
//  Triggers repair when hooks are removed or modified by external tools.
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "HookFileWatcher")

class HookFileWatcher {
    static let shared = HookFileWatcher()

    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "com.claudeisland.hookwatcher", qos: .utility)

    /// Debounce tracking: path -> scheduled work item
    private var debounceTimers: [String: DispatchWorkItem] = [:]
    private let debounceInterval: TimeInterval = 0.5

    private var onChangeHandler: ((String) -> Void)?

    private init() {}

    /// Start watching all enabled hook configuration files
    func startWatching(onChange: @escaping (String) -> Void) {
        onChangeHandler = onChange
        refreshWatchers()
    }

    /// Stop all watchers
    func stopWatching() {
        for (_, source) in watchers {
            source.cancel()
        }
        watchers.removeAll()
        debounceTimers.removeAll()
    }

    /// Refresh watchers based on current enabled sources
    func refreshWatchers() {
        // Stop existing watchers
        stopWatching()

        let managedSources: [SessionSource] = [.claude, .codexCLI, .gemini, .cursor, .opencode, .copilot]

        for source in managedSources {
            guard AppSettings.isHookEnabled(for: source) else { continue }
            guard let hookSource = HookInstaller.hookSource(for: source) else { continue }

            let path = hookSource.configPath
            watchFile(at: path)
        }
    }

    // MARK: - Private

    private func watchFile(at path: String) {
        // Ensure directory exists
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: "{}".data(using: .utf8))
        }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            logger.warning("Cannot open \(path, privacy: .public) for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleFileChange(path: path)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watchers[path] = source

        logger.info("Watching \(path, privacy: .public)")
    }

    private func handleFileChange(path: String) {
        // Cancel existing debounce timer
        debounceTimers[path]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.debounceTimers.removeValue(forKey: path)

            logger.info("File changed: \(path, privacy: .public)")
            self?.onChangeHandler?(path)

            // If file was deleted, re-create watcher after a delay
            if !FileManager.default.fileExists(atPath: path) {
                self?.queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.watchers.removeValue(forKey: path)
                    self?.watchFile(at: path)
                }
            }
        }

        debounceTimers[path] = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
