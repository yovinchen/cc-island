//
//  HookSetupView.swift
//  ClaudeIsland
//
//  First-run hook setup view. Detects installed AI tools and lets the user
//  choose which ones to integrate with Claude Island.
//  No hooks are injected without explicit user consent.
//

import SwiftUI

struct HookSetupView: View {
    let onComplete: () -> Void

    @State private var detectedTools: [SessionSource] = []
    @State private var selectedTools: Set<SessionSource> = []
    @State private var autoRepairEnabled: Bool = false
    @State private var isInstalling: Bool = false
    @State private var installComplete: Bool = false

    private let allTools: [SessionSource] = [
        .claude, .cline, .codexCLI, .gemini, .cursor, .windsurf, .kimiCLI, .kiroCLI,
        .ampCLI, .opencode, .copilot, .pi, .crush,
        .qoder, .droid, .codebuddy
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(String(localized: "hookSetup.title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text(String(localized: "hookSetup.desc"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.1))

            // Tool list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(allTools, id: \.rawValue) { source in
                        ToolSetupRow(
                            source: source,
                            isDetected: detectedTools.contains(source),
                            isSelected: selectedTools.contains(source)
                        ) {
                            if selectedTools.contains(source) {
                                selectedTools.remove(source)
                            } else {
                                selectedTools.insert(source)
                            }
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.vertical, 6)

                    // Auto-repair toggle
                    Button {
                        autoRepairEnabled.toggle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "hookSetup.auto_repair"))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))

                                Text(String(localized: "hookSetup.auto_repair_desc"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                            }

                            Spacer()

                            Circle()
                                .fill(autoRepairEnabled ? TerminalColors.green : Color.white.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Actions
            HStack(spacing: 12) {
                // Skip button
                Button {
                    skipSetup()
                } label: {
                    Text(String(localized: "hookSetup.skip"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                // Install button
                Button {
                    performInstall()
                } label: {
                    HStack(spacing: 6) {
                        if isInstalling {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else if installComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }

                        Text(installComplete ? String(localized: "hookSetup.done") : (selectedTools.count == 1 ? String(localized: "hookSetup.install_single") : String(format: String(localized: "hookSetup.install %lld"), selectedTools.count)))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(selectedTools.isEmpty ? .white.opacity(0.3) : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTools.isEmpty ? Color.white.opacity(0.1) : Color.white)
                    )
                }
                .buttonStyle(.plain)
                .disabled(selectedTools.isEmpty || isInstalling)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .onAppear {
            detectedTools = HookInstaller.detectInstalledTools()
            // Pre-select detected tools
            selectedTools = Set(detectedTools)
        }
    }

    private func performInstall() {
        isInstalling = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Enable selected tools in settings
            for source in allTools {
                AppSettings.setHookEnabled(selectedTools.contains(source), for: source)
            }

            // Set auto-repair preference
            AppSettings.autoRepairHooks = autoRepairEnabled

            // Install only selected hooks
            HookInstaller.installEnabledOnly()

            // Start auto-repair if enabled
            if autoRepairEnabled {
                DispatchQueue.main.async {
                    HookRepairManager.shared.start()
                }
            }

            DispatchQueue.main.async {
                AppSettings.hookSetupCompleted = true
                isInstalling = false
                installComplete = true

                // Auto-dismiss after brief success indication
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onComplete()
                }
            }
        }
    }

    private func skipSetup() {
        // Mark as completed but don't install any hooks
        AppSettings.hookSetupCompleted = true
        onComplete()
    }
}

// MARK: - Tool Setup Row

struct ToolSetupRow: View {
    let source: SessionSource
    let isDetected: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? TerminalColors.green : Color.white.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(TerminalColors.green)
                            .frame(width: 16, height: 16)

                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.black)
                    }
                }

                // Source pixel icon
                SourceIcon(source: source, size: 14)
                    .frame(width: 18, height: 18)

                // Tool name
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.8))

                    Text(configDescription(for: source))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()

                // Detection badge
                if isDetected {
                    Text(String(localized: "hookSetup.detected"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(TerminalColors.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(TerminalColors.green.opacity(0.15))
                        )
                } else {
                    Text(String(localized: "hookSetup.not_found"))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func configDescription(for source: SessionSource) -> String {
        switch source {
        case .claude: return "~/.claude/settings.json"
        case .cline: return "~/Documents/Cline/Hooks + ~/.cline/data/globalState.json (+ managed .clinerules/hooks when present, or $CLINE_DIR/data/globalState.json)"
        case .codexCLI: return "~/.codex/hooks.json + ~/.codex/config.toml"
        case .gemini: return "~/.gemini/settings.json or .gemini/settings.json"
        case .cursor: return "~/.cursor/hooks.json or .cursor/hooks.json"
        case .windsurf: return "~/.codeium/windsurf/hooks.json (+ managed .windsurf/hooks.json when present / diagnose-only /Library/Application Support/Windsurf/hooks.json)"
        case .kimiCLI: return "~/.kimi/config.toml (+ ~/.claude-island/bin/claude-island-kimi-print for print-mode fallback)"
        case .kiroCLI: return "~/.kiro/agents/claude-island.json + ~/.claude-island/bin/claude-island-kiro"
        case .ampCLI: return "~/.config/amp/plugins/claude-island.ts (+ diagnose-only .amp/settings.json / .amp/plugins/ workspace layers)"
        case .pi: return "~/.claude-island/bin/claude-island-pi + claude-island-pi-json"
        case .crush: return "~/.claude-island/bin/claude-island-crush"
        case .opencode: return "~/.config/opencode/plugins/"
        case .copilot: return "~/.copilot/config.json (+ optional .github/hooks/*.json, ~/.claude-island/bin/claude-island-copilot-json)"
        case .qoder: return "~/.qoder/settings.json (+ managed .qoder/settings.json / .qoder/settings.local.json when present)"
        case .droid: return "~/.factory/settings.json"
        case .codebuddy: return "~/.codebuddy/settings.json"
        case .trae: return "~/.trae/settings.json"
        default: return ""
        }
    }
}
