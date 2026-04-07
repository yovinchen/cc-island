import XCTest
@testable import Claude_Island

@MainActor
final class Wave2QuotaProviderTests: XCTestCase {
    func testCursorUsageSummaryDecodesPlanAndUsage() throws {
        let data = Data(
            """
            {
              "billingCycleEnd": "2026-05-01T00:00:00Z",
              "membershipType": "pro",
              "individualUsage": {
                "plan": {
                  "used": 1500,
                  "limit": 2000,
                  "autoPercentUsed": 30,
                  "apiPercentUsed": 20,
                  "totalPercentUsed": 25
                },
                "onDemand": {
                  "used": 200,
                  "limit": 500
                }
              }
            }
            """.utf8
        )

        let summary = try JSONDecoder().decode(CursorUsageSummary.self, from: data)

        XCTAssertEqual(summary.membershipType, "pro")
        XCTAssertEqual(summary.individualUsage?.plan?.totalPercentUsed ?? 0, 25, accuracy: 0.001)
        XCTAssertEqual(summary.individualUsage?.onDemand?.limit, 500)
    }

    func testCursorSnapshotTreatsFractionalPercentFieldsAsPercentageUnits() {
        let provider = CursorQuotaProvider()
        let snapshot = provider._test_snapshot(
            summary: CursorUsageSummary(
                billingCycleStart: "2026-03-18T20:45:42.000Z",
                billingCycleEnd: "2026-04-18T20:45:42.000Z",
                membershipType: "pro",
                limitType: "user",
                isUnlimited: false,
                autoModelSelectedDisplayMessage: nil,
                namedModelSelectedDisplayMessage: nil,
                individualUsage: CursorIndividualUsage(
                    plan: CursorPlanUsage(
                        enabled: true,
                        used: 86,
                        limit: 2000,
                        remaining: 1914,
                        breakdown: CursorPlanBreakdown(
                            included: 86,
                            bonus: 0,
                            total: 86
                        ),
                        autoPercentUsed: 0.36,
                        apiPercentUsed: 0.7111111111111111,
                        totalPercentUsed: 0.441025641025641
                    ),
                    onDemand: CursorOnDemandUsage(
                        enabled: false,
                        used: 0,
                        limit: nil,
                        remaining: nil
                    )
                ),
                teamUsage: CursorTeamUsage(onDemand: nil)
            )
        )

        XCTAssertEqual(snapshot.primaryWindow?.usedRatio ?? 0, 0.00441025641025641, accuracy: 0.0000001)
        XCTAssertEqual(snapshot.secondaryWindow?.usedRatio ?? 0, 0.0036, accuracy: 0.0000001)
        XCTAssertEqual(snapshot.tertiaryWindow?.usedRatio ?? 0, 0.007111111111111111, accuracy: 0.0000001)
    }

    func testCursorSnapshotPrefersLegacyRequestUsageWhenAvailable() {
        let provider = CursorQuotaProvider()
        let snapshot = provider._test_snapshot(
            summary: CursorUsageSummary(
                billingCycleStart: nil,
                billingCycleEnd: nil,
                membershipType: "enterprise",
                limitType: nil,
                isUnlimited: nil,
                autoModelSelectedDisplayMessage: nil,
                namedModelSelectedDisplayMessage: nil,
                individualUsage: nil,
                teamUsage: nil
            ),
            requestUsage: CursorUsageResponse(
                gpt4: CursorModelUsage(
                    numRequests: 120,
                    numRequestsTotal: 240,
                    numTokens: nil,
                    maxRequestUsage: 500,
                    maxTokenUsage: nil
                ),
                startOfMonth: nil
            )
        )

        XCTAssertEqual(snapshot.primaryWindow?.usedRatio ?? 0, 0.48, accuracy: 0.0001)
        XCTAssertEqual(snapshot.primaryWindow?.detail, "240 / 500 requests")
    }

    func testOpenCodeWorkspaceNormalizationFindsWorkspaceID() {
        let provider = OpenCodeQuotaProvider()

        XCTAssertEqual(
            provider._test_normalizeWorkspaceID("https://opencode.ai/workspace/wrk_abc123/billing"),
            "wrk_abc123"
        )
        XCTAssertEqual(provider._test_normalizeWorkspaceID("wrk_xyz789"), "wrk_xyz789")
    }

    func testCopilotUsageResponseDecodesQuotaSnapshots() throws {
        let data = Data(
            """
            {
              "copilot_plan": "individual",
              "quota_snapshots": {
                "premium_interactions": {
                  "entitlement": 300,
                  "remaining": 120,
                  "percent_remaining": 40,
                  "quota_id": "premium"
                },
                "chat": {
                  "entitlement": 1000,
                  "remaining": 950,
                  "percent_remaining": 95,
                  "quota_id": "chat"
                }
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: data)

        XCTAssertEqual(response.copilotPlan, "individual")
        XCTAssertEqual(response.quotaSnapshots.premiumInteractions?.percentRemaining ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(response.quotaSnapshots.chat?.remaining ?? 0, 950, accuracy: 0.001)
    }

    func testCopilotUsageResponseDecodesMonthlyFallbackPayload() throws {
        let data = Data(
            """
            {
              "copilot_plan": "free",
              "monthly_quotas": {
                "chat": "500",
                "completions": 300
              },
              "limited_user_quotas": {
                "chat": 125,
                "completions": "75"
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: data)

        XCTAssertEqual(response.quotaSnapshots.premiumInteractions?.quotaId, "completions")
        XCTAssertEqual(response.quotaSnapshots.premiumInteractions?.percentRemaining ?? 0, 25, accuracy: 0.001)
        XCTAssertEqual(response.quotaSnapshots.chat?.quotaId, "chat")
        XCTAssertEqual(response.quotaSnapshots.chat?.remaining ?? 0, 125, accuracy: 0.001)
    }

    func testCopilotUsageResponseFallsBackToUnknownQuotaKey() throws {
        let data = Data(
            """
            {
              "copilot_plan": "free",
              "quota_snapshots": {
                "mystery_bucket": {
                  "entitlement": 100,
                  "remaining": 40,
                  "percent_remaining": 40,
                  "quota_id": "mystery_bucket"
                }
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: data)

        XCTAssertNil(response.quotaSnapshots.premiumInteractions)
        XCTAssertEqual(response.quotaSnapshots.chat?.quotaId, "mystery_bucket")
        XCTAssertEqual(response.quotaSnapshots.chat?.percentRemaining ?? 0, 40, accuracy: 0.001)
    }

    func testCopilotUsageResponseUsesMonthlyFallbackWhenDirectSnapshotCannotComputePercent() throws {
        let data = Data(
            """
            {
              "copilot_plan": "free",
              "quota_snapshots": {
                "chat": {
                  "entitlement": 120,
                  "quota_id": "chat"
                }
              },
              "monthly_quotas": {
                "chat": 400
              },
              "limited_user_quotas": {
                "chat": 100
              }
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(CopilotUsageResponse.self, from: data)

        XCTAssertEqual(response.quotaSnapshots.chat?.quotaId, "chat")
        XCTAssertEqual(response.quotaSnapshots.chat?.entitlement ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(response.quotaSnapshots.chat?.remaining ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(response.quotaSnapshots.chat?.percentRemaining ?? 0, 25, accuracy: 0.001)
    }

    func testKimiUsageResponseDecodesWeeklyAndRateLimit() throws {
        let data = Data(
            """
            {
              "usages": [{
                "scope": "FEATURE_CODING",
                "detail": {
                  "limit": "2048",
                  "used": "214",
                  "remaining": "1834",
                  "resetTime": "2026-01-09T15:23:13.716839300Z"
                },
                "limits": [{
                  "window": { "duration": 300, "timeUnit": "TIME_UNIT_MINUTE" },
                  "detail": {
                    "limit": "200",
                    "used": "139",
                    "remaining": "61",
                    "resetTime": "2026-01-06T13:33:02.717479433Z"
                  }
                }]
              }]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(KimiUsageResponse.self, from: data)

        XCTAssertEqual(response.usages.count, 1)
        XCTAssertEqual(response.usages.first?.scope, "FEATURE_CODING")
        XCTAssertEqual(response.usages.first?.detail.limit, "2048")
        XCTAssertEqual(response.usages.first?.limits?.first?.window.duration, 300)
        XCTAssertEqual(response.usages.first?.limits?.first?.detail.remaining, "61")
    }

    func testJetBrainsQuotaParserParsesEncodedXML() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <application>
          <component name="AIAssistantQuotaManager2">
            <option name="quotaInfo" value="{&quot;type&quot;:&quot;Available&quot;,&quot;current&quot;:&quot;7478.3&quot;,&quot;maximum&quot;:&quot;1000000&quot;,&quot;tariffQuota&quot;:{&quot;available&quot;:&quot;992521.7&quot;},&quot;until&quot;:&quot;2026-06-01T12:00:00Z&quot;}" />
            <option name="nextRefill" value="{&quot;type&quot;:&quot;Known&quot;,&quot;next&quot;:&quot;2026-05-01T00:00:00Z&quot;,&quot;tariff&quot;:{&quot;amount&quot;:&quot;1000000&quot;,&quot;duration&quot;:&quot;PT720H&quot;}}" />
          </component>
        </application>
        """

        let (quotaInfo, refillInfo) = try JetBrainsQuotaParser.parseXMLData(Data(xml.utf8))

        XCTAssertEqual(quotaInfo.type, "Available")
        XCTAssertEqual(quotaInfo.used, 7478.3, accuracy: 0.001)
        XCTAssertEqual(quotaInfo.maximum, 1_000_000, accuracy: 0.001)
        XCTAssertEqual(quotaInfo.available, 992_521.7, accuracy: 0.001)
        XCTAssertNotNil(quotaInfo.until)
        XCTAssertEqual(refillInfo?.type, "Known")
        XCTAssertNotNil(refillInfo?.next)
        XCTAssertEqual(refillInfo?.amount ?? 0, 1_000_000, accuracy: 0.001)
    }

    func testKiroSnapshotParsesManagedPlanWithoutMetrics() throws {
        let provider = KiroQuotaProvider()
        let snapshot = try provider._test_snapshot(
            output: """
            Plan: Q Developer Pro
            Your plan is managed by admin
            """,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(snapshot.identity?.plan, "Q Developer Pro")
        XCTAssertNil(snapshot.primaryWindow)
        XCTAssertNil(snapshot.credits)
    }

    func testKiroSnapshotUsesParsedPercentWhenCoveredLineIsMissing() throws {
        let provider = KiroQuotaProvider()
        let snapshot = try provider._test_snapshot(
            output: """
            | KIRO FREE                                          |
            ████████████████████████████████████████████████████ 40%
            """,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(snapshot.primaryWindow?.usedRatio ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertNil(snapshot.credits)
    }

    func testKiroSnapshotRejectsManagedMarkerWithoutPlanHeader() {
        let provider = KiroQuotaProvider()

        XCTAssertThrowsError(
            try provider._test_snapshot(
                output: """
                Your plan is managed by admin
                """
            )
        )
    }
}
