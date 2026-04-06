//
//  SessionState.swift
//  ClaudeIsland
//
//  Unified state model for a Claude session.
//  Consolidates all state that was previously spread across multiple components.
//

import Foundation

enum SessionSource: String, Codable, CaseIterable, Sendable {
    case claude
    case cline
    case codexCLI = "codex_cli"
    case codexDesktop = "codex_desktop"
    case cursor
    case opencode
    case gemini
    case copilot
    case codebuddy
    case qoder
    case droid
    case windsurf
    case kimiCLI = "kimi_cli"
    case kiroCLI = "kiro_cli"
    case ampCLI = "amp_cli"
    case trae
    case unknown

    init(rawSource: String?) {
        guard let rawSource else {
            self = .claude
            return
        }

        switch rawSource.lowercased() {
        case "claude":
            self = .claude
        case "cline":
            self = .cline
        case "codex", "codex_cli":
            self = .codexCLI
        case "codex_desktop":
            self = .codexDesktop
        case "cursor":
            self = .cursor
        case "opencode":
            self = .opencode
        case "gemini":
            self = .gemini
        case "copilot":
            self = .copilot
        case "codebuddy":
            self = .codebuddy
        case "qoder":
            self = .qoder
        case "droid":
            self = .droid
        case "windsurf":
            self = .windsurf
        case "kimi", "kimi_cli":
            self = .kimiCLI
        case "kiro", "kiro_cli":
            self = .kiroCLI
        case "amp", "amp_cli":
            self = .ampCLI
        case "trae":
            self = .trae
        default:
            self = .unknown
        }
    }

    /// Human-readable label for future UI surfaces.
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .cline: return "Cline"
        case .codexCLI: return "Codex CLI"
        case .codexDesktop: return "Codex Desktop"
        case .cursor: return "Cursor"
        case .opencode: return "OpenCode"
        case .gemini: return "Gemini"
        case .copilot: return "Copilot"
        case .codebuddy: return "CodeBuddy"
        case .qoder: return "Qoder"
        case .droid: return "Droid"
        case .windsurf: return "Windsurf"
        case .kimiCLI: return "Kimi CLI"
        case .kiroCLI: return "Kiro CLI"
        case .ampCLI: return "Amp CLI"
        case .trae: return "Trae"
        case .unknown: return "Unknown"
        }
    }

    /// Root config folder used by the local transcript helpers.
    /// Unknown sources intentionally fall back to Claude's layout until a dedicated adapter exists.
    var transcriptRootFolderName: String {
        switch self {
        case .codexCLI, .codexDesktop:
            return ".codex"
        default:
            return ".claude"
        }
    }

    /// Shared cwd -> project directory transformation used by Claude transcript paths.
    static func projectDirectoryName(for cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
    }

    /// Transcript file candidates for this source.
    func transcriptFileCandidates(sessionId: String, cwd: String) -> [String] {
        switch self {
        case .codexCLI, .codexDesktop:
            return [
                "\(NSHomeDirectory())/.codex/sessions/\(sessionId).jsonl",
                "\(NSHomeDirectory())/.codex/archived_sessions/\(sessionId).jsonl"
            ]
        default:
            let projectDir = Self.projectDirectoryName(for: cwd)
            return [
                "\(NSHomeDirectory())/.claude/projects/\(projectDir)/\(sessionId).jsonl"
            ]
        }
    }

    /// Agent transcript file candidates for nested Task sessions.
    func agentFileCandidates(agentId: String, cwd: String) -> [String] {
        switch self {
        case .codexCLI, .codexDesktop:
            return [
                "\(NSHomeDirectory())/.codex/sessions/agent-\(agentId).jsonl",
                "\(NSHomeDirectory())/.codex/archived_sessions/agent-\(agentId).jsonl"
            ]
        default:
            let projectDir = Self.projectDirectoryName(for: cwd)
            return [
                "\(NSHomeDirectory())/.claude/projects/\(projectDir)/agent-\(agentId).jsonl"
            ]
        }
    }
}

enum ApprovalChannel: String, Codable, Sendable {
    case socket
    case http
    case terminal
    case none
    case unknown

    init(rawChannel: String?, defaultSource: SessionSource) {
        _ = defaultSource
        guard let rawChannel else {
            self = .none
            return
        }

        switch rawChannel.lowercased() {
        case "socket":
            self = .socket
        case "http":
            self = .http
        case "terminal":
            self = .terminal
        case "none":
            self = .none
        default:
            self = .unknown
        }
    }

    /// Fallback channel for permission requests when a payload omitted one.
    var resolvedForPermissionRequest: ApprovalChannel {
        (self == .none || self == .unknown) ? .socket : self
    }
}

/// Complete state for a single Claude session
/// This is the single source of truth - all state reads and writes go through SessionStore
struct SessionState: Identifiable, Sendable {
    // MARK: - Identity

    let sessionId: String
    var source: SessionSource
    let cwd: String
    let projectName: String

    // MARK: - Instance Metadata

    var pid: Int?
    var tty: String?
    var isInTmux: Bool
    var approvalChannel: ApprovalChannel
    var env: [String: String]?

    // MARK: - State Machine

    /// Current phase in the session lifecycle
    var phase: SessionPhase

    // MARK: - Chat History

    /// All chat items for this session (replaces ChatHistoryManager.histories)
    var chatItems: [ChatHistoryItem]

    // MARK: - Tool Tracking

    /// Unified tool tracker (replaces 6+ dictionaries in ChatHistoryManager)
    var toolTracker: ToolTracker

    // MARK: - Subagent State

    /// State for Task tools and their nested subagent tools
    var subagentState: SubagentState

    // MARK: - Conversation Info (from JSONL parsing)

    var conversationInfo: ConversationInfo

    // MARK: - Clear Reconciliation

    /// When true, the next file update should reconcile chatItems with parser state
    /// This removes pre-/clear items that no longer exist in the JSONL
    var needsClearReconciliation: Bool

    // MARK: - Usage Data

    /// API usage and context window data for this session
    var usageData: UsageData

    // MARK: - Hook-Level Content (real-time, from hook events)

    /// Last user prompt (from UserPromptSubmit hook event)
    var hookPrompt: String?

    /// Last tool error (from PostToolUseFailure hook event, Qoder-specific)
    var hookError: String?

    /// Last hook-supplied notification message (for sources without transcript parsing)
    var hookMessage: String?

    /// Last assistant message (from Stop hook event)
    var hookLastMessage: String?

    // MARK: - Timestamps

    var lastActivity: Date
    var createdAt: Date

    // MARK: - Identifiable

    nonisolated static func key(sessionId: String, source: SessionSource) -> String {
        "\(source.rawValue):\(sessionId)"
    }

    var sessionKey: String { Self.key(sessionId: sessionId, source: source) }

    var id: String { sessionKey }

    // MARK: - Initialization

    nonisolated init(
        sessionId: String,
        source: SessionSource = .claude,
        cwd: String,
        projectName: String? = nil,
        pid: Int? = nil,
        tty: String? = nil,
        isInTmux: Bool = false,
        approvalChannel: ApprovalChannel = .none,
        env: [String: String]? = nil,
        phase: SessionPhase = .idle,
        chatItems: [ChatHistoryItem] = [],
        toolTracker: ToolTracker = ToolTracker(),
        subagentState: SubagentState = SubagentState(),
        conversationInfo: ConversationInfo = ConversationInfo(
            summary: nil, lastMessage: nil, lastMessageRole: nil,
            lastToolName: nil, firstUserMessage: nil, lastUserMessageDate: nil
        ),
        needsClearReconciliation: Bool = false,
        usageData: UsageData = .empty,
        lastActivity: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.source = source
        self.cwd = cwd
        self.projectName = projectName ?? URL(fileURLWithPath: cwd).lastPathComponent
        self.pid = pid
        self.tty = tty
        self.isInTmux = isInTmux
        self.approvalChannel = approvalChannel
        self.env = env
        self.phase = phase
        self.chatItems = chatItems
        self.toolTracker = toolTracker
        self.subagentState = subagentState
        self.conversationInfo = conversationInfo
        self.needsClearReconciliation = needsClearReconciliation
        self.usageData = usageData
        self.hookPrompt = nil
        self.hookError = nil
        self.hookMessage = nil
        self.hookLastMessage = nil
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }

    // MARK: - Derived Properties

    /// Whether this session needs user attention
    var needsAttention: Bool {
        phase.needsAttention
    }

    /// The active permission context, if any
    var activePermission: PermissionContext? {
        if case .waitingForApproval(let ctx) = phase {
            return ctx
        }
        return nil
    }

    // MARK: - UI Convenience Properties

    /// Stable identity for SwiftUI (combines PID and sessionId for animation stability)
    var stableId: String {
        if let pid = pid {
            return "\(source.rawValue):\(pid)-\(sessionId)"
        }
        return id
    }

    /// Display title: summary > first user message > project name
    var displayTitle: String {
        conversationInfo.summary ?? conversationInfo.firstUserMessage ?? projectName
    }

    /// Best hint for matching window title
    var windowHint: String {
        conversationInfo.summary ?? projectName
    }

    /// Pending tool name if waiting for approval
    var pendingToolName: String? {
        activePermission?.toolName
    }

    /// Pending tool use ID
    var pendingToolId: String? {
        activePermission?.toolUseId
    }

    /// Formatted pending tool input for display
    var pendingToolInput: String? {
        activePermission?.formattedInput
    }

    /// Last message content
    var lastMessage: String? {
        conversationInfo.lastMessage
    }

    /// Last message role
    var lastMessageRole: String? {
        conversationInfo.lastMessageRole
    }

    /// Last tool name
    var lastToolName: String? {
        conversationInfo.lastToolName
    }

    /// Summary
    var summary: String? {
        conversationInfo.summary
    }

    /// First user message
    var firstUserMessage: String? {
        conversationInfo.firstUserMessage
    }

    /// Last user message date
    var lastUserMessageDate: Date? {
        conversationInfo.lastUserMessageDate
    }

    /// Whether the session can be interacted with
    var canInteract: Bool {
        phase.needsAttention
    }

    /// Human-readable terminal/IDE app name derived from env vars
    var terminalAppName: String? {
        // Try TERM_PROGRAM first (terminal-based CLIs)
        if let termProgram = env?["TERM_PROGRAM"] {
            switch termProgram.lowercased() {
            case "apple_terminal": return "Terminal"
            case "iterm.app": return "iTerm2"
            case "ghostty": return "Ghostty"
            case "wezterm": return "WezTerm"
            case "alacritty": return "Alacritty"
            case "kitty": return "Kitty"
            case "hyper": return "Hyper"
            case "tmux": return "tmux"
            case "vscode": return "VS Code"
            case "windsurf": return "Windsurf"
            default: return termProgram
            }
        }

        // Fallback: __CFBundleIdentifier (IDE-based CLIs)
        if let bundleId = env?["__CFBundleIdentifier"] {
            let ideNames: [String: String] = [
                "com.microsoft.VSCode": "VS Code",
                "com.todesktop.230313mzl4w4u92": "Cursor",
                "com.exafunction.windsurf": "Windsurf",
                "com.jetbrains.intellij": "IntelliJ",
                "com.jetbrains.intellij.ce": "IntelliJ CE",
                "com.jetbrains.WebStorm": "WebStorm",
                "com.jetbrains.pycharm": "PyCharm",
                "com.jetbrains.pycharm.ce": "PyCharm CE",
                "com.jetbrains.goland": "GoLand",
                "com.jetbrains.CLion": "CLion",
                "com.jetbrains.rider": "Rider",
                "com.jetbrains.rubymine": "RubyMine",
                "com.jetbrains.PhpStorm": "PhpStorm",
                "dev.zed.Zed": "Zed",
            ]
            return ideNames[bundleId]
        }

        return nil
    }

    /// Whether the terminal/IDE can be focused.
    /// Supports: tmux, TERM_PROGRAM (terminals), __CFBundleIdentifier (IDEs), PID walk (fallback)
    var canFocusTerminal: Bool {
        isInTmux || env?["TERM_PROGRAM"] != nil || env?["__CFBundleIdentifier"] != nil || pid != nil
    }
}

extension SessionState: Equatable {
    nonisolated static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        lhs.sessionId == rhs.sessionId &&
            lhs.source == rhs.source &&
            lhs.cwd == rhs.cwd &&
            lhs.projectName == rhs.projectName &&
            lhs.pid == rhs.pid &&
            lhs.tty == rhs.tty &&
            lhs.isInTmux == rhs.isInTmux &&
            lhs.approvalChannel == rhs.approvalChannel &&
            lhs.env == rhs.env &&
            lhs.phase == rhs.phase &&
            lhs.chatItems == rhs.chatItems &&
            lhs.toolTracker == rhs.toolTracker &&
            lhs.subagentState == rhs.subagentState &&
            lhs.conversationInfo == rhs.conversationInfo &&
            lhs.needsClearReconciliation == rhs.needsClearReconciliation &&
            lhs.usageData == rhs.usageData &&
            lhs.lastActivity == rhs.lastActivity &&
            lhs.createdAt == rhs.createdAt
    }
}

// MARK: - Tool Tracker

/// Unified tool tracking - replaces multiple dictionaries in ChatHistoryManager
struct ToolTracker: Sendable {
    /// Tools currently in progress, keyed by tool_use_id
    var inProgress: [String: ToolInProgress]

    /// All tool IDs we've seen (for deduplication)
    var seenIds: Set<String>

    /// Last JSONL file offset for incremental parsing
    var lastSyncOffset: UInt64

    /// Last sync timestamp
    var lastSyncTime: Date?

    nonisolated init(
        inProgress: [String: ToolInProgress] = [:],
        seenIds: Set<String> = [],
        lastSyncOffset: UInt64 = 0,
        lastSyncTime: Date? = nil
    ) {
        self.inProgress = inProgress
        self.seenIds = seenIds
        self.lastSyncOffset = lastSyncOffset
        self.lastSyncTime = lastSyncTime
    }

    /// Mark a tool ID as seen, returns true if it was new
    nonisolated mutating func markSeen(_ id: String) -> Bool {
        seenIds.insert(id).inserted
    }

    /// Check if a tool ID has been seen
    nonisolated func hasSeen(_ id: String) -> Bool {
        seenIds.contains(id)
    }

    /// Start tracking a tool
    nonisolated mutating func startTool(id: String, name: String) {
        guard markSeen(id) else { return }
        inProgress[id] = ToolInProgress(
            id: id,
            name: name,
            startTime: Date(),
            phase: .running
        )
    }

    /// Complete a tool
    nonisolated mutating func completeTool(id: String, success: Bool) {
        inProgress.removeValue(forKey: id)
    }
}

extension ToolTracker: Equatable {
    nonisolated static func == (lhs: ToolTracker, rhs: ToolTracker) -> Bool {
        lhs.inProgress == rhs.inProgress &&
            lhs.seenIds == rhs.seenIds &&
            lhs.lastSyncOffset == rhs.lastSyncOffset &&
            lhs.lastSyncTime == rhs.lastSyncTime
    }
}

/// A tool currently in progress
struct ToolInProgress: Sendable {
    let id: String
    let name: String
    let startTime: Date
    var phase: ToolInProgressPhase
}

extension ToolInProgress: Equatable {
    nonisolated static func == (lhs: ToolInProgress, rhs: ToolInProgress) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.startTime == rhs.startTime &&
            lhs.phase == rhs.phase
    }
}

/// Phase of a tool in progress
enum ToolInProgressPhase: Sendable {
    case starting
    case running
    case pendingApproval
}

extension ToolInProgressPhase: Equatable {
    nonisolated static func == (lhs: ToolInProgressPhase, rhs: ToolInProgressPhase) -> Bool {
        switch (lhs, rhs) {
        case (.starting, .starting), (.running, .running), (.pendingApproval, .pendingApproval):
            return true
        default:
            return false
        }
    }
}

// MARK: - Subagent State

/// State for Task (subagent) tools
struct SubagentState: Sendable {
    /// Active Task tools, keyed by task tool_use_id
    var activeTasks: [String: TaskContext]

    /// Ordered stack of active task IDs (most recent last) - used for proper tool assignment
    /// When multiple Tasks run in parallel, we use insertion order rather than timestamps
    var taskStack: [String]

    /// Mapping of agentId to Task description (for AgentOutputTool display)
    var agentDescriptions: [String: String]

    nonisolated init(activeTasks: [String: TaskContext] = [:], taskStack: [String] = [], agentDescriptions: [String: String] = [:]) {
        self.activeTasks = activeTasks
        self.taskStack = taskStack
        self.agentDescriptions = agentDescriptions
    }

    /// Whether there's an active subagent
    nonisolated var hasActiveSubagent: Bool {
        !activeTasks.isEmpty
    }

    /// Start tracking a Task tool
    nonisolated mutating func startTask(taskToolId: String, description: String? = nil) {
        activeTasks[taskToolId] = TaskContext(
            taskToolId: taskToolId,
            startTime: Date(),
            agentId: nil,
            description: description,
            subagentTools: []
        )
    }

    /// Stop tracking a Task tool
    nonisolated mutating func stopTask(taskToolId: String) {
        activeTasks.removeValue(forKey: taskToolId)
    }

    /// Set the agentId for a Task (called when agent file is discovered)
    nonisolated mutating func setAgentId(_ agentId: String, for taskToolId: String) {
        activeTasks[taskToolId]?.agentId = agentId
        if let description = activeTasks[taskToolId]?.description {
            agentDescriptions[agentId] = description
        }
    }

    /// Add a subagent tool to a specific Task by ID
    nonisolated mutating func addSubagentToolToTask(_ tool: SubagentToolCall, taskId: String) {
        activeTasks[taskId]?.subagentTools.append(tool)
    }

    /// Set all subagent tools for a specific Task (used when updating from agent file)
    nonisolated mutating func setSubagentTools(_ tools: [SubagentToolCall], for taskId: String) {
        activeTasks[taskId]?.subagentTools = tools
    }

    /// Add a subagent tool to the most recent active Task
    nonisolated mutating func addSubagentTool(_ tool: SubagentToolCall) {
        // Find most recent active task (for parallel Task support)
        guard let mostRecentTaskId = activeTasks.keys.max(by: {
            (activeTasks[$0]?.startTime ?? .distantPast) < (activeTasks[$1]?.startTime ?? .distantPast)
        }) else { return }

        activeTasks[mostRecentTaskId]?.subagentTools.append(tool)
    }

    /// Update the status of a subagent tool across all active Tasks
    nonisolated mutating func updateSubagentToolStatus(toolId: String, status: ToolStatus) {
        for taskId in activeTasks.keys {
            if let index = activeTasks[taskId]?.subagentTools.firstIndex(where: { $0.id == toolId }) {
                activeTasks[taskId]?.subagentTools[index].status = status
                return
            }
        }
    }
}

extension SubagentState: Equatable {
    nonisolated static func == (lhs: SubagentState, rhs: SubagentState) -> Bool {
        lhs.activeTasks == rhs.activeTasks &&
            lhs.taskStack == rhs.taskStack &&
            lhs.agentDescriptions == rhs.agentDescriptions
    }
}

/// Context for an active Task tool
struct TaskContext: Sendable {
    let taskToolId: String
    let startTime: Date
    var agentId: String?
    var description: String?
    var subagentTools: [SubagentToolCall]
}

extension TaskContext: Equatable {
    nonisolated static func == (lhs: TaskContext, rhs: TaskContext) -> Bool {
        lhs.taskToolId == rhs.taskToolId &&
            lhs.startTime == rhs.startTime &&
            lhs.agentId == rhs.agentId &&
            lhs.description == rhs.description &&
            lhs.subagentTools == rhs.subagentTools
    }
}
