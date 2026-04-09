import XCTest
@testable import Claude_Island

@MainActor
final class Wave3QuotaProviderTests: XCTestCase {
    func testAntigravityParsesUserStatusResponse() throws {
        let json = """
        {
          "code": 0,
          "userStatus": {
            "email": "test@example.com",
            "planStatus": {
              "planInfo": {
                "planName": "Pro"
              }
            },
            "cascadeModelConfigData": {
              "clientModelConfigs": [
                {
                  "label": "Claude 3.5 Sonnet",
                  "modelOrAlias": { "model": "claude-3-5-sonnet" },
                  "quotaInfo": { "remainingFraction": 0.5, "resetTime": "2025-12-24T10:00:00Z" }
                },
                {
                  "label": "Gemini Pro Low",
                  "modelOrAlias": { "model": "gemini-pro-low" },
                  "quotaInfo": { "remainingFraction": 0.8, "resetTime": "2025-12-24T11:00:00Z" }
                },
                {
                  "label": "Gemini Flash",
                  "modelOrAlias": { "model": "gemini-flash" },
                  "quotaInfo": { "remainingFraction": 0.2, "resetTime": "2025-12-24T12:00:00Z" }
                }
              ]
            }
          }
        }
        """

        let snapshot = try AntigravityStatusProbe.parseUserStatusResponse(Data(json.utf8))
        let quota = try snapshot.toQuotaSnapshot()

        XCTAssertEqual(quota.identity?.email, "test@example.com")
        XCTAssertEqual(quota.identity?.plan, "Pro")
        XCTAssertEqual(quota.primaryWindow?.usedRatio ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(quota.secondaryWindow?.usedRatio ?? 0, 0.2, accuracy: 0.001)
        XCTAssertEqual(quota.tertiaryWindow?.usedRatio ?? 0, 0.8, accuracy: 0.001)
    }

    func testVertexAICredentialsParseUserADCFile() throws {
        let json = """
        {
          "client_id": "client-id",
          "client_secret": "client-secret",
          "refresh_token": "refresh-token",
          "access_token": "access-token",
          "token_expiry": "2026-04-09T12:00:00Z",
          "id_token": "eyJhbGciOiJub25lIn0.eyJlbWFpbCI6InZlcnRleEBleGFtcGxlLmNvbSJ9."
        }
        """

        let credentials = try VertexAIOAuthCredentialsStore.parse(data: Data(json.utf8))

        XCTAssertEqual(credentials.clientId, "client-id")
        XCTAssertEqual(credentials.clientSecret, "client-secret")
        XCTAssertEqual(credentials.refreshToken, "refresh-token")
        XCTAssertEqual(credentials.accessToken, "access-token")
        XCTAssertEqual(credentials.email, "vertex@example.com")
        XCTAssertNotNil(credentials.expiryDate)
    }

    func testKiloParsesSnapshotMapsCreditsAndPass() throws {
        let json = """
        [
          {
            "result": {
              "data": {
                "json": {
                  "blocks": [
                    {
                      "usedCredits": 25,
                      "totalCredits": 100,
                      "remainingCredits": 75
                    }
                  ]
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "subscription": {
                    "tier": "tier_49",
                    "currentPeriodUsageUsd": 0,
                    "currentPeriodBaseCreditsUsd": 19.0,
                    "currentPeriodBonusCreditsUsd": 9.5,
                    "nextBillingAt": "2026-03-28T04:00:00.000Z"
                  }
                }
              }
            }
          },
          {
            "result": {
              "data": {
                "json": {
                  "enabled": false,
                  "paymentMethod": null
                }
              }
            }
          }
        ]
        """

        let snapshot = try KiloUsageFetcher._test_parseSnapshot(Data(json.utf8))
        let quota = snapshot.toQuotaSnapshot(source: .apiKey)

        XCTAssertEqual(quota.primaryWindow?.usedRatio ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(quota.secondaryWindow?.detail, "$0.00 / $19.00 (+ $9.50 bonus)")
        XCTAssertEqual(quota.identity?.plan, "Pro")
        XCTAssertEqual(quota.identity?.detail, "Auto top-up: off")
    }
}
