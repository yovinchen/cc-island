import XCTest
@testable import Claude_Island

@MainActor
final class QuotaStoreTests: XCTestCase {
    func testHeaderRecordsOrdersByRiskDescending() {
        let store = QuotaStore.shared
        let low = makeRecord(id: .warp, risk: 0.2, status: .connected)
        let high = makeRecord(id: .openrouter, risk: 0.9, status: .connected)
        let medium = makeRecord(id: .zai, risk: 0.5, status: .connected)

        store._replaceRecordsForTesting([low, high, medium], lastGlobalRefreshAt: Date())

        let result = store.headerRecords(limit: 3)

        XCTAssertEqual(result.map(\.id), [.openrouter, .zai, .warp])
    }

    func testHeaderRecordsSkipsProvidersWithoutSnapshots() {
        let store = QuotaStore.shared
        let withSnapshot = makeRecord(id: .openrouter, risk: 0.4, status: .connected)
        let withoutSnapshot = QuotaProviderRecord(
            descriptor: QuotaProviderRegistry.descriptor(for: .codex),
            isEnabled: true,
            isConfigured: false,
            status: .needsConfiguration,
            snapshot: nil,
            diagnostics: QuotaDiagnostics()
        )

        store._replaceRecordsForTesting([withSnapshot, withoutSnapshot], lastGlobalRefreshAt: Date())

        let result = store.headerRecords(limit: 3)

        XCTAssertEqual(result.map(\.id), [.openrouter])
    }

    private func makeRecord(id: QuotaProviderID, risk: Double, status: QuotaProviderStatus) -> QuotaProviderRecord {
        QuotaProviderRecord(
            descriptor: QuotaProviderRegistry.descriptor(for: id),
            isEnabled: true,
            isConfigured: true,
            status: status,
            snapshot: QuotaSnapshot(
                providerID: id,
                source: .apiKey,
                primaryWindow: QuotaWindow(
                    label: "Primary",
                    usedRatio: risk,
                    detail: nil,
                    resetsAt: nil
                ),
                secondaryWindow: nil,
                credits: nil,
                identity: nil,
                updatedAt: Date(),
                note: nil
            ),
            diagnostics: QuotaDiagnostics()
        )
    }
}
