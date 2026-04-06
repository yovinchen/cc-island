//
//  QuotaViews.swift
//  ClaudeIsland
//

import AppKit
import SwiftUI

struct QuotaSettingsPane: View {
    @ObservedObject private var quotaStore = QuotaStore.shared

    @State private var selectedProviderID: QuotaProviderID = .codex
    @State private var secretValue = ""
    @State private var loadedSecretProviderID: QuotaProviderID?

    private var selectedRecord: QuotaProviderRecord? {
        quotaStore.record(for: selectedProviderID) ?? quotaStore.orderedRecords.first
    }

    private var headerRecords: [QuotaProviderRecord] {
        quotaStore.headerRecords(limit: 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SettingsToggle(
                    label: String(localized: "settings.usage.show_desc"),
                    getter: { AppSettings.showUsageData },
                    setter: { AppSettings.showUsageData = $0 }
                )

                Spacer()

                if let refreshedAt = quotaStore.lastGlobalRefreshAt {
                    Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                }

                Button("Refresh All") {
                    quotaStore.userVisibleRefresh()
                }
                .buttonStyle(SettingsButtonStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Overview")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))

                if headerRecords.isEmpty {
                    Text("No quota data yet. Use Refresh All after configuring a provider.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                } else {
                    HStack(spacing: 10) {
                        ForEach(headerRecords) { record in
                            QuotaOverviewCard(record: record)
                        }
                    }
                }
            }

            HSplitView {
                quotaSidebar
                    .frame(minWidth: 190, idealWidth: 210, maxWidth: 230)

                quotaDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            quotaStore.refreshIfNeeded(maxAge: 60)
            ensureSelection()
            loadSecretIfNeeded(force: true)
        }
        .onChange(of: selectedProviderID) { _, _ in
            loadSecretIfNeeded(force: true)
        }
        .onChange(of: quotaStore.orderedRecords.map(\.id)) { _, _ in
            ensureSelection()
            loadSecretIfNeeded(force: false)
        }
    }

    private var quotaSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(quotaStore.orderedRecords) { record in
                    Button {
                        selectedProviderID = record.id
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: record.descriptor.id.systemImageName)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 16, height: 16)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(record.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                    QuotaStatusPill(status: record.status)
                                }

                                Text(record.summaryLine)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.45))
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(record.id == selectedProviderID ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var quotaDetail: some View {
        if let record = selectedRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.displayName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                            Text(record.descriptor.credentialHint)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.45))
                        }

                        Spacer()

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { record.isEnabled },
                                set: { quotaStore.setEnabled($0, for: record.id) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(TerminalColors.green)
                    }

                    quotaInfoGrid(for: record)

                    if let primaryWindow = record.snapshot?.primaryWindow {
                        QuotaWindowCard(window: primaryWindow)
                    }

                    if let secondaryWindow = record.snapshot?.secondaryWindow {
                        QuotaWindowCard(window: secondaryWindow)
                    }

                    if let credits = record.snapshot?.credits {
                        QuotaCreditsCard(credits: credits)
                    }

                    if let note = record.snapshot?.note, !note.isEmpty {
                        quotaTextBlock(title: "Notes", text: note, color: .white.opacity(0.7))
                    }

                    if let error = record.latestErrorText, !error.isEmpty {
                        quotaTextBlock(title: "Last error", text: error, color: TerminalColors.red)
                    }

                    if record.descriptor.supportsManualSecret {
                        quotaSecretEditor(for: record)
                    } else {
                        quotaSetupGuide(for: record)
                    }

                    if record.id == .zai {
                        quotaZAIRegionPicker
                    }

                    quotaActions(for: record)
                }
                .padding(.trailing, 8)
            }
        } else {
            Text("Select a provider to view quota details.")
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func quotaInfoGrid(for record: QuotaProviderRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            QuotaInfoRow(label: "State", value: record.statusText)
            QuotaInfoRow(label: "Source", value: record.effectiveSourceLabel)
            QuotaInfoRow(label: "Updated", value: record.lastUpdatedText)
            QuotaInfoRow(label: "Account", value: record.accountText ?? "Unknown")
            if let organization = record.organizationText {
                QuotaInfoRow(label: "Organization", value: organization)
            }
            if let plan = record.planText {
                QuotaInfoRow(label: "Plan", value: plan)
            }
            if let detail = record.detailText {
                QuotaInfoRow(label: "Detail", value: detail)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func quotaSecretEditor(for record: QuotaProviderRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credential")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            SecureField(record.credentialPlaceholder, text: $secretValue)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))
                )
                .foregroundColor(.white.opacity(0.9))

            HStack(spacing: 10) {
                Button("Save Key") {
                    quotaStore.saveSecret(secretValue, for: record.id)
                    quotaStore.userVisibleRefresh()
                }
                .buttonStyle(SettingsButtonStyle())

                Button("Clear Key") {
                    secretValue = ""
                    quotaStore.saveSecret("", for: record.id)
                }
                .buttonStyle(SettingsButtonStyle(isDestructive: true))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func quotaSetupGuide(for record: QuotaProviderRecord) -> some View {
        quotaTextBlock(title: "Setup", text: record.descriptor.credentialHint, color: .white.opacity(0.7))
    }

    private var quotaZAIRegionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("z.ai region")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            Picker(
                "z.ai region",
                selection: Binding(
                    get: { QuotaPreferences.zaiRegion },
                    set: { newValue in
                        QuotaPreferences.zaiRegion = newValue
                        quotaStore.userVisibleRefresh()
                    }
                )
            ) {
                ForEach(QuotaZAIRegion.allCases, id: \.rawValue) { region in
                    Text(region.displayName).tag(region)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func quotaActions(for record: QuotaProviderRecord) -> some View {
        HStack(spacing: 10) {
            Button("Refresh") {
                quotaStore.userVisibleRefresh()
            }
            .buttonStyle(SettingsButtonStyle())

            if let dashboardURL = record.dashboardURL, let url = URL(string: dashboardURL) {
                Button("Open Dashboard") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(SettingsButtonStyle())
            }

            if let statusURL = record.statusURL, let url = URL(string: statusURL) {
                Button("Open Status") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(SettingsButtonStyle())
            }
        }
    }

    private func quotaTextBlock(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
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
}

struct QuotaPanelView: View {
    @ObservedObject private var quotaStore = QuotaStore.shared
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Quota")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Button("Refresh") {
                        quotaStore.userVisibleRefresh()
                    }
                    .buttonStyle(SettingsButtonStyle())

                    Button("Settings") {
                        SettingsWindowController.show()
                    }
                    .buttonStyle(SettingsButtonStyle())
                }

                if quotaStore.orderedRecords.isEmpty {
                    Text("No providers configured yet.")
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
                    Text("\(record.id.shortName) \(Int(record.primaryRiskScore * 100))%")
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
        if record.primaryRiskScore >= 0.9 {
            return TerminalColors.red
        }
        if record.primaryRiskScore >= 0.7 {
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

            QuotaProgressBar(progress: record.primaryRiskScore)

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
                Text("Resets \(QuotaRuntimeSupport.relativeResetDescription(for: resetsAt))")
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
                Text("Unlimited")
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
                    Text(credits.currencyCode == "USD" ? String(format: "$%.2f remaining", remaining) : String(format: "%.0f remaining", remaining))
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
            return "Connected"
        case .needsConfiguration:
            return "Setup"
        case .refreshing:
            return "Refreshing"
        case .stale:
            return "Stale"
        case .error:
            return "Error"
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
