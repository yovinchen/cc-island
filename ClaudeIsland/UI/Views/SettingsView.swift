//
//  SettingsView.swift
//  ClaudeIsland
//
//  Full settings view for the independent settings window.
//  Organized into tabs: General, Hooks, Sound, Usage, Diagnostics.
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .providers

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            Divider()
                .background(Color.white.opacity(0.08))

            Group {
                if selectedTab == .providers {
                    providersTab
                        .padding(.horizontal, 26)
                        .padding(.vertical, 24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            tabContent
                        }
                        .padding(.horizontal, 26)
                        .padding(.vertical, 24)
                        .frame(maxWidth: 920, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0)))
    }

    private var settingsHeader: some View {
        VStack(spacing: 12) {
            Text(selectedTab.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.84))

            HStack(spacing: 14) {
                ForEach(SettingsTab.allCases) { tab in
                    settingsTopTab(tab)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.white.opacity(0.02),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func settingsTopTab(_ tab: SettingsTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .medium))
                    .frame(width: 26, height: 26)

                Text(tab.label)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(width: 88, height: 72)
            .foregroundColor(selectedTab == tab ? TerminalColors.blue : .white.opacity(0.55))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedTab == tab ? Color.white.opacity(0.07) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedTab == tab ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .general:
            generalTab
        case .hooks:
            hooksTab
        case .sound:
            soundTab
        case .providers:
            providersTab
        case .diagnostics:
            diagnosticsTab
        }
    }

    // MARK: - General Tab

    @ViewBuilder
    private var generalTab: some View {
        sectionHeader(String(localized: "settings.section.behavior"))

        SettingsToggle(label: String(localized: "settings.auto_expand"),
                      getter: { AppSettings.autoExpandOnTaskComplete },
                      setter: { AppSettings.autoExpandOnTaskComplete = $0 })
        SettingsToggle(label: String(localized: "settings.suppress_focused_desc"),
                      getter: { AppSettings.suppressAutoExpandWhenFocusedSession },
                      setter: { AppSettings.suppressAutoExpandWhenFocusedSession = $0 })
        SettingsToggle(label: String(localized: "settings.auto_popup_approval"),
                      getter: { AppSettings.autoPopupOnApproval },
                      setter: { AppSettings.autoPopupOnApproval = $0 })
        SettingsToggle(label: String(localized: "settings.auto_hide_idle"),
                      getter: { AppSettings.autoHideWhenIdle },
                      setter: { AppSettings.autoHideWhenIdle = $0 })
        SettingsToggle(label: String(localized: "settings.global_shortcut"),
                      getter: { AppSettings.globalShortcutEnabled },
                      setter: { AppSettings.globalShortcutEnabled = $0; KeyboardShortcutManager.shared.updateRegistration() })

        Divider().background(Color.white.opacity(0.1))

        sectionHeader(String(localized: "settings.section.system"))

        LaunchAtLoginToggle()
    }

    // MARK: - Hooks Tab

    @ViewBuilder
    private var hooksTab: some View {
        sectionHeader(String(localized: "settings.hooks.integrations"))

        SettingsHookList()

        Divider().background(Color.white.opacity(0.1))

        SettingsToggle(label: String(localized: "settings.hooks.auto_repair_desc"),
                      getter: { AppSettings.autoRepairHooks },
                      setter: { AppSettings.autoRepairHooks = $0; HookRepairManager.shared.restart() })
    }

    // MARK: - Sound Tab

    @ViewBuilder
    private var soundTab: some View {
        sectionHeader(String(localized: "settings.sound.theme"))

        SoundThemePicker()

        Divider().background(Color.white.opacity(0.1))

        sectionHeader(String(localized: "settings.sound.device"))

        Text(String(localized: "settings.sound.device_desc"))
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.5))
    }

    // MARK: - Usage Tab

    @ViewBuilder
    private var providersTab: some View {
        QuotaSettingsPane()
    }

    // MARK: - Diagnostics Tab

    @ViewBuilder
    private var diagnosticsTab: some View {
        sectionHeader(String(localized: "settings.diagnostics.title"))

        Text(String(localized: "settings.diagnostics.desc"))
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.5))

        HStack(spacing: 12) {
            Button(String(localized: "settings.diagnostics.copy")) {
                Task {
                    let log = await DiagnosticLogger.shared.export()
                    await MainActor.run {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log, forType: .string)
                    }
                }
            }
            .buttonStyle(SettingsButtonStyle())

            Button(String(localized: "settings.diagnostics.clear")) {
                Task { await DiagnosticLogger.shared.clear() }
            }
            .buttonStyle(SettingsButtonStyle(isDestructive: true))
        }
        .padding(.top, 4)

        Divider().background(Color.white.opacity(0.1))

        sectionHeader(String(localized: "settings.app_info"))

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        Text("Version \(version) (\(build))")
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.white.opacity(0.5))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white.opacity(0.8))
            .padding(.bottom, 4)
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case hooks
    case sound
    case providers
    case diagnostics

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .hooks:
            return "link"
        case .sound:
            return "speaker.wave.2"
        case .providers:
            return "square.grid.2x2"
        case .diagnostics:
            return "doc.text.magnifyingglass"
        }
    }

    var label: String {
        switch self {
        case .general:
            return String(localized: "settings.tab.general")
        case .hooks:
            return String(localized: "settings.tab.hooks")
        case .sound:
            return String(localized: "settings.tab.sound")
        case .providers:
            return String(localized: "settings.tab.usage")
        case .diagnostics:
            return String(localized: "settings.tab.diagnostics")
        }
    }

    var title: String { label }
}

// MARK: - Reusable Settings Components

struct SettingsToggle: View {
    let label: String
    let getter: () -> Bool
    let setter: (Bool) -> Void

    @State private var isOn: Bool = false

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.8))
            .tint(TerminalColors.green)
            .onAppear { isOn = getter() }
            .onChange(of: isOn) { _, newValue in
                setter(newValue)
            }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var isOn = false

    var body: some View {
        Toggle(String(localized: "settings.launch_at_login"), isOn: $isOn)
            .toggleStyle(.switch)
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.8))
            .tint(TerminalColors.green)
            .onAppear { isOn = SMAppService.mainApp.status == .enabled }
            .onChange(of: isOn) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    isOn = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

struct SettingsHookList: View {
    @State private var statuses: [SessionSource: Bool] = [:]

    private let sources: [SessionSource] = [
        .claude, .cline, .codexCLI, .gemini, .cursor, .windsurf, .kimiCLI, .kiroCLI,
        .ampCLI, .opencode, .copilot, .pi, .crush, .antigravity,
        .qoder, .qoderCLI, .droid, .codebuddy
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(sources, id: \.rawValue) { source in
                HStack(spacing: 8) {
                    // Source pixel icon
                    SourceIcon(source: source, size: 14)
                        .frame(width: 18, height: 18)

                    // Status dot
                    Circle()
                        .fill(statusColor(for: source))
                        .frame(width: 6, height: 6)
                    Text(source.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(statusText(for: source))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))

                    Button(AppSettings.isHookEnabled(for: source) ? String(localized: "menu.hooks.disable") : String(localized: "menu.hooks.enable")) {
                        if AppSettings.isHookEnabled(for: source) {
                            HookInstaller.uninstallSource(source)
                        } else {
                            HookInstaller.installSource(source)
                        }
                        refreshStatuses()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(TerminalColors.green)
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear { refreshStatuses() }
    }

    private func refreshStatuses() {
        statuses = HookInstaller.allStatuses()
    }

    private func statusColor(for source: SessionSource) -> Color {
        if !AppSettings.isHookEnabled(for: source) { return .white.opacity(0.3) }
        return (statuses[source] ?? false) ? TerminalColors.green : Color(red: 1.0, green: 0.4, blue: 0.4)
    }

    private func statusText(for source: SessionSource) -> String {
        if !AppSettings.isHookEnabled(for: source) { return String(localized: "hooks.status.disabled") }
        return (statuses[source] ?? false) ? String(localized: "hooks.status.active") : String(localized: "hooks.status.not_installed")
    }
}

struct SoundThemePicker: View {
    @State private var selected: SoundThemePack = AppSettings.soundThemePack

    var body: some View {
        Picker(String(localized: "settings.sound.theme_picker"), selection: $selected) {
            ForEach(SoundThemePack.allCases, id: \.self) { pack in
                Text(pack.displayName).tag(pack)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selected) { _, newValue in
            AppSettings.soundThemePack = newValue
        }
    }
}

struct SettingsButtonStyle: ButtonStyle {
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(isDestructive ? Color(red: 1, green: 0.4, blue: 0.4) : .white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.15 : 0.08))
            )
    }
}
