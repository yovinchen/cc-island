import XCTest
@testable import Claude_Island

final class GeminiQuotaProviderTests: XCTestCase {
    func testGeminiOAuthClientCredentialsParseBundledChunkContent() {
        let content = """
        var OAUTH_CLIENT_ID = "client-id.apps.googleusercontent.com";
        var OAUTH_CLIENT_SECRET = "secret-value";
        """

        let credentials = GeminiQuotaTestingSupport.extractOAuthClientCredentials(from: content)

        XCTAssertEqual(credentials?.clientId, "client-id.apps.googleusercontent.com")
        XCTAssertEqual(credentials?.clientSecret, "secret-value")
    }

    func testGeminiProjectIdParsesNestedCloudCompanionProject() {
        let json: [String: Any] = [
            "cloudaicompanionProject": [
                "projectId": "nested-project-id",
            ],
        ]

        let projectId = GeminiQuotaTestingSupport.parseProjectId(json: json)

        XCTAssertEqual(projectId, "nested-project-id")
    }
}
