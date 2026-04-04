//
//  HookRepairManager.swift
//  ClaudeIsland
//
//  Automatically repairs hook configurations when they are modified or removed
//  by external tools (e.g., Claude Code overwriting settings.json).
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "HookRepair")

@MainActor
class HookRepairManager: ObservableObject {
    static let shared = HookRepairManager()

    /// Maximum repairs per hour to prevent infinite loops
    private let maxRepairsPerHour = 10

    /// Repair timestamps for rate limiting
    private var repairTimestamps: [Date] = []

    /// Whether repair is currently paused due to rate limiting
    @Published private(set) var isPaused: Bool = false

    /// Last repair result message
    @Published private(set) var lastRepairMessage: String?

    private init() {}

    /// Start monitoring and auto-repairing hooks (only if user opted in)
    func start() {
        guard AppSettings.autoRepairHooks else { return }
        HookFileWatcher.shared.startWatching { [weak self] path in
            Task { @MainActor in
                self?.handleConfigChange(path: path)
            }
        }
    }

    /// Restart monitoring (call when user toggles the auto-repair setting)
    func restart() {
        stop()
        start()
    }

    /// Stop monitoring
    func stop() {
        HookFileWatcher.shared.stopWatching()
    }

    /// Manually trigger repair of all hooks
    func repairAllNow() {
        let managedSources: [SessionSource] = [.claude, .codexCLI, .gemini, .cursor, .opencode, .copilot]
        var repaired: [String] = []

        for source in managedSources {
            guard AppSettings.isHookEnabled(for: source) else { continue }
            guard let hookSource = HookInstaller.hookSource(for: source) else { continue }

            if !hookSource.isInstalled() {
                let bridge = HookInstaller.bridgePath()
                try? hookSource.install(bridgePath: bridge)
                repaired.append(hookSource.displayName)
                logger.info("Repaired hook for \(hookSource.displayName, privacy: .public)")
            }
        }

        if repaired.isEmpty {
            lastRepairMessage = "All hooks are intact"
        } else {
            lastRepairMessage = "Repaired: \(repaired.joined(separator: ", "))"
        }
    }

    // MARK: - Private

    private func handleConfigChange(path: String) {
        // Rate limit check
        cleanupOldTimestamps()
        guard repairTimestamps.count < maxRepairsPerHour else {
            if !isPaused {
                isPaused = true
                lastRepairMessage = "Auto-repair paused (rate limit reached)"
                logger.warning("Hook repair rate limit reached")
            }
            return
        }

        isPaused = false

        // Find which source this config belongs to
        let managedSources: [SessionSource] = [.claude, .codexCLI, .gemini, .cursor, .opencode, .copilot]

        for source in managedSources {
            guard AppSettings.isHookEnabled(for: source) else { continue }
            guard let hookSource = HookInstaller.hookSource(for: source) else { continue }

            if hookSource.configPath == path {
                // Check if our hooks were removed
                if !hookSource.isInstalled() {
                    // Backup before repair
                    backupConfig(at: path)

                    let bridge = HookInstaller.bridgePath()
                    try? hookSource.install(bridgePath: bridge)
                    repairTimestamps.append(Date())

                    lastRepairMessage = "Auto-repaired: \(hookSource.displayName)"
                    logger.info("Auto-repaired hook for \(hookSource.displayName, privacy: .public)")
                }
                break
            }
        }
    }

    private func backupConfig(at path: String) {
        let backupPath = path + ".backup"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
    }

    private func cleanupOldTimestamps() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        repairTimestamps.removeAll { $0 < oneHourAgo }
    }
}
