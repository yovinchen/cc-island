//
//  ApprovalDetailView.swift
//  ClaudeIsland
//
//  Full-panel approval view with tool details and 4-tier approval buttons
//

import SwiftUI

struct ApprovalDetailView: View {
    let session: SessionState
    let sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    @State private var showContent = false
    @State private var showButtons = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

    private var permission: PermissionContext? {
        session.activePermission
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            header

            if let permission = permission {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Session info + source badges
                        sessionInfo

                        // Tool details card
                        toolDetailCard(permission: permission)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 8)

                // 4 approval buttons at bottom
                approvalButtons(permission: permission)
                    .opacity(showButtons ? 1 : 0)
                    .offset(y: showButtons ? 0 : 10)
            } else {
                // Permission was resolved while viewing
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundColor(TerminalColors.green)
                    Text("已处理")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8).delay(0.05)) {
                showContent = true
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.15)) {
                showButtons = true
            }
        }
        .onReceive(sessionMonitor.$instances) { instances in
            // Auto-navigate back when permission is resolved
            if let updated = instances.first(where: { $0.sessionId == session.sessionId }) {
                if !updated.phase.isWaitingForApproval {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if case .approval = viewModel.contentType {
                            viewModel.contentType = .instances
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    @State private var isHeaderHovered = false

    private var header: some View {
        Button {
            viewModel.contentType = .instances
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.6))
                    .frame(width: 24, height: 24)

                Text(session.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.85))
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHeaderHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHeaderHovered = $0 }
    }

    // MARK: - Session Info

    private var sessionInfo: some View {
        HStack(spacing: 6) {
            // Source badge
            if session.source != .claude {
                Text(session.source.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Terminal badge
            if let termName = session.terminalAppName {
                HStack(spacing: 3) {
                    Image(systemName: "terminal")
                        .font(.system(size: 8, weight: .medium))
                    Text(termName)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
            }

            Spacer()

            // Waiting indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(TerminalColors.amber)
                    .frame(width: 6, height: 6)
                Text(String(localized: "instances.approval_needed"))
                    .font(.system(size: 10))
                    .foregroundColor(TerminalColors.amber.opacity(0.8))
            }
        }
    }

    // MARK: - Tool Detail Card

    private func toolDetailCard(permission: PermissionContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tool name header
            HStack(spacing: 8) {
                Image(systemName: toolIcon(for: permission.toolName))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TerminalColors.amber)

                Text(MCPToolFormatter.formatToolName(permission.toolName))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(TerminalColors.amber)
            }

            // Tool input details
            if let input = permission.toolInput {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(input.keys.sorted()), id: \.self) { key in
                        toolInputRow(key: key, value: input[key]!)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(TerminalColors.amber.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func toolInputRow(key: String, value: AnyCodable) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            let stringValue = formatValue(value)
            if isMultilineContent(stringValue) {
                // Show as code block with line numbers
                codePreview(stringValue)
            } else {
                Text(stringValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(3)
            }
        }
    }

    private func codePreview(_ content: String) -> some View {
        let lines = content.components(separatedBy: "\n")
        let displayLines = Array(lines.prefix(15))
        let hasMore = lines.count > 15

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(idx + 1)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                        .frame(width: 24, alignment: .trailing)

                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            if hasMore {
                Text(String(format: String(localized: "tool.more_lines %lld"), lines.count - 15))
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(.top, 4)
                    .padding(.leading, 32)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.3))
        )
    }

    // MARK: - Approval Buttons

    private func approvalButtons(permission: PermissionContext) -> some View {
        VStack(spacing: 8) {
            Divider()
                .background(Color.white.opacity(0.1))

            // 4 equal-width buttons
            HStack(spacing: 6) {
                Button {
                    sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
                } label: {
                    Text(String(localized: "instances.deny"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    sessionMonitor.approvePermission(sessionId: session.sessionId)
                } label: {
                    Text(String(localized: "instances.allow_once"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    sessionMonitor.alwaysAllowPermission(sessionId: session.sessionId)
                } label: {
                    Text(String(localized: "instances.always_allow"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    sessionMonitor.autoApprovePermission(sessionId: session.sessionId)
                } label: {
                    Text(String(localized: "instances.auto_approve"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func toolIcon(for toolName: String) -> String {
        switch toolName.lowercased() {
        case "bash": return "terminal"
        case "read": return "doc.text"
        case "write": return "square.and.pencil"
        case "edit": return "pencil.line"
        case "glob": return "magnifyingglass"
        case "grep": return "text.magnifyingglass"
        case "webfetch", "websearch": return "globe"
        default: return "wrench"
        }
    }

    private func formatValue(_ value: AnyCodable) -> String {
        switch value.value {
        case let str as String:
            return str
        case let num as Int:
            return String(num)
        case let num as Double:
            return String(num)
        case let bool as Bool:
            return bool ? "true" : "false"
        case let arr as [Any]:
            return "[\(arr.count) items]"
        case let dict as [String: Any]:
            return "{\(dict.count) keys}"
        default:
            return "..."
        }
    }

    private func isMultilineContent(_ str: String) -> Bool {
        str.contains("\n") && str.count > 50
    }
}
