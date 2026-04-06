//
//  QuotaStore.swift
//  ClaudeIsland
//

import Combine
import Foundation

@MainActor
final class QuotaStore: ObservableObject {
    static let shared = QuotaStore()

    @Published private(set) var records: [QuotaProviderID: QuotaProviderRecord]
    @Published private(set) var lastGlobalRefreshAt: Date?
    @Published private(set) var refreshInFlight = false

    private var refreshLoopTask: Task<Void, Never>?

    private init() {
        self.records = Dictionary(uniqueKeysWithValues: QuotaProviderRegistry.descriptors.map { descriptor in
            let enabled = Self.enabledValue(for: descriptor)
            let provider = QuotaProviderRegistry.provider(for: descriptor.id)
            let configured = provider?.isConfigured() ?? false
            let status: QuotaProviderStatus = if !configured {
                .needsConfiguration
            } else {
                .stale
            }

            return (
                descriptor.id,
                QuotaProviderRecord(
                    descriptor: descriptor,
                    isEnabled: enabled,
                    isConfigured: configured,
                    status: status,
                    snapshot: nil,
                    diagnostics: QuotaDiagnostics()
                )
            )
        })
    }

    func start() {
        guard refreshLoopTask == nil else { return }

        refreshLoopTask = Task { [weak self] in
            await self?.refreshAll()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { break }
                await self?.refreshAll()
            }
        }
    }

    func stop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
    }

    var orderedRecords: [QuotaProviderRecord] {
        records.values.sorted { lhs, rhs in
            if lhs.descriptor.sortPriority != rhs.descriptor.sortPriority {
                return lhs.descriptor.sortPriority < rhs.descriptor.sortPriority
            }
            return lhs.displayName < rhs.displayName
        }
    }

    func record(for providerID: QuotaProviderID) -> QuotaProviderRecord? {
        records[providerID]
    }

    func headerRecords(limit: Int = 3) -> [QuotaProviderRecord] {
        orderedRecords
            .filter { $0.snapshot != nil }
            .sorted { lhs, rhs in
                if lhs.primaryRiskScore != rhs.primaryRiskScore {
                    return lhs.primaryRiskScore > rhs.primaryRiskScore
                }
                if lhs.statusSortPriority != rhs.statusSortPriority {
                    return lhs.statusSortPriority < rhs.statusSortPriority
                }
                if lhs.descriptor.sortPriority != rhs.descriptor.sortPriority {
                    return lhs.descriptor.sortPriority < rhs.descriptor.sortPriority
                }
                return lhs.displayName < rhs.displayName
            }
            .prefix(limit)
            .map { $0 }
    }

    func setEnabled(_ enabled: Bool, for providerID: QuotaProviderID) {
        guard var record = records[providerID] else { return }
        record.isEnabled = enabled
        records[providerID] = record
        UserDefaults.standard.set(enabled, forKey: Self.enabledDefaultsKey(for: providerID))

        if enabled {
            Task { await refresh(providerID: providerID) }
        }
    }

    func storedSecret(for providerID: QuotaProviderID) -> String {
        QuotaSecretStore.read(account: QuotaProviderRegistry.secretAccountName(for: providerID)) ?? ""
    }

    func saveSecret(_ value: String, for providerID: QuotaProviderID) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = QuotaProviderRegistry.secretAccountName(for: providerID)

        if trimmed.isEmpty {
            QuotaSecretStore.delete(account: account)
        } else {
            QuotaSecretStore.save(trimmed, account: account)
        }

        rebuildConfigurationState(for: providerID)
    }

    func refreshAll() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }

        for providerID in QuotaProviderID.allCases {
            await refresh(providerID: providerID)
        }
        lastGlobalRefreshAt = Date()
    }

    func refreshIfNeeded(maxAge: TimeInterval = 60) {
        guard !refreshInFlight else { return }
        if let lastGlobalRefreshAt,
           Date().timeIntervalSince(lastGlobalRefreshAt) < maxAge
        {
            return
        }

        Task { await refreshAll() }
    }

    func userVisibleRefresh() {
        guard !refreshInFlight else { return }
        Task { await refreshAll() }
    }

    func refresh(providerID: QuotaProviderID) async {
        guard let provider = QuotaProviderRegistry.provider(for: providerID),
              var record = records[providerID]
        else {
            return
        }

        let configured = provider.isConfigured()
        record.isConfigured = configured
        record.diagnostics.lastRefreshAttemptAt = Date()

        guard record.isEnabled else {
            records[providerID] = record
            return
        }

        guard configured else {
            if record.snapshot == nil {
                record.status = .needsConfiguration
            } else {
                record.status = .stale
            }
            records[providerID] = record
            return
        }

        record.status = .refreshing
        records[providerID] = record

        do {
            let snapshot = try await provider.fetch()
            record.snapshot = snapshot
            record.status = .connected
            record.diagnostics.lastError = nil
            record.diagnostics.lastSuccessAt = snapshot.updatedAt
            record.diagnostics.sourceLabel = snapshot.source.rawValue
        } catch {
            record.status = record.snapshot == nil ? .error : .stale
            record.diagnostics.lastError = error.localizedDescription
        }

        records[providerID] = record
    }

    private func rebuildConfigurationState(for providerID: QuotaProviderID) {
        guard let provider = QuotaProviderRegistry.provider(for: providerID),
              var record = records[providerID]
        else {
            return
        }

        record.isConfigured = provider.isConfigured()
        if !record.isConfigured, record.snapshot == nil {
            record.status = .needsConfiguration
        }
        records[providerID] = record
    }

    private static func enabledDefaultsKey(for providerID: QuotaProviderID) -> String {
        "quota.enabled.\(providerID.rawValue)"
    }

    private static func enabledValue(for descriptor: QuotaProviderDescriptor) -> Bool {
        let key = enabledDefaultsKey(for: descriptor.id)
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return descriptor.defaultEnabled
        }
        return defaults.bool(forKey: key)
    }
}

#if DEBUG
extension QuotaStore {
    func _replaceRecordsForTesting(_ newRecords: [QuotaProviderRecord], lastGlobalRefreshAt: Date? = nil) {
        records = Dictionary(uniqueKeysWithValues: newRecords.map { ($0.id, $0) })
        self.lastGlobalRefreshAt = lastGlobalRefreshAt
    }
}
#endif
