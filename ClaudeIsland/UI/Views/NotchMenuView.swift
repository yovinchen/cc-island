//
//  NotchMenuView.swift
//  ClaudeIsland
//
//  Minimal menu matching Dynamic Island aesthetic
//

import ApplicationServices
import Combine
import SwiftUI
import ServiceManagement
import Sparkle

// MARK: - NotchMenuView

struct NotchMenuView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @ObservedObject private var soundSelector = SoundSelector.shared
    @State private var hooksInstalled: Bool = false
    @State private var launchAtLogin: Bool = false
    @State private var autoExpandOnTaskComplete: Bool = AppSettings.autoExpandOnTaskComplete
    @State private var suppressAutoExpandWhenFocusedSession: Bool = AppSettings.suppressAutoExpandWhenFocusedSession
    @State private var autoHideWhenIdle: Bool = AppSettings.autoHideWhenIdle
    @State private var showUsageData: Bool = AppSettings.showUsageData
    @State private var globalShortcutEnabled: Bool = AppSettings.globalShortcutEnabled
    @State private var autoPopupOnApproval: Bool = AppSettings.autoPopupOnApproval

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                // Back button
                MenuRow(
                    icon: "chevron.left",
                    label: String(localized: "menu.back")
                ) {
                    viewModel.toggleMenu()
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // Appearance settings
                ScreenPickerRow(screenSelector: screenSelector)
                SoundPickerRow(soundSelector: soundSelector)

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // Behavior settings
                MenuToggleRow(
                    icon: "arrow.down.to.line.compact",
                    label: String(localized: "settings.auto_expand"),
                    isOn: autoExpandOnTaskComplete
                ) {
                    autoExpandOnTaskComplete.toggle()
                    AppSettings.autoExpandOnTaskComplete = autoExpandOnTaskComplete
                }

                MenuToggleRow(
                    icon: "bell.badge",
                    label: String(localized: "settings.auto_popup_approval"),
                    isOn: autoPopupOnApproval
                ) {
                    autoPopupOnApproval.toggle()
                    AppSettings.autoPopupOnApproval = autoPopupOnApproval
                }

                MenuToggleRow(
                    icon: "scope",
                    label: String(localized: "settings.suppress_focused"),
                    isOn: suppressAutoExpandWhenFocusedSession
                ) {
                    suppressAutoExpandWhenFocusedSession.toggle()
                    AppSettings.suppressAutoExpandWhenFocusedSession = suppressAutoExpandWhenFocusedSession
                }

                MenuToggleRow(
                    icon: "eye.slash",
                    label: String(localized: "settings.auto_hide_idle"),
                    isOn: autoHideWhenIdle
                ) {
                    autoHideWhenIdle.toggle()
                    AppSettings.autoHideWhenIdle = autoHideWhenIdle
                    NotchActivityCoordinator.shared.startIdleCheckIfNeeded()
                }

                MenuToggleRow(
                    icon: "chart.bar",
                    label: String(localized: "settings.show_usage"),
                    isOn: showUsageData
                ) {
                    showUsageData.toggle()
                    AppSettings.showUsageData = showUsageData
                }

                MenuToggleRow(
                    icon: "keyboard",
                    label: String(localized: "settings.global_shortcut"),
                    isOn: globalShortcutEnabled
                ) {
                    globalShortcutEnabled.toggle()
                    AppSettings.globalShortcutEnabled = globalShortcutEnabled
                    KeyboardShortcutManager.shared.updateRegistration()
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // Hook status section
                HookStatusSection()

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                MenuRow(
                    icon: "gauge.medium",
                    label: String(localized: "menu.open_quota")
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.contentType = .quota
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // System settings
                MenuToggleRow(
                    icon: "power",
                    label: String(localized: "menu.launch_at_login"),
                    isOn: launchAtLogin
                ) {
                    do {
                        if launchAtLogin {
                            try SMAppService.mainApp.unregister()
                            launchAtLogin = false
                        } else {
                            try SMAppService.mainApp.register()
                            launchAtLogin = true
                        }
                    } catch {
                        print("Failed to toggle launch at login: \(error)")
                    }
                }

                AccessibilityRow(isEnabled: AXIsProcessTrusted())

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                // About
                UpdateRow(updateManager: updateManager)

                MenuRow(
                    icon: "gearshape",
                    label: String(localized: "menu.open_settings")
                ) {
                    SettingsWindowController.show()
                }

                MenuRow(
                    icon: "doc.text",
                    label: String(localized: "menu.export_log")
                ) {
                    Task {
                        let log = await DiagnosticLogger.shared.export()
                        await MainActor.run {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(log, forType: .string)
                        }
                    }
                }

                MenuRow(
                    icon: "star",
                    label: String(localized: "menu.star_github")
                ) {
                    if let url = URL(string: "https://github.com/farouqaldori/claude-island") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 4)

                MenuRow(
                    icon: "xmark.circle",
                    label: String(localized: "menu.quit"),
                    isDestructive: true
                ) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            refreshStates()
        }
        .onChange(of: viewModel.contentType) { _, newValue in
            if newValue == .menu {
                refreshStates()
            }
        }
    }

    private func refreshStates() {
        hooksInstalled = HookInstaller.isInstalled()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        autoExpandOnTaskComplete = AppSettings.autoExpandOnTaskComplete
        suppressAutoExpandWhenFocusedSession = AppSettings.suppressAutoExpandWhenFocusedSession
        autoHideWhenIdle = AppSettings.autoHideWhenIdle
        showUsageData = AppSettings.showUsageData
        globalShortcutEnabled = AppSettings.globalShortcutEnabled
        autoPopupOnApproval = AppSettings.autoPopupOnApproval
        screenSelector.refreshScreens()
    }
}

// MARK: - Hook Status Section

struct HookStatusSection: View {
    @State private var hookStatuses: [SessionSource: Bool] = [:]
    @State private var autoRepairEnabled: Bool = AppSettings.autoRepairHooks

    private let managedSources: [SessionSource] = [
        .claude, .cline, .codexCLI, .gemini, .cursor, .windsurf, .kimiCLI, .kiroCLI,
        .ampCLI, .opencode, .copilot, .pi, .crush,
        .qoder, .droid, .codebuddy
    ]

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text(String(localized: "hooks.title"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()

                Button {
                    HookRepairManager.shared.repairAllNow()
                    refreshStatuses()
                } label: {
                    Text(String(localized: "hooks.repair_all"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            ForEach(managedSources, id: \.rawValue) { source in
                HookSourceRow(
                    source: source,
                    isEnabled: AppSettings.isHookEnabled(for: source),
                    isInstalled: hookStatuses[source] ?? false
                ) {
                    let currentlyEnabled = AppSettings.isHookEnabled(for: source)
                    if currentlyEnabled {
                        // User is disabling — uninstall the hook
                        HookInstaller.uninstallSource(source)
                    } else {
                        // User is enabling — install the hook
                        HookInstaller.installSource(source)
                    }
                    refreshStatuses()
                }
            }

            // Auto-repair toggle
            MenuToggleRow(
                icon: "wrench.and.screwdriver",
                label: String(localized: "settings.hooks.auto_repair"),
                isOn: autoRepairEnabled
            ) {
                autoRepairEnabled.toggle()
                AppSettings.autoRepairHooks = autoRepairEnabled
                HookRepairManager.shared.restart()
            }
        }
        .onAppear { refreshStatuses() }
    }

    private func refreshStatuses() {
        hookStatuses = HookInstaller.allStatuses()
        autoRepairEnabled = AppSettings.autoRepairHooks
    }
}

// MARK: - Hook Source Row

struct HookSourceRow: View {
    let source: SessionSource
    let isEnabled: Bool
    let isInstalled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(source.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.7))

                Spacer()

                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var statusColor: Color {
        if !isEnabled { return .white.opacity(0.3) }
        return isInstalled ? TerminalColors.green : Color(red: 1.0, green: 0.4, blue: 0.4)
    }

    private var statusText: String {
        if !isEnabled { return String(localized: "hooks.status.disabled") }
        return isInstalled ? String(localized: "hooks.status.active") : String(localized: "hooks.status.not_installed")
    }
}

// MARK: - Update Row

struct UpdateRow: View {
    @ObservedObject var updateManager: UpdateManager
    @State private var isHovered = false
    @State private var isSpinning = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    var body: some View {
        Button {
            handleTap()
        } label: {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    if case .installing = updateManager.state {
                        Image(systemName: "gear")
                            .font(.system(size: 12))
                            .foregroundColor(TerminalColors.blue)
                            .rotationEffect(.degrees(isSpinning ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isSpinning)
                            .onAppear { isSpinning = true }
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(iconColor)
                    }
                }
                .frame(width: 16)

                // Label
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(labelColor)

                Spacer()

                // Right side: progress or status
                rightContent
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered && isInteractive ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.2), value: updateManager.state)
    }

    // MARK: - Right Content

    @ViewBuilder
    private var rightContent: some View {
        switch updateManager.state {
        case .idle:
            Text(appVersion)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))

        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(TerminalColors.green)
                Text(String(localized: "update.up_to_date"))
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .checking, .installing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)

        case .found(let version, _):
            HStack(spacing: 6) {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)
                Text("v\(version)")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .tint(TerminalColors.blue)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.blue)
                    .frame(width: 32, alignment: .trailing)
            }

        case .extracting(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(width: 60)
                    .tint(TerminalColors.amber)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.amber)
                    .frame(width: 32, alignment: .trailing)
            }

        case .readyToInstall(let version):
            HStack(spacing: 6) {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)
                Text("v\(version)")
                    .font(.system(size: 11))
                    .foregroundColor(TerminalColors.green)
            }

        case .error:
            Text(String(localized: "update.retry"))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Computed Properties

    private var icon: String {
        switch updateManager.state {
        case .idle:
            return "arrow.down.circle"
        case .checking:
            return "arrow.down.circle"
        case .upToDate:
            return "checkmark.circle.fill"
        case .found:
            return "arrow.down.circle.fill"
        case .downloading:
            return "arrow.down.circle"
        case .extracting:
            return "doc.zipper"
        case .readyToInstall:
            return "checkmark.circle.fill"
        case .installing:
            return "gear"
        case .error:
            return "exclamationmark.circle"
        }
    }

    private var iconColor: Color {
        switch updateManager.state {
        case .idle:
            return .white.opacity(isHovered ? 1.0 : 0.7)
        case .checking:
            return .white.opacity(0.7)
        case .upToDate:
            return TerminalColors.green
        case .found, .readyToInstall:
            return TerminalColors.green
        case .downloading:
            return TerminalColors.blue
        case .extracting:
            return TerminalColors.amber
        case .installing:
            return TerminalColors.blue
        case .error:
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }

    private var label: String {
        switch updateManager.state {
        case .idle:
            return String(localized: "menu.check_updates")
        case .checking:
            return String(localized: "update.checking")
        case .upToDate:
            return String(localized: "menu.check_updates")
        case .found:
            return String(localized: "update.download")
        case .downloading:
            return String(localized: "update.downloading")
        case .extracting:
            return String(localized: "update.extracting")
        case .readyToInstall:
            return String(localized: "update.install_relaunch")
        case .installing:
            return String(localized: "update.installing")
        case .error:
            return String(localized: "update.failed")
        }
    }

    private var labelColor: Color {
        switch updateManager.state {
        case .idle, .upToDate:
            return .white.opacity(isHovered ? 1.0 : 0.7)
        case .checking, .downloading, .extracting, .installing:
            return .white.opacity(0.9)
        case .found, .readyToInstall:
            return TerminalColors.green
        case .error:
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }

    private var isInteractive: Bool {
        switch updateManager.state {
        case .idle, .upToDate, .found, .readyToInstall, .error:
            return true
        case .checking, .downloading, .extracting, .installing:
            return false
        }
    }

    // MARK: - Actions

    private func handleTap() {
        switch updateManager.state {
        case .idle, .upToDate, .error:
            updateManager.checkForUpdates()
        case .found:
            updateManager.downloadAndInstall()
        case .readyToInstall:
            updateManager.installAndRelaunch()
        default:
            break
        }
    }
}

// MARK: - Accessibility Permission Row

struct AccessibilityRow: View {
    let isEnabled: Bool

    @State private var isHovered = false
    @State private var refreshTrigger = false

    private var currentlyEnabled: Bool {
        // Re-check on each render when refreshTrigger changes
        _ = refreshTrigger
        return isEnabled
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)

            Text(String(localized: "menu.accessibility"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)

            Spacer()

            if isEnabled {
                Circle()
                    .fill(TerminalColors.green)
                    .frame(width: 6, height: 6)

                Text(String(localized: "menu.accessibility.on"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Button(action: openAccessibilitySettings) {
                    Text(String(localized: "menu.accessibility.enable"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshTrigger.toggle()
        }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct MenuRow: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        if isDestructive {
            return Color(red: 1.0, green: 0.4, blue: 0.4)
        }
        return .white.opacity(isHovered ? 1.0 : 0.7)
    }
}

struct MenuToggleRow: View {
    let icon: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)

                Spacer()

                Circle()
                    .fill(isOn ? TerminalColors.green : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)

                Text(isOn ? String(localized: "general.on") : String(localized: "general.off"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(isHovered ? 1.0 : 0.7)
    }
}
