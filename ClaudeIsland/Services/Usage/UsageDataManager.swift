//
//  UsageDataManager.swift
//  ClaudeIsland
//
//  Manages API usage data collection and display.
//  Reads rate limit info from hook events and temporary files.
//

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "Usage")

/// API usage data for display
struct UsageData: Equatable, Sendable {
    /// Primary rate limit usage percentage (0.0 - 1.0)
    var primaryUsedPercent: Double?

    /// When the primary rate limit resets
    var primaryResetsAt: Date?

    /// Secondary rate limit usage percentage (0.0 - 1.0)
    var secondaryUsedPercent: Double?

    /// Model being used
    var model: String?

    /// Context window usage percentage (0.0 - 1.0)
    var contextWindowPercent: Double?

    /// Whether we have any data to show
    var hasData: Bool {
        primaryUsedPercent != nil || contextWindowPercent != nil
    }

    nonisolated static let empty = UsageData()
}

@MainActor
class UsageDataManager: ObservableObject {
    static let shared = UsageDataManager()

    /// Current usage data per session
    @Published private(set) var usageBySession: [String: UsageData] = [:]

    /// Aggregated usage (max across all sessions)
    @Published private(set) var aggregatedUsage: UsageData = .empty

    private var pollTimer: Task<Void, Never>?
    private let rateLimitFilePath = "/tmp/claude-island-rl.json"

    private init() {
        startPolling()
    }

    /// Update usage data from a hook event
    func updateFromHookEvent(sessionId: String, rateLimits: [String: Any]?) {
        guard let rateLimits = rateLimits else { return }

        var usage = usageBySession[sessionId] ?? UsageData()

        if let primary = rateLimits["primary"] as? [String: Any] {
            if let used = primary["used"] as? Double, let limit = primary["limit"] as? Double, limit > 0 {
                usage.primaryUsedPercent = used / limit
            }
            if let resetsAt = primary["resetsAt"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                usage.primaryResetsAt = formatter.date(from: resetsAt)
            }
        }

        if let secondary = rateLimits["secondary"] as? [String: Any] {
            if let used = secondary["used"] as? Double, let limit = secondary["limit"] as? Double, limit > 0 {
                usage.secondaryUsedPercent = used / limit
            }
        }

        if let model = rateLimits["model"] as? String {
            usage.model = model
        }

        if let context = rateLimits["contextWindow"] as? [String: Any] {
            if let used = context["used"] as? Double, let limit = context["limit"] as? Double, limit > 0 {
                usage.contextWindowPercent = used / limit
            }
        }

        usageBySession[sessionId] = usage
        recalculateAggregated()
    }

    /// Remove usage data for an ended session
    func removeSession(_ sessionId: String) {
        usageBySession.removeValue(forKey: sessionId)
        recalculateAggregated()
    }

    // MARK: - Private

    private func startPolling() {
        pollTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self = self, !Task.isCancelled else { return }
                self.readRateLimitFile()
            }
        }
    }

    private func readRateLimitFile() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: rateLimitFilePath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // The file format: { "session_id": "...", "rate_limits": { ... } }
        if let sessionId = json["session_id"] as? String,
           let rateLimits = json["rate_limits"] as? [String: Any] {
            updateFromHookEvent(sessionId: sessionId, rateLimits: rateLimits)
        }
    }

    private func recalculateAggregated() {
        var agg = UsageData()
        for (_, usage) in usageBySession {
            if let p = usage.primaryUsedPercent {
                agg.primaryUsedPercent = max(agg.primaryUsedPercent ?? 0, p)
            }
            if let s = usage.secondaryUsedPercent {
                agg.secondaryUsedPercent = max(agg.secondaryUsedPercent ?? 0, s)
            }
            if let c = usage.contextWindowPercent {
                agg.contextWindowPercent = max(agg.contextWindowPercent ?? 0, c)
            }
            if agg.model == nil { agg.model = usage.model }
            if let r = usage.primaryResetsAt {
                if agg.primaryResetsAt == nil || r < agg.primaryResetsAt! {
                    agg.primaryResetsAt = r
                }
            }
        }
        aggregatedUsage = agg
    }
}
