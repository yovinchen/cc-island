//
//  QuotaViews.swift
//  ClaudeIsland
//

import AppKit
import SwiftUI

struct QuotaSettingsPane: View {
    private struct SessionImportFeedback {
        let message: String
        let color: Color
    }

    private struct CopilotAuthorizationContext {
        let userCode: String
        let verificationURI: String
        let expiresAt: Date
    }

    @ObservedObject private var quotaStore = QuotaStore.shared

    @State private var selectedProviderID: QuotaProviderID = .codex
    @State private var secretValue = ""
    @State private var loadedSecretProviderID: QuotaProviderID?
    @State private var openCodeWorkspaceID = ""
    @State private var sourcePreference: QuotaSourcePreference = .auto
    @State private var cliBinaryPath = ""
    @State private var importingSessionProviderID: QuotaProviderID?
    @State private var sessionImportFeedback: SessionImportFeedback?
    @State private var authenticatingCopilot = false
    @State private var copilotLoginFeedback: SessionImportFeedback?
    @State private var copilotAuthorizationContext: CopilotAuthorizationContext?
    @State private var copilotLoginTask: Task<Void, Never>?

    private var selectedRecord: QuotaProviderRecord? {
        quotaStore.record(for: selectedProviderID) ?? quotaStore.orderedRecords.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(String(localized: "settings.usage.detail"))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                if let refreshedAt = quotaStore.lastGlobalRefreshAt {
                    Text(relativeText(for: refreshedAt))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                }

                Button(String(localized: "quota.refresh_all")) {
                    quotaStore.userVisibleRefresh()
                }
                .buttonStyle(SettingsButtonStyle())
            }

            HStack(alignment: .top, spacing: 24) {
                providerListPanel
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)

                providerDetailPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            quotaStore.refreshIfNeeded(maxAge: 60)
            ensureSelection()
            loadSecretIfNeeded(force: true)
            loadProviderPreferences()
        }
        .onChange(of: selectedProviderID) { _, _ in
            loadSecretIfNeeded(force: true)
            loadProviderPreferences()
            sessionImportFeedback = nil
            copilotLoginFeedback = nil
            if selectedProviderID != .copilot {
                cancelCopilotAuthentication()
                copilotAuthorizationContext = nil
            }
        }
        .onChange(of: quotaStore.orderedRecords.map(\.id)) { _, _ in
            ensureSelection()
            loadSecretIfNeeded(force: false)
        }
    }

    private var providerListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "settings.tab.usage"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))

                Spacer()

                Text("\(quotaStore.orderedRecords.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Divider()
                .background(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(quotaStore.orderedRecords) { record in
                        providerListRow(for: record)
                    }
                }
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var providerDetailPanel: some View {
        if let record = selectedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top, spacing: 14) {
                        QuotaProviderBrandIcon(providerID: record.id, size: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.displayName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            Text(providerHeaderSubtitle(for: record))
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.45))
                        }

                        Spacer()

                        HStack(spacing: 12) {
                            Button {
                                quotaStore.userVisibleRefresh(providerID: record.id)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .buttonStyle(SettingsButtonStyle())

                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { record.isEnabled },
                                    set: { quotaStore.setEnabled($0, for: record.id) }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(TerminalColors.blue)
                        }
                    }

                    providerFactsSection(for: record)
                    providerUsageSection(for: record)

                    if let credits = record.snapshot?.credits {
                        quotaTextBlock(title: credits.label, text: creditsSummaryText(credits), color: .white.opacity(0.75))
                    }

                    if let note = record.snapshot?.note, !note.isEmpty {
                        quotaTextBlock(title: String(localized: "quota.notes"), text: note, color: .white.opacity(0.7))
                    }

                    if let error = record.latestErrorText, !error.isEmpty {
                        quotaTextBlock(title: String(localized: "quota.last_error"), text: error, color: TerminalColors.red)
                    }

                    providerSettingsSection(for: record)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
            }
        } else {
            Text(String(localized: "quota.select_provider"))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func providerListRow(for record: QuotaProviderRecord) -> some View {
        let isSelected = record.id == selectedProviderID

        return HStack(alignment: .top, spacing: 12) {
            ProviderGripHandle()
                .padding(.top, 12)

            QuotaProviderBrandIcon(providerID: record.id, size: 18)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(record.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))

                    Circle()
                        .fill(color(for: record.status))
                        .frame(width: 10, height: 10)
                }

                Text(providerRowPrimaryText(for: record))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))

                Text(providerRowSecondaryText(for: record))
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.54))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Toggle(
                "",
                isOn: Binding(
                    get: { record.isEnabled },
                    set: { quotaStore.setEnabled($0, for: record.id) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(TerminalColors.blue)
            .padding(.top, 7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    isSelected
                    ? LinearGradient(
                        colors: [
                            TerminalColors.blue.opacity(0.95),
                            Color(red: 0.07, green: 0.36, blue: 0.86),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.02),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.04), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture {
            selectedProviderID = record.id
        }
    }

    private func providerFactsSection(for record: QuotaProviderRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "quota.overview"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))

            VStack(alignment: .leading, spacing: 10) {
                QuotaInfoRow(label: String(localized: "quota.info.state"), value: record.statusText)
                QuotaInfoRow(label: String(localized: "quota.info.source"), value: record.effectiveSourceLabel)
                QuotaInfoRow(label: String(localized: "quota.info.updated"), value: providerUpdatedText(for: record))
                QuotaInfoRow(label: String(localized: "quota.info.account"), value: record.accountText ?? String(localized: "quota.unknown"))
                if let organization = record.organizationText {
                    QuotaInfoRow(label: String(localized: "quota.info.organization"), value: organization)
                }
                if let plan = record.planText {
                    QuotaInfoRow(label: String(localized: "quota.info.plan"), value: plan)
                }
                if let detail = record.detailText {
                    QuotaInfoRow(label: String(localized: "quota.info.detail"), value: detail)
                }
                QuotaInfoRow(label: String(localized: "quota.info.version"), value: providerDetectionText(for: record))
                QuotaInfoRow(label: String(localized: "quota.info.status"), value: providerServiceStatusText(for: record))
            }
        }
    }

    private func providerUsageSection(for record: QuotaProviderRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "quota.usage"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))

            let windows = providerUsageRows(for: record)
            if windows.isEmpty {
                Text(String(localized: "quota.no_usage"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                        ProviderUsageRow(window: window)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func providerSettingsSection(for record: QuotaProviderRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "quota.configuration"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))

            if record.supportsSourceSelection {
                providerSettingsBlock(title: String(localized: "quota.source_mode"), caption: String(localized: "quota.source_mode_hint")) {
                    Picker(
                        String(localized: "quota.source_mode"),
                        selection: Binding(
                            get: { sourcePreference },
                            set: { newValue in
                                sourcePreference = newValue
                                QuotaPreferences.setSourcePreference(newValue, for: record.id)
                                quotaStore.userVisibleRefresh(providerID: record.id)
                            }
                        )
                    ) {
                        ForEach(sourceOptions(for: record), id: \.id) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }

            providerSettingsBlock(
                title: String(localized: "quota.session_rings"),
                caption: String(localized: "settings.usage.show_desc")
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { AppSettings.showUsageData },
                        set: { AppSettings.showUsageData = $0 }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(TerminalColors.blue)
            }

            if let cliBinaryName = record.descriptor.cliBinaryName {
                providerSettingsBlock(
                    title: String(localized: "quota.cli_binary"),
                    caption: String(format: String(localized: "quota.cli_binary_hint %@"), cliBinaryName)
                ) {
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: 10) {
                    TextField(String(localized: "quota.cli_binary_placeholder"), text: $cliBinaryPath)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                        .foregroundColor(.white.opacity(0.9))

                    HStack(spacing: 10) {
                        Button(String(localized: "quota.save_cli_path")) {
                            QuotaPreferences.setCLIBinaryPath(
                                cliBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: record.id
                            )
                            quotaStore.userVisibleRefresh(providerID: record.id)
                        }
                        .buttonStyle(SettingsButtonStyle())

                        Button(String(localized: "quota.clear_cli_path")) {
                            cliBinaryPath = ""
                            QuotaPreferences.setCLIBinaryPath("", for: record.id)
                            quotaStore.userVisibleRefresh(providerID: record.id)
                        }
                        .buttonStyle(SettingsButtonStyle(isDestructive: true))
                    }
                }
            }

            if record.descriptor.supportsManualSecret {
                providerSettingsBlock(title: String(localized: "quota.credential"), caption: record.descriptor.credentialHint) {
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SecureField(record.credentialPlaceholder, text: $secretValue)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                        .foregroundColor(.white.opacity(0.9))

                    HStack(spacing: 10) {
                        Button(String(localized: "quota.save_key")) {
                            quotaStore.saveSecret(secretValue, for: record.id)
                            quotaStore.userVisibleRefresh(providerID: record.id)
                        }
                        .buttonStyle(SettingsButtonStyle())

                        Button(String(localized: "quota.clear_key")) {
                            secretValue = ""
                            quotaStore.saveSecret("", for: record.id)
                            quotaStore.userVisibleRefresh(providerID: record.id)
                        }
                        .buttonStyle(SettingsButtonStyle(isDestructive: true))
                    }
                }
            } else {
                providerSettingsBlock(title: String(localized: "quota.setup"), caption: record.descriptor.credentialHint) {
                    EmptyView()
                }
            }

            if record.id == .copilot {
                providerSettingsBlock(
                    title: String(localized: "quota.copilot_sign_in"),
                    caption: String(localized: "quota.copilot_sign_in_hint")
                ) {
                    if authenticatingCopilot {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)

                            Button(String(localized: "quota.copilot_sign_in_cancel")) {
                                cancelCopilotAuthentication()
                            }
                            .buttonStyle(SettingsButtonStyle(isDestructive: true))
                        }
                    } else {
                        Button(quotaStore.storedSecret(for: .copilot).isEmpty
                               ? String(localized: "quota.copilot_sign_in_action")
                               : String(localized: "quota.copilot_sign_in_reauth")) {
                            Task { await authenticateCopilot() }
                        }
                        .buttonStyle(SettingsButtonStyle())
                    }
                }

                if let copilotAuthorizationContext {
                    VStack(alignment: .leading, spacing: 10) {
                        quotaTextBlock(
                            title: String(localized: "quota.copilot_sign_in_code"),
                            text: copilotAuthorizationContext.userCode,
                            color: .white.opacity(0.82)
                        )

                        Text(
                            String(
                                format: String(localized: "quota.copilot_sign_in_expires %@"),
                                relativeText(for: copilotAuthorizationContext.expiresAt)
                            )
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))

                        HStack(spacing: 10) {
                            Button(String(localized: "quota.copilot_sign_in_copy_code")) {
                                copyCopilotUserCode(copilotAuthorizationContext.userCode)
                            }
                            .buttonStyle(SettingsButtonStyle())

                            Button(String(localized: "quota.copilot_sign_in_open_browser")) {
                                openCopilotVerificationURL(copilotAuthorizationContext.verificationURI)
                            }
                            .buttonStyle(SettingsButtonStyle())
                        }
                    }
                }

                if let copilotLoginFeedback {
                    Text(copilotLoginFeedback.message)
                        .font(.system(size: 12))
                        .foregroundColor(copilotLoginFeedback.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if QuotaWebSessionImportRunner.supports(providerID: record.id) {
                providerSettingsBlock(
                    title: String(localized: "quota.import_session"),
                    caption: String(localized: "quota.import_session_hint")
                ) {
                    if importingSessionProviderID == record.id {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(String(localized: "quota.import_session")) {
                            Task { await importSession(for: record.id) }
                        }
                        .buttonStyle(SettingsButtonStyle())
                    }
                }

                if let sessionImportFeedback {
                    Text(sessionImportFeedback.message)
                        .font(.system(size: 12))
                        .foregroundColor(sessionImportFeedback.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if record.id == .opencode {
                providerSettingsBlock(
                    title: String(localized: "quota.opencode_workspace"),
                    caption: String(localized: "quota.opencode_workspace_hint")
                ) {
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: 10) {
                    TextField(String(localized: "quota.opencode_workspace_placeholder"), text: $openCodeWorkspaceID)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.06))
                        )
                        .foregroundColor(.white.opacity(0.9))

                    HStack(spacing: 10) {
                        Button(String(localized: "quota.save_workspace")) {
                            QuotaPreferences.openCodeWorkspaceID = openCodeWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
                            quotaStore.userVisibleRefresh(providerID: record.id)
                        }
                        .buttonStyle(SettingsButtonStyle())

                        Button(String(localized: "quota.clear_workspace")) {
                            openCodeWorkspaceID = ""
                            QuotaPreferences.openCodeWorkspaceID = ""
                            quotaStore.userVisibleRefresh(providerID: record.id)
                        }
                        .buttonStyle(SettingsButtonStyle(isDestructive: true))
                    }
                }
            }

            if record.id == .zai {
                providerSettingsBlock(title: String(localized: "quota.zai_region"), caption: String(localized: "quota.zai_region_hint")) {
                    Picker(
                        String(localized: "quota.zai_region"),
                        selection: Binding(
                            get: { QuotaPreferences.zaiRegion },
                            set: { newValue in
                                QuotaPreferences.zaiRegion = newValue
                                quotaStore.userVisibleRefresh(providerID: record.id)
                            }
                        )
                    ) {
                        ForEach(QuotaZAIRegion.allCases, id: \.rawValue) { region in
                            Text(region.displayName).tag(region)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
            }

            HStack(spacing: 10) {
                if let dashboardURL = record.dashboardURL, let url = URL(string: dashboardURL) {
                    Button(String(localized: "quota.open_dashboard")) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(SettingsButtonStyle())
                }

                if let statusURL = record.statusURL, let url = URL(string: statusURL) {
                    Button(String(localized: "quota.open_status")) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(SettingsButtonStyle())
                }
            }
        }
    }

    private func providerSettingsBlock<Content: View>(title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))

                Spacer()

                content()
            }

            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func quotaTextBlock(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private func providerUsageRows(for record: QuotaProviderRecord) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        if let primary = record.snapshot?.primaryWindow {
            windows.append(primary)
        }
        if let secondary = record.snapshot?.secondaryWindow {
            windows.append(secondary)
        }
        if let tertiary = record.snapshot?.tertiaryWindow {
            windows.append(tertiary)
        }
        return windows
    }

    private func providerHeaderSubtitle(for record: QuotaProviderRecord) -> String {
        "\(record.effectiveSourceLabel.lowercased()) • \(providerUpdatedText(for: record))"
    }

    private func providerUpdatedText(for record: QuotaProviderRecord) -> String {
        if let updatedAt = record.snapshot?.updatedAt ?? record.diagnostics.lastSuccessAt {
            return relativeText(for: updatedAt)
        }
        return String(localized: "quota.never_updated")
    }

    private func providerDetectionText(for record: QuotaProviderRecord) -> String {
        switch record.id {
        case .cursor:
            if let binary = QuotaRuntimeSupport.which("cursor"),
               let version = QuotaRuntimeSupport.detectProviderVersion(providerID: .cursor, binaryPath: binary)
            {
                return version
            }
            if let version = QuotaRuntimeSupport.appBundleVersion(appName: "Cursor") {
                return version
            }
            return String(localized: "quota.not_detected")
        case .opencode:
            if let binary = QuotaRuntimeSupport.which("opencode"),
               let version = QuotaRuntimeSupport.detectProviderVersion(providerID: .opencode, binaryPath: binary)
            {
                return version
            }
            if let binary = QuotaRuntimeSupport.which("opencode"),
               let version = QuotaRuntimeSupport.nodePackageVersionNearBinary(binaryPath: binary, packageDirectoryName: "opencode-ai")
            {
                return version
            }
            return String(localized: "quota.not_detected")
        case .amp:
            if let binary = QuotaRuntimeSupport.which("amp"),
               let version = QuotaRuntimeSupport.detectProviderVersion(providerID: .amp, binaryPath: binary)
            {
                return version
            }
            if QuotaRuntimeSupport.which("amp") != nil {
                return String(localized: "quota.detected")
            }
            return String(localized: "quota.not_detected")
        case .jetbrains:
            return JetBrainsIDEDetector.detectLatestIDE()?.displayName ?? String(localized: "quota.not_detected")
        case .warp:
            return QuotaRuntimeSupport.appBundleVersion(appName: "Warp") ?? String(localized: "quota.not_detected")
        default:
            break
        }

        if let cliBinaryName = record.descriptor.cliBinaryName {
            if let resolved = QuotaRuntimeSupport.resolvedBinary(defaultBinary: cliBinaryName, providerID: record.id) {
                if let version = QuotaRuntimeSupport.detectProviderVersion(providerID: record.id, binaryPath: resolved) {
                    return version
                }
                return String(localized: "quota.detected")
            }
            return String(localized: "quota.not_detected")
        }

        if record.descriptor.supportsManualSecret {
            return quotaStore.storedSecret(for: record.id).isEmpty
                ? String(localized: "quota.not_detected")
                : String(localized: "quota.detected_manual")
        }

        if record.isConfigured {
            return String(localized: "quota.detected")
        }
        return String(localized: "quota.not_detected")
    }

    private func providerServiceStatusText(for record: QuotaProviderRecord) -> String {
        record.statusURL == nil
            ? String(localized: "quota.status.inline")
            : String(localized: "quota.status.page_available")
    }

    private func providerRowPrimaryText(for record: QuotaProviderRecord) -> String {
        if record.isEnabled {
            return record.effectiveSourceLabel.lowercased()
        }
        return "\(String(localized: "quota.disabled")) — \(record.effectiveSourceLabel.lowercased())"
    }

    private func providerRowSecondaryText(for record: QuotaProviderRecord) -> String {
        if let error = record.latestErrorText, !error.isEmpty {
            return error
        }
        if record.snapshot != nil {
            return "\(record.summaryLine) • \(providerUpdatedText(for: record))"
        }
        if record.status == .needsConfiguration {
            return String(localized: "quota.needs_configuration")
        }
        if record.status == .stale {
            return String(localized: "quota.last_fetch_failed")
        }
        return String(localized: "quota.no_usage")
    }

    private func creditsSummaryText(_ credits: QuotaCredits) -> String {
        if credits.isUnlimited {
            return String(localized: "quota.unlimited")
        }
        if let used = credits.used, let total = credits.total, total > 0 {
            if let remaining = credits.remaining {
                return String(format: "%.2f / %.2f • %.2f left", used, total, remaining)
            }
            return String(format: "%.2f / %.2f", used, total)
        }
        if let remaining = credits.remaining {
            if credits.currencyCode == "USD" {
                return String(format: String(localized: "quota.remaining_usd"), remaining)
            }
            return String(format: String(localized: "quota.remaining_generic"), remaining)
        }
        return String(localized: "quota.unknown")
    }

    private func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func color(for status: QuotaProviderStatus) -> Color {
        switch status {
        case .connected:
            return TerminalColors.green
        case .needsConfiguration:
            return TerminalColors.blue
        case .refreshing:
            return TerminalColors.cyan
        case .stale:
            return TerminalColors.amber
        case .error:
            return TerminalColors.red
        }
    }

    private func ensureSelection() {
        if quotaStore.record(for: selectedProviderID) != nil {
            return
        }
        selectedProviderID = quotaStore.orderedRecords.first?.id ?? .codex
    }

    private func loadSecretIfNeeded(force: Bool) {
        guard let selectedRecord else { return }
        if !selectedRecord.descriptor.supportsManualSecret {
            secretValue = ""
            loadedSecretProviderID = selectedRecord.id
            return
        }

        if !force, loadedSecretProviderID == selectedRecord.id {
            return
        }
        secretValue = quotaStore.storedSecret(for: selectedRecord.id)
        loadedSecretProviderID = selectedRecord.id
    }

    private func loadProviderPreferences() {
        sourcePreference = QuotaPreferences.sourcePreference(for: selectedProviderID)
        cliBinaryPath = QuotaPreferences.cliBinaryPath(for: selectedProviderID)

        if selectedProviderID == .opencode {
            openCodeWorkspaceID = QuotaPreferences.openCodeWorkspaceID
        } else {
            openCodeWorkspaceID = ""
        }
    }

    private func sourceOptions(for record: QuotaProviderRecord) -> [QuotaSourcePreference] {
        var options = record.descriptor.supportedSources.map { QuotaSourcePreference.from(sourceKind: $0) }
        if record.supportsSourceSelection {
            options.insert(.auto, at: 0)
        }
        return options
    }

    @MainActor
    private func importSession(for providerID: QuotaProviderID) async {
        importingSessionProviderID = providerID
        defer { importingSessionProviderID = nil }

        let result = await QuotaWebSessionImportRunner.run(providerID: providerID)
        switch result {
        case .success:
            loadSecretIfNeeded(force: true)
            quotaStore.userVisibleRefresh(providerID: providerID)
            sessionImportFeedback = SessionImportFeedback(
                message: String(localized: "quota.import_session_success"),
                color: TerminalColors.green
            )
        case .cancelled:
            sessionImportFeedback = SessionImportFeedback(
                message: String(localized: "quota.import_session_cancelled"),
                color: .white.opacity(0.5)
            )
        case .failed(let message):
            sessionImportFeedback = SessionImportFeedback(
                message: String(format: String(localized: "quota.import_session_failed %@"), message),
                color: TerminalColors.red
            )
        case .unsupported:
            sessionImportFeedback = SessionImportFeedback(
                message: String(localized: "quota.import_session_unsupported"),
                color: TerminalColors.red
            )
        }
    }

    @MainActor
    private func authenticateCopilot() async {
        guard !authenticatingCopilot else { return }
        authenticatingCopilot = true
        copilotLoginFeedback = nil
        copilotAuthorizationContext = nil
        defer {
            authenticatingCopilot = false
            copilotLoginTask = nil
        }

        let flow = CopilotDeviceFlow()

        do {
            let code = try await flow.requestDeviceCode()
            let authorizationContext = CopilotAuthorizationContext(
                userCode: code.userCode,
                verificationURI: code.verificationUri,
                expiresAt: Date().addingTimeInterval(TimeInterval(code.expiresIn))
            )
            copyCopilotUserCode(code.userCode)
            openCopilotVerificationURL(code.verificationUri)
            copilotAuthorizationContext = authorizationContext

            copilotLoginFeedback = SessionImportFeedback(
                message: String(localized: "quota.copilot_sign_in_waiting"),
                color: .white.opacity(0.7)
            )

            let task = Task {
                do {
                    let token = try await flow.pollForToken(deviceCode: code.deviceCode, interval: code.interval)
                    await MainActor.run {
                        secretValue = token
                        quotaStore.saveSecret(token, for: .copilot)
                        loadSecretIfNeeded(force: true)
                        quotaStore.userVisibleRefresh(providerID: .copilot)
                        copilotAuthorizationContext = nil
                        copilotLoginFeedback = SessionImportFeedback(
                            message: String(localized: "quota.copilot_sign_in_success"),
                            color: TerminalColors.green
                        )
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        copilotLoginFeedback = SessionImportFeedback(
                            message: String(localized: "quota.copilot_sign_in_cancelled"),
                            color: .white.opacity(0.5)
                        )
                    }
                } catch {
                    await MainActor.run {
                        copilotLoginFeedback = SessionImportFeedback(
                            message: String(
                                format: String(localized: "quota.copilot_sign_in_failed %@"),
                                error.localizedDescription
                            ),
                            color: TerminalColors.red
                        )
                    }
                }
            }
            copilotLoginTask = task
            await task.value
        } catch is CancellationError {
            copilotLoginFeedback = SessionImportFeedback(
                message: String(localized: "quota.copilot_sign_in_cancelled"),
                color: .white.opacity(0.5)
            )
        } catch {
            copilotLoginFeedback = SessionImportFeedback(
                message: String(
                    format: String(localized: "quota.copilot_sign_in_failed %@"),
                    error.localizedDescription
                ),
                color: TerminalColors.red
            )
        }
    }

    @MainActor
    private func cancelCopilotAuthentication() {
        copilotLoginTask?.cancel()
    }

    @MainActor
    private func copyCopilotUserCode(_ userCode: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(userCode, forType: .string)
    }

    @MainActor
    private func openCopilotVerificationURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct QuotaPanelView: View {
    @ObservedObject private var quotaStore = QuotaStore.shared
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "quota.title"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Button(String(localized: "quota.refresh")) {
                        quotaStore.userVisibleRefresh()
                    }
                    .buttonStyle(SettingsButtonStyle())

                    Button(String(localized: "quota.open_settings")) {
                        SettingsWindowController.show()
                    }
                    .buttonStyle(SettingsButtonStyle())
                }

                if quotaStore.orderedRecords.isEmpty {
                    Text(String(localized: "quota.no_providers"))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                } else {
                    ForEach(quotaStore.orderedRecords) { record in
                        QuotaCompactCard(record: record)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .onAppear {
            quotaStore.refreshIfNeeded(maxAge: 60)
        }
    }
}

struct QuotaHeaderDisplay: View {
    @ObservedObject var quotaStore: QuotaStore

    var body: some View {
        let records = quotaStore.headerRecords(limit: 3)
        if !records.isEmpty {
            HStack(spacing: 4) {
                ForEach(records) { record in
                    Text("\(record.id.shortName) \(Int(record.displayRiskScore * 100))%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(chipColor(for: record).opacity(0.22))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func chipColor(for record: QuotaProviderRecord) -> Color {
        if record.displayRiskScore >= 0.9 {
            return TerminalColors.red
        }
        if record.displayRiskScore >= 0.7 {
            return TerminalColors.amber
        }
        return TerminalColors.green
    }
}

private struct QuotaOverviewCard: View {
    let record: QuotaProviderRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                QuotaStatusPill(status: record.status)
            }

            QuotaProgressBar(progress: record.displayRiskScore)

            Text(record.summaryLine)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct QuotaCompactCard: View {
    let record: QuotaProviderRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(record.displayName, systemImage: record.id.systemImageName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))

                Spacer()

                QuotaStatusPill(status: record.status)
            }

            if let primary = record.snapshot?.primaryWindow {
                QuotaWindowCard(window: primary)
            }

            if let secondary = record.snapshot?.secondaryWindow {
                QuotaWindowCard(window: secondary)
            }

            if let tertiary = record.snapshot?.tertiaryWindow {
                QuotaWindowCard(window: tertiary)
            }

            if let credits = record.snapshot?.credits {
                QuotaCreditsCard(credits: credits)
            }

            if let note = record.snapshot?.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct QuotaProviderBrandIcon: View {
    let providerID: QuotaProviderID
    let size: CGFloat

    var body: some View {
        Group {
            if let source = mappedSource {
                SourceIcon(source: source, size: size)
            } else {
                Image(systemName: providerID.systemImageName)
                    .font(.system(size: size * 0.82, weight: .medium))
                    .foregroundColor(.white.opacity(0.78))
                    .frame(width: size, height: size)
            }
        }
    }

    private var mappedSource: SessionSource? {
        switch providerID {
        case .codex:
            return .codexCLI
        case .claude:
            return .claude
        case .gemini:
            return .gemini
        case .copilot:
            return .copilot
        case .cursor:
            return .cursor
        case .opencode:
            return .opencode
        case .amp:
            return .ampCLI
        case .kimi:
            return .kimiCLI
        case .kiro:
            return .kiroCLI
        case .kimiK2:
            return .kimiCLI
        case .augment, .jetbrains, .openrouter, .warp, .zai:
            return nil
        }
    }
}

private struct ProviderGripHandle: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 3.5, height: 3.5)
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 3.5, height: 3.5)
                }
            }
        }
        .frame(width: 14, height: 20)
    }
}

private struct ProviderUsageRow: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 16) {
                Text(window.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 94, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    ProviderUsageProgressBar(progress: window.clampedUsedRatio)

                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(window.clampedUsedRatio * 100))% used")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.65))

                        Spacer()

                        if let resetsAt = window.resetsAt {
                            Text(String(format: String(localized: "quota.resets %@"), resetsAt.formatted(date: .abbreviated, time: .shortened)))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.52))
                        } else {
                            Text(String(localized: "quota.no_reset_detected"))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }

                    if let detail = window.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ProviderUsageProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [
                                TerminalColors.blue.opacity(0.95),
                                Color(red: 0.11, green: 0.46, blue: 0.96),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geometry.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 10)
    }
}

private struct QuotaWindowCard: View {
    let window: QuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(window.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))

                Spacer()

                Text("\(Int(window.clampedUsedRatio * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(progressColor)
            }

            QuotaProgressBar(progress: window.clampedUsedRatio)

            if let detail = window.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }

            if let resetsAt = window.resetsAt {
                Text(String(format: String(localized: "quota.resets %@"), QuotaRuntimeSupport.relativeResetDescription(for: resetsAt)))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
                }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var progressColor: Color {
        if window.clampedUsedRatio >= 0.9 {
            return TerminalColors.red
        }
        if window.clampedUsedRatio >= 0.7 {
            return TerminalColors.amber
        }
        return TerminalColors.green
    }
}

private struct QuotaCreditsCard: View {
    let credits: QuotaCredits

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(credits.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))

            if credits.isUnlimited {
                Text(String(localized: "quota.unlimited"))
                    .font(.system(size: 12))
                    .foregroundColor(TerminalColors.green)
            } else {
                if let used = credits.used, let total = credits.total, total > 0 {
                    QuotaProgressBar(progress: used / total)
                    Text(String(format: "%.2f / %.2f", used, total))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                }

                if let remaining = credits.remaining {
                    Text(credits.currencyCode == "USD"
                         ? String(format: String(localized: "quota.remaining_usd"), remaining)
                         : String(format: String(localized: "quota.remaining_generic"), remaining))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct QuotaProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 4)
                    .fill(progressColor)
                    .frame(width: max(6, geometry.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 8)
    }

    private var progressColor: Color {
        if progress >= 0.9 {
            return TerminalColors.red
        }
        if progress >= 0.7 {
            return TerminalColors.amber
        }
        return TerminalColors.green
    }
}

private struct QuotaStatusPill: View {
    let status: QuotaProviderStatus

    var body: some View {
        Text(statusText)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
    }

    private var statusText: String {
        switch status {
        case .connected:
            return String(localized: "quota.status.connected")
        case .needsConfiguration:
            return String(localized: "quota.status.setup")
        case .refreshing:
            return String(localized: "quota.status.refreshing")
        case .stale:
            return String(localized: "quota.status.stale")
        case .error:
            return String(localized: "quota.status.error")
        }
    }

    private var color: Color {
        switch status {
        case .connected:
            return TerminalColors.green
        case .needsConfiguration:
            return TerminalColors.blue
        case .refreshing:
            return TerminalColors.cyan
        case .stale:
            return TerminalColors.amber
        case .error:
            return TerminalColors.red
        }
    }
}

private struct QuotaInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 90, alignment: .leading)

            Text(value)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
