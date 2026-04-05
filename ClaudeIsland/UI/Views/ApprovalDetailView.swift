//
//  ApprovalDetailView.swift
//  ClaudeIsland
//
//  Full-panel approval view matching Vibe Island style.
//  Shows session header, tool context, and either approval controls or Gemini terminal choices.
//

import SwiftUI

struct ApprovalDetailView: View {
    let session: SessionState
    let sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    @State private var showContent = false
    @State private var showButtons = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let approvalBlue = Color(red: 0.25, green: 0.48, blue: 0.85)
    private let approvalRed = Color(red: 0.82, green: 0.25, blue: 0.25)
    private let commandPreviewLineLimit = 3
    private let messagePreviewLineLimit = 3
    private let choicePreviewLineLimit = 2
    private let detailPreviewLineLimit = 2
    private let maxVisibleToolRows = 3
    private let maxCodePreviewLines = 6
    private let contentAreaMaxHeight: CGFloat = 250

    private var permission: PermissionContext? {
        session.activePermission
    }

    var body: some View {
        VStack(spacing: 0) {
            if let permission = permission {
                // Session header row
                sessionHeader
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : -4)

                Spacer().frame(height: 12)

                contentArea(permission: permission)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 8)

                Spacer(minLength: 12)

                (permission.isTerminalSelection ? AnyView(terminalSelectionButtons) : AnyView(approvalButtons))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .opacity(showButtons ? 1 : 0)
                    .offset(y: showButtons ? 0 : 10)
            } else {
                // Permission was resolved
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
            if let updated = instances.first(where: { $0.sessionId == session.sessionId }) {
                if !updated.phase.isWaitingForApproval {
                    // Navigate back to instances list after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if case .approval = viewModel.contentType {
                            viewModel.contentType = .instances
                        }
                    }
                    // Auto-collapse the notch after 3 seconds (only if still on instances list)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if viewModel.status != .closed,
                           case .instances = viewModel.contentType {
                            viewModel.notchClose()
                        }
                    }
                }
            }
        }
    }

    private func contentArea(permission: PermissionContext) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                toolCard(permission: permission)

                if permission.isTerminalSelection {
                    terminalChoiceCard(permission: permission)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 1)
        }
        .frame(maxHeight: contentAreaMaxHeight, alignment: .top)
    }

    // MARK: - Session Header (matching screenshot: project · title, badges on right)

    private var sessionHeader: some View {
        HStack(spacing: 8) {
            // Crab icon + session title
            ClaudeCrabIcon(size: 14, animateLegs: true)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                if let userMessage = session.firstUserMessage {
                    Text(String(localized: "instances.user_prefix") + " " + userMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Right-side badges: source, terminal, time
            HStack(spacing: 5) {
                Text(session.source.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())

                if let termName = session.terminalAppName {
                    Text(termName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Tool Card (warning icon + command block + description)

    private func toolCard(permission: PermissionContext) -> some View {
        let sortedKeys = Array((permission.toolInput ?? [:]).keys.sorted().filter { $0 != "command" && $0 != "description" })
        let visibleKeys = Array(sortedKeys.prefix(maxVisibleToolRows))
        let hiddenKeyCount = max(0, sortedKeys.count - visibleKeys.count)

        return VStack(alignment: .leading, spacing: 10) {
            // Warning triangle + tool name
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(claudeOrange)

                Text(MCPToolFormatter.formatToolName(permission.toolName))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(claudeOrange)
            }

            // Command block
            if let input = permission.toolInput {
                VStack(alignment: .leading, spacing: 6) {
                    // Show command (for Bash) or key-value pairs
                    if let command = input["command"] {
                        commandBlock(formatValue(command))
                    }

                    // Show description if available
                    if let desc = input["description"] {
                        Text(formatValue(desc))
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.top, 2)
                            .lineLimit(detailPreviewLineLimit)
                    }

                    // Show other keys (file_path, etc.) excluding command/description
                    ForEach(visibleKeys, id: \.self) { key in
                        toolInputRow(key: key, value: input[key]!)
                    }

                    if hiddenKeyCount > 0 {
                        compactSummaryLabel("+\(hiddenKeyCount) more fields")
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func terminalChoiceCard(permission: PermissionContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TerminalColors.amber)
                Text("Choose in Gemini Terminal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            if let message = permission.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(messagePreviewLineLimit)
            }

            VStack(alignment: .leading, spacing: 8) {
                let visibleChoices = Array(permission.choices.prefix(4))
                let hiddenChoiceCount = max(0, permission.choices.count - visibleChoices.count)

                ForEach(visibleChoices, id: \.index) { choice in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(choice.index).")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(TerminalColors.amber.opacity(0.9))
                            .frame(width: 18, alignment: .trailing)

                        Text(choice.label)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(choicePreviewLineLimit)
                    }
                }

                if hiddenChoiceCount > 0 {
                    compactSummaryLabel("+\(hiddenChoiceCount) more choices")
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
            )

            Text("Gemini requires the final choice in the terminal. Claude Island is mirroring the available options here.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
                .lineLimit(detailPreviewLineLimit)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Command Block ($ command style)

    private func commandBlock(_ command: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("$")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))

            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(commandPreviewLineLimit)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func toolInputRow(key: String, value: AnyCodable) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            let stringValue = formatValue(value)
            if isMultilineContent(stringValue) {
                codePreview(stringValue)
            } else {
                Text(stringValue)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(detailPreviewLineLimit)
            }
        }
    }

    private func codePreview(_ content: String) -> some View {
        let lines = content.components(separatedBy: "\n")
        let displayLines = Array(lines.prefix(maxCodePreviewLines))
        let hasMore = lines.count > maxCodePreviewLines

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
                Text(String(format: String(localized: "tool.more_lines %lld"), Int64(lines.count - maxCodePreviewLines)))
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

    private func compactSummaryLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white.opacity(0.35))
            .padding(.top, 2)
    }

    // MARK: - Approval Buttons (4 equal-width, colored per screenshot)

    private var approvalButtons: some View {
        HStack(spacing: 8) {
            // Deny — dark gray
            Button {
                sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
            } label: {
                Text(String(localized: "instances.deny"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Allow Once — lighter gray
            Button {
                sessionMonitor.approvePermission(sessionId: session.sessionId)
            } label: {
                Text(String(localized: "instances.allow_once"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Always Allow — blue
            Button {
                sessionMonitor.alwaysAllowPermission(sessionId: session.sessionId)
            } label: {
                Text(String(localized: "instances.always_allow"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(approvalBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Bypass — red
            Button {
                sessionMonitor.autoApprovePermission(sessionId: session.sessionId)
            } label: {
                Text(String(localized: "instances.auto_approve"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(approvalRed)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private var terminalSelectionButtons: some View {
        VStack(spacing: 8) {
            Button {
                focusTerminal()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.system(size: 13, weight: .medium))
                    Text("Go To Terminal")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Text("Selecting an option here would be misleading because Gemini only accepts the actual choice inside the terminal prompt.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Helpers

    private func focusTerminal() {
        Task {
            _ = await TerminalFocuser.shared.focusTerminal(session: session)
        }
    }

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
