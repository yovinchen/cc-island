import XCTest
@testable import Claude_Island

@MainActor
final class Wave2QuotaProviderTests: XCTestCase {
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
}
