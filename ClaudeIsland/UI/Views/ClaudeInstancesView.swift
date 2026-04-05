//
//  ClaudeInstancesView.swift
//  ClaudeIsland
//
//  Minimal instances list matching Dynamic Island aesthetic
//

import Combine
import SwiftUI

struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            instancesList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(String(localized: "instances.empty"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.4))

            Text(String(localized: "instances.empty_desc"))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        sessionMonitor.instances.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(sortedInstances) { session in
                    InstanceRow(
                        session: session,
                        onTap: { focusAndCollapse(session) },
                        onOpenTerminal: { focusAndCollapse(session) },
                        onArchive: { archiveSession(session) },
                        onApprove: { approveSession(session) },
                        onAlwaysAllow: { alwaysAllowSession(session) },
                        onAutoApprove: { autoApproveSession(session) },
                        onReject: { rejectSession(session) },
                        onShowApprovalDetail: { showApprovalDetail(session) }
                    )
                    .id(session.stableId)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    /// Focus terminal and collapse notch
    private func focusAndCollapse(_ session: SessionState) {
        Task {
            _ = await TerminalFocuser.shared.focusTerminal(session: session)
        }
        viewModel.notchClose()
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func alwaysAllowSession(_ session: SessionState) {
        sessionMonitor.alwaysAllowPermission(sessionId: session.sessionId)
    }

    private func autoApproveSession(_ session: SessionState) {
        sessionMonitor.autoApprovePermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func showApprovalDetail(_ session: SessionState) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            viewModel.contentType = .approval(session)
        }
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let onTap: () -> Void
    let onOpenTerminal: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onAlwaysAllow: () -> Void
    let onAutoApprove: () -> Void
    let onReject: () -> Void
    let onShowApprovalDetail: () -> Void

    @State private var isHovered = false
    /// Grace period flag: keeps approval UI visible for 2s after phase leaves waitingForApproval
    @State private var keepApprovalVisible = false
    @State private var approvalShowTime: Date? = nil
    @State private var now = Date()

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let minApprovalDisplaySeconds: TimeInterval = 2.0
    private let timeTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Whether we're showing the approval UI: real phase OR grace period
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval || keepApprovalVisible
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        if session.activePermission?.isTerminalSelection == true {
            return true
        }
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    private var showsApprovalDetail: Bool {
        guard isWaitingForApproval else { return false }
        return session.activePermission?.isTerminalSelection == true || !isInteractiveTool
    }

    /// Is the crab actively working (animated legs)
    private var isActive: Bool {
        session.phase == .processing || session.phase == .compacting
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Claude crab icon with status overlay
            crabWithStatus
                .padding(.top, 2)

            // Main content area
            VStack(alignment: .leading, spacing: 3) {
                // Title row: projectName · title + badges on right
                titleRow

                // Activity info row
                activityRow
            }

            Spacer(minLength: 0)

            // Action buttons (right side)
            actionButtons
                .padding(.top, 2)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if showsApprovalDetail {
                onShowApprovalDetail()
            } else {
                onTap()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .onReceive(timeTimer) { _ in now = Date() }
        .onChange(of: session.phase) { oldPhase, newPhase in
            if newPhase.isWaitingForApproval {
                approvalShowTime = Date()
                keepApprovalVisible = false
            } else if oldPhase.isWaitingForApproval {
                if oldPhase.approvalContext?.isTerminalSelection == true {
                    keepApprovalVisible = false
                } else if let showTime = approvalShowTime {
                    let elapsed = Date().timeIntervalSince(showTime)
                    if elapsed < minApprovalDisplaySeconds {
                        keepApprovalVisible = true
                        let remaining = minApprovalDisplaySeconds - elapsed
                        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                            if !session.phase.isWaitingForApproval {
                                keepApprovalVisible = false
                            }
                        }
                    }
                }
                approvalShowTime = nil
            }
        }
        .onAppear {
            now = Date()
            if session.phase.isWaitingForApproval {
                approvalShowTime = Date()
            }
        }
    }

    // MARK: - Crab Icon with Status

    private var crabWithStatus: some View {
        ZStack(alignment: .bottomTrailing) {
            ClaudeCrabIcon(
                size: 14,
                color: crabColor,
                animateLegs: isActive
            )

            // Status overlay badge
            statusBadge
                .offset(x: 4, y: 4)
        }
        .frame(width: 22, height: 22)
    }

    private var crabColor: Color {
        switch session.phase {
        case .processing, .compacting:
            return claudeOrange
        case .waitingForApproval:
            return TerminalColors.amber
        case .waitingForInput:
            return TerminalColors.green
        case .idle, .ended:
            return Color.white.opacity(0.35)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.phase {
        case .processing, .compacting:
            // Running: small spinning dot
            Circle()
                .fill(claudeOrange)
                .frame(width: 6, height: 6)
        case .waitingForApproval:
            // Needs approval: amber "?" badge
            Text("?")
                .font(.system(size: 7, weight: .heavy))
                .foregroundColor(.black)
                .frame(width: 10, height: 10)
                .background(Circle().fill(TerminalColors.amber))
        case .waitingForInput:
            // Done/ready: green checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 5, weight: .bold))
                .foregroundColor(.black)
                .frame(width: 10, height: 10)
                .background(Circle().fill(TerminalColors.green))
        case .idle, .ended:
            EmptyView()
        }
    }

    // MARK: - Title Row

    private var titleRow: some View {
        HStack(spacing: 6) {
            // Project name · display title
            HStack(spacing: 0) {
                Text(session.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)

                if session.displayTitle != session.projectName {
                    Text(" · ")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))

                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .lineLimit(1)

            Spacer(minLength: 4)

            // Right-aligned badges: source, terminal, time
            HStack(spacing: 4) {
                BadgePill(text: session.source.displayName)

                if let termName = session.terminalAppName {
                    BadgePill(text: termName)
                }

                BadgePill(
                    text: SessionPhaseHelpers.timeAgo(session.lastActivity, now: now),
                    dimmed: true
                )
            }
        }
    }

    // MARK: - Activity Row

    @ViewBuilder
    private var activityRow: some View {
        if let permission = session.activePermission, isWaitingForApproval, permission.isTerminalSelection {
            HStack(spacing: 4) {
                Text(MCPToolFormatter.formatToolName(permission.toolName))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TerminalColors.amber.opacity(0.9))
                if let message = permission.message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                } else if let choicesSummary = permission.choicesSummary {
                    Text(choicesSummary)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                } else {
                    Text("Choose in Gemini terminal")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        } else if isWaitingForApproval, let toolName = session.pendingToolName {
            // Approval state: show tool name and input
            HStack(spacing: 4) {
                Text(MCPToolFormatter.formatToolName(toolName))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TerminalColors.amber.opacity(0.9))
                if isInteractiveTool {
                    Text(String(localized: "instances.needs_input"))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                } else if let input = session.pendingToolInput {
                    Text(input)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        } else if let error = session.hookError {
            // Tool failure (e.g. Qoder PostToolUseFailure)
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(Color.red.opacity(0.8))
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Color.red.opacity(0.7))
                    .lineLimit(1)
            }
        } else if let role = session.lastMessageRole {
            // JSONL-parsed data available
            switch role {
            case "tool":
                HStack(spacing: 4) {
                    if let toolName = session.lastToolName {
                        Text(MCPToolFormatter.formatToolName(toolName))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    if let input = session.lastMessage {
                        Text(input)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            case "user":
                HStack(spacing: 4) {
                    Text(String(localized: "instances.user_prefix"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    if let msg = session.lastMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            default:
                if let msg = session.lastMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
        } else if let hookMsg = session.hookLastMessage {
            // Hook-level fallback: last AI message (from Stop event)
            Text(hookMsg)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
        } else if let hookMessage = session.hookMessage {
            HStack(spacing: 4) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 9))
                    .foregroundColor(TerminalColors.amber.opacity(0.8))
                Text(hookMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }
        } else if let prompt = session.hookPrompt {
            // Hook-level fallback: user's latest prompt (from UserPromptSubmit)
            HStack(spacing: 4) {
                Text(String(localized: "instances.user_prefix"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Text(prompt)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }
        } else if let lastMsg = session.lastMessage {
            Text(lastMsg)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if let permission = session.activePermission, permission.isTerminalSelection {
            IconButton(icon: "terminal") { onOpenTerminal() }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else if isWaitingForApproval && !isInteractiveTool {
            InlineApprovalButtons(
                onApprove: onApprove,
                onAlwaysAllow: onAlwaysAllow,
                onAutoApprove: onAutoApprove,
                onReject: onReject
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            // Archive button — only for idle or completed sessions
            if session.phase == .idle || session.phase == .waitingForInput {
                IconButton(icon: "xmark") { onArchive() }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }
}

// MARK: - Badge Pill

struct BadgePill: View {
    let text: String
    var dimmed: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white.opacity(dimmed ? 0.4 : 0.6))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(dimmed ? 0.05 : 0.08))
            .clipShape(Capsule())
    }
}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons — 4 equal-width capsules
/// Deny / Allow Once / Always Allow / Bypass
struct InlineApprovalButtons: View {
    let onApprove: () -> Void
    let onAlwaysAllow: () -> Void
    let onAutoApprove: () -> Void
    let onReject: () -> Void

    @State private var showButtons = false

    var body: some View {
        HStack(spacing: 4) {
            ApprovalCapsuleButton(
                label: String(localized: "instances.deny"),
                style: .deny,
                action: onReject
            )
            ApprovalCapsuleButton(
                label: String(localized: "instances.allow_once"),
                style: .allowOnce,
                action: onApprove
            )
            ApprovalCapsuleButton(
                label: String(localized: "instances.always_allow"),
                style: .alwaysAllow,
                action: onAlwaysAllow
            )
            ApprovalCapsuleButton(
                label: String(localized: "instances.auto_approve"),
                style: .bypass,
                action: onAutoApprove
            )
        }
        .opacity(showButtons ? 1 : 0)
        .scaleEffect(showButtons ? 1 : 0.85)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showButtons = true
            }
        }
    }
}

// MARK: - Approval Capsule Button

enum ApprovalButtonStyle {
    case deny, allowOnce, alwaysAllow, bypass

    var foregroundColor: Color {
        switch self {
        case .deny: return .white.opacity(0.7)
        case .allowOnce: return .white.opacity(0.9)
        case .alwaysAllow: return .white
        case .bypass: return .white
        }
    }

    var backgroundColor: Color {
        switch self {
        case .deny: return Color.white.opacity(0.1)
        case .allowOnce: return Color.white.opacity(0.16)
        case .alwaysAllow: return Color(red: 0.25, green: 0.48, blue: 0.85)
        case .bypass: return Color(red: 0.82, green: 0.25, blue: 0.25)
        }
    }
}

struct ApprovalCapsuleButton: View {
    let label: String
    let style: ApprovalButtonStyle
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(style.foregroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(style.backgroundColor)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
