//
//  Wave4QuotaProviders.swift
//  ClaudeIsland
//

import Foundation
#if canImport(SweetCookieKit)
import SweetCookieKit
#endif

// MARK: - Perplexity

private enum PerplexityAPIError: LocalizedError, Sendable, Equatable {
    case missingToken
    case invalidCookie
    case invalidToken
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Perplexity session token is missing. Please log into Perplexity in your browser."
        case .invalidCookie:
            return "Perplexity manual cookie header is empty or invalid."
        case .invalidToken:
            return "Perplexity session token is invalid or expired. Please log in again."
        case .networkError(let message):
            return "Perplexity network error: \(message)"
        case .apiError(let message):
            return "Perplexity API error: \(message)"
        case .parseFailed(let message):
            return "Failed to parse Perplexity usage data: \(message)"
        }
    }
}

struct PerplexityCreditGrant: Codable, Sendable {
    let type: String
    let amountCents: Double
    let expiresAtTs: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case type
        case amountCents = "amount_cents"
        case expiresAtTs = "expires_at_ts"
    }
}

struct PerplexityCreditsResponse: Codable, Sendable {
    let balanceCents: Double
    let renewalDateTs: TimeInterval
    let currentPeriodPurchasedCents: Double
    let creditGrants: [PerplexityCreditGrant]
    let totalUsageCents: Double

    enum CodingKeys: String, CodingKey {
        case balanceCents = "balance_cents"
        case renewalDateTs = "renewal_date_ts"
        case currentPeriodPurchasedCents = "current_period_purchased_cents"
        case creditGrants = "credit_grants"
        case totalUsageCents = "total_usage_cents"
    }
}

struct PerplexityUsageSnapshot: Sendable {
    let recurringTotal: Double
    let recurringUsed: Double
    let promoTotal: Double
    let promoUsed: Double
    let purchasedTotal: Double
    let purchasedUsed: Double
    let balanceCents: Double
    let totalUsageCents: Double
    let renewalDate: Date
    let promoExpiration: Date?
    let updatedAt: Date

    init(response: PerplexityCreditsResponse, now: Date) {
        let recurring = response.creditGrants.filter { $0.type == "recurring" }
        let promotional = response.creditGrants.filter {
            $0.type == "promotional" && ($0.expiresAtTs ?? .infinity) > now.timeIntervalSince1970
        }
        let purchased = response.creditGrants.filter { $0.type == "purchased" }

        let recurringSum = max(0, recurring.reduce(0.0) { $0 + $1.amountCents })
        let promoSum = max(0, promotional.reduce(0.0) { $0 + $1.amountCents })
        let purchasedFromGrants = max(0, purchased.reduce(0.0) { $0 + $1.amountCents })
        let purchasedFromField = max(0, response.currentPeriodPurchasedCents)
        let purchasedSum = max(purchasedFromGrants, purchasedFromField)

        var remaining = response.totalUsageCents
        let usedFromRecurring = min(remaining, recurringSum); remaining -= usedFromRecurring
        let usedFromPurchased = min(remaining, purchasedSum); remaining -= usedFromPurchased
        let usedFromPromo = min(remaining, promoSum)

        recurringTotal = recurringSum
        recurringUsed = usedFromRecurring
        promoTotal = promoSum
        promoUsed = usedFromPromo
        purchasedTotal = purchasedSum
        purchasedUsed = usedFromPurchased
        balanceCents = response.balanceCents
        totalUsageCents = response.totalUsageCents
        renewalDate = Date(timeIntervalSince1970: response.renewalDateTs)
        promoExpiration = promotional
            .compactMap { $0.expiresAtTs.map { Date(timeIntervalSince1970: $0) } }
            .min()
        updatedAt = now
    }

    var planName: String? {
        if recurringTotal <= 0 { return nil }
        if recurringTotal < 5000 { return "Pro" }
        return "Max"
    }

    private static let promoExpiryFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt
    }()

    func toQuotaSnapshot(sourceNote: String? = nil) -> QuotaSnapshot {
        let hasFallbackCredits = promoTotal > 0 || purchasedTotal > 0

        let primaryWindow: QuotaWindow? = {
            if recurringTotal > 0 {
                return QuotaWindow(
                    label: QuotaProviderRegistry.descriptor(for: .perplexity).primaryLabel,
                    usedRatio: min(1, max(0, recurringUsed / recurringTotal)),
                    detail: "\(Int(recurringUsed.rounded()))/\(Int(recurringTotal)) credits",
                    resetsAt: renewalDate
                )
            }
            if hasFallbackCredits {
                return nil
            }
            return QuotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .perplexity).primaryLabel,
                usedRatio: 1,
                detail: "0/0 credits",
                resetsAt: renewalDate
            )
        }()

        let secondaryDetail: String = {
            var detail = "\(Int(promoUsed.rounded()))/\(Int(promoTotal)) bonus"
            if let expiry = promoExpiration {
                detail += " · exp. \(Self.promoExpiryFormatter.string(from: expiry))"
            }
            return detail
        }()
        let secondaryWindow = QuotaWindow(
            label: QuotaProviderRegistry.descriptor(for: .perplexity).secondaryLabel ?? "Bonus credits",
            usedRatio: promoTotal > 0 ? min(1, max(0, promoUsed / promoTotal)) : 1,
            detail: secondaryDetail,
            resetsAt: nil
        )

        let tertiaryWindow = QuotaWindow(
            label: "Purchased",
            usedRatio: purchasedTotal > 0 ? min(1, max(0, purchasedUsed / purchasedTotal)) : 1,
            detail: "\(Int(purchasedUsed.rounded()))/\(Int(purchasedTotal)) credits",
            resetsAt: nil
        )

        return QuotaSnapshot(
            providerID: .perplexity,
            source: .web,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: tertiaryWindow,
            credits: nil,
            identity: QuotaIdentity(
                email: nil,
                organization: nil,
                plan: planName,
                detail: nil
            ),
            updatedAt: updatedAt,
            note: sourceNote
        )
    }
}

private struct PerplexityCookieOverride: Sendable, Equatable {
    let name: String
    let token: String
    let requestCookieNames: [String]

    init(name: String, token: String, requestCookieNames: [String]? = nil) {
        self.name = name
        self.token = token
        self.requestCookieNames = requestCookieNames ?? [name]
    }
}

private enum PerplexityCookieSupport {
    nonisolated static let defaultSessionCookieName = "__Secure-next-auth.session-token"
    nonisolated static let supportedSessionCookieNames = [
        "__Secure-authjs.session-token",
        "authjs.session-token",
        "__Secure-next-auth.session-token",
        "next-auth.session-token",
    ]

    static func override(from raw: String?) -> PerplexityCookieOverride? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        if !raw.contains("="), !raw.contains(";") {
            return PerplexityCookieOverride(
                name: defaultSessionCookieName,
                token: raw,
                requestCookieNames: supportedSessionCookieNames
            )
        }

        return extractSessionCookie(from: CookieHeaderNormalizer.pairs(from: raw))
    }

    static func sessionCookie(from cookies: [HTTPCookie]) -> PerplexityCookieOverride? {
        extractSessionCookie(from: cookies.map { CookieHeaderNormalizer.Pair(name: $0.name, value: $0.value) })
    }

    private static func extractSessionCookie(from cookies: [CookieHeaderNormalizer.Pair]) -> PerplexityCookieOverride? {
        var cookieMap: [String: CookieHeaderNormalizer.Pair] = [:]
        var chunkedCookies: [String: [Int: CookieHeaderNormalizer.Pair]] = [:]

        for cookie in cookies {
            let loweredName = cookie.name.lowercased()
            cookieMap[loweredName] = cookie

            for expected in supportedSessionCookieNames {
                let loweredExpected = expected.lowercased()
                let prefix = "\(loweredExpected)."
                guard loweredName.hasPrefix(prefix) else { continue }
                let suffix = String(loweredName.dropFirst(prefix.count))
                guard let index = Int(suffix) else { continue }
                chunkedCookies[loweredExpected, default: [:]][index] = cookie
            }
        }

        for expected in supportedSessionCookieNames {
            let loweredExpected = expected.lowercased()
            if let match = cookieMap[loweredExpected] {
                return PerplexityCookieOverride(name: match.name, token: match.value)
            }
            if let chunked = reassembleChunkedSessionCookie(from: chunkedCookies[loweredExpected]) {
                return chunked
            }
        }
        return nil
    }

    private static func reassembleChunkedSessionCookie(
        from chunks: [Int: CookieHeaderNormalizer.Pair]?
    ) -> PerplexityCookieOverride? {
        guard let chunks,
              let firstChunk = chunks[0],
              let maxIndex = chunks.keys.max()
        else {
            return nil
        }

        var tokenParts: [String] = []
        tokenParts.reserveCapacity(maxIndex + 1)
        for index in 0...maxIndex {
            guard let chunk = chunks[index] else { return nil }
            tokenParts.append(chunk.value)
        }

        guard let suffixStart = firstChunk.name.lastIndex(of: ".") else { return nil }
        let baseName = String(firstChunk.name[..<suffixStart])
        return PerplexityCookieOverride(name: baseName, token: tokenParts.joined())
    }
}

#if os(macOS) && canImport(SweetCookieKit)
private enum PerplexityBrowserCookieImporter {
    private static let cookieDomains = ["www.perplexity.ai", "perplexity.ai"]

    static func hasSession() -> Bool {
        !candidateSessions().isEmpty
    }

    static func candidateSessions() -> [QuotaBrowserCookieSession] {
        QuotaBrowserCookieImporter.candidateSessions(
            domains: cookieDomains,
            browserOrder: Browser.defaultImportOrder,
            requiredCookieNames: Set(PerplexityCookieSupport.supportedSessionCookieNames),
            allowDomainFallback: true
        )
    }
}
#endif

enum PerplexityUsageFetcher {
    private static let creditsURL = URL(string: "https://www.perplexity.ai/rest/billing/credits?version=2.18&source=default")!

    static func parseResponse(_ data: Data, now: Date = Date()) throws -> PerplexityUsageSnapshot {
        do {
            let decoded = try JSONDecoder().decode(PerplexityCreditsResponse.self, from: data)
            return PerplexityUsageSnapshot(response: decoded, now: now)
        } catch {
            throw PerplexityAPIError.parseFailed(error.localizedDescription)
        }
    }

    static func fetchCredits(
        sessionToken: String,
        cookieName: String = PerplexityCookieSupport.defaultSessionCookieName,
        now: Date = Date()
    ) async throws -> PerplexityUsageSnapshot {
        var request = URLRequest(url: creditsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(cookieName)=\(sessionToken)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.perplexity.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://www.perplexity.ai/account/usage", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PerplexityAPIError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw PerplexityAPIError.invalidToken
            }
            throw PerplexityAPIError.apiError("HTTP \(httpResponse.statusCode)")
        }

        return try parseResponse(data, now: now)
    }
}

struct PerplexityQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .perplexity)

    func isConfigured() -> Bool {
        !cookieCandidates().isEmpty
    }

    func fetch() async throws -> QuotaSnapshot {
        try await fetchOutcome().snapshot
    }

    func fetchOutcome() async throws -> QuotaProviderFetchOutcome {
        let candidates = cookieCandidates()
        let requestContext = "https://www.perplexity.ai/rest/billing/credits"
        guard !candidates.isEmpty else {
            throw wave4Failure(
                providerID: .perplexity,
                message: PerplexityAPIError.missingToken.localizedDescription,
                sourceLabel: "Web login",
                attemptedSource: QuotaPreferences.webCredentialMode(for: .perplexity).rawValue,
                requestContext: requestContext
            )
        }

        var lastError: Error?
        for candidate in candidates {
            guard let cookie = PerplexityCookieSupport.override(from: candidate.cookieHeader) else { continue }
            do {
                let snapshot = try await fetchSnapshot(cookie: cookie, sourceNote: candidate.provenanceLabel)
                if candidate.shouldCacheOnSuccess {
                    QuotaCookieCache.store(
                        providerID: .perplexity,
                        cookieHeader: "\(cookie.name)=\(cookie.token)",
                        sourceLabel: candidate.provenanceLabel
                    )
                }
                return QuotaProviderFetchOutcome(
                    snapshot: snapshot,
                    sourceLabel: candidate.sourceLabel,
                    debugProbe: wave4DebugProbe(
                        providerID: .perplexity,
                        attemptedSource: candidate.sourceKind.rawValue,
                        resolvedSource: candidate.sourceKind.rawValue,
                        provenanceLabel: candidate.provenanceLabel,
                        requestContext: requestContext,
                        lastValidation: "Perplexity billing credits payload accepted."
                    )
                )
            } catch {
                lastError = error
                if candidate.sourceKind == .cache {
                    QuotaCookieCache.clear(providerID: .perplexity)
                }
            }
        }

        throw wave4Failure(
            providerID: .perplexity,
            message: lastError?.localizedDescription ?? PerplexityAPIError.missingToken.localizedDescription,
            sourceLabel: "Web login",
            attemptedSource: candidates.map(\.sourceLabel).joined(separator: " -> "),
            requestContext: requestContext
        )
    }

    private func cookieCandidates() -> [QuotaResolvedCookieCandidate] {
#if os(macOS) && canImport(SweetCookieKit)
        let sessions = PerplexityBrowserCookieImporter.candidateSessions()
#else
        let sessions: [QuotaBrowserCookieSession] = []
#endif
        return QuotaCookieCandidateResolver.candidates(
            providerID: .perplexity,
            envKeys: ["PERPLEXITY_COOKIE_HEADER", "PERPLEXITY_SESSION_TOKEN"],
            browserSessions: sessions
        )
    }

    private func fetchSnapshot(
        cookie: PerplexityCookieOverride,
        sourceNote: String?
    ) async throws -> QuotaSnapshot {
        var lastInvalidToken = false

        for cookieName in cookie.requestCookieNames {
            do {
                let snapshot = try await PerplexityUsageFetcher.fetchCredits(
                    sessionToken: cookie.token,
                    cookieName: cookieName
                )
                return snapshot.toQuotaSnapshot(sourceNote: sourceNote)
            } catch let error as PerplexityAPIError {
                if case .invalidToken = error {
                    lastInvalidToken = true
                    continue
                }
                throw error
            }
        }

        if lastInvalidToken {
            throw PerplexityAPIError.invalidToken
        }
        throw PerplexityAPIError.missingToken
    }
}

// MARK: - Shared helpers

private func wave4DebugProbe(
    providerID: QuotaProviderID,
    attemptedSource: String?,
    resolvedSource: String? = nil,
    provenanceLabel: String? = nil,
    requestContext: String? = nil,
    lastValidation: String? = nil,
    lastFailure: String? = nil
) -> QuotaDebugProbeSnapshot {
    QuotaDebugProbeSnapshot(
        providerID: providerID,
        attemptedSource: attemptedSource,
        resolvedSource: resolvedSource,
        provenanceLabel: provenanceLabel,
        requestContext: requestContext,
        lastValidation: lastValidation,
        lastFailure: lastFailure
    )
}

private func wave4Failure(
    providerID: QuotaProviderID,
    message: String,
    sourceLabel: String? = nil,
    attemptedSource: String? = nil,
    resolvedSource: String? = nil,
    provenanceLabel: String? = nil,
    requestContext: String? = nil
) -> QuotaProviderFailure {
    QuotaProviderFailure(
        message: message,
        sourceLabel: sourceLabel,
        debugProbe: wave4DebugProbe(
            providerID: providerID,
            attemptedSource: attemptedSource,
            resolvedSource: resolvedSource,
            provenanceLabel: provenanceLabel,
            requestContext: requestContext,
            lastValidation: nil,
            lastFailure: message
        )
    )
}

private func wave4NormalizedCookieHeader(_ raw: String?) -> String? {
    guard var value = QuotaRuntimeSupport.cleaned(raw), !value.isEmpty else {
        return nil
    }
    value = value.replacingOccurrences(of: #"(?i)^cookie:\s*"#, with: "", options: .regularExpression)
    return value.isEmpty ? nil : value
}

private enum Wave4JSONLookup {
    static func firstDictionary(in object: Any?, where predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        switch object {
        case let dict as [String: Any]:
            if predicate(dict) { return dict }
            for value in dict.values {
                if let match = firstDictionary(in: value, where: predicate) {
                    return match
                }
            }
        case let array as [Any]:
            for item in array {
                if let match = firstDictionary(in: item, where: predicate) {
                    return match
                }
            }
        default:
            break
        }
        return nil
    }

    static func allDictionaries(in object: Any?) -> [[String: Any]] {
        switch object {
        case let dict as [String: Any]:
            return [dict] + dict.values.flatMap { allDictionaries(in: $0) }
        case let array as [Any]:
            return array.flatMap { allDictionaries(in: $0) }
        default:
            return []
        }
    }

    static func string(_ raw: Any?) -> String? {
        QuotaRuntimeSupport.stringValue(raw)
    }

    static func double(_ raw: Any?) -> Double? {
        QuotaRuntimeSupport.doubleValue(raw)
    }

    static func int(_ raw: Any?) -> Int? {
        QuotaRuntimeSupport.intValue(raw)
    }

    static func date(_ raw: Any?) -> Date? {
        if let string = string(raw), let date = QuotaUtilities.isoDate(string) {
            return date
        }
        if let double = double(raw) {
            if double > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: double / 1000.0)
            }
            if double > 1_000_000_000 {
                return Date(timeIntervalSince1970: double)
            }
        }
        return QuotaRuntimeSupport.dateFromMilliseconds(raw)
    }

    static func firstString(in contexts: [[String: Any]], keys: [String]) -> String? {
        for key in keys {
            for context in contexts {
                if let value = string(context[key]) {
                    return value
                }
            }
        }
        return nil
    }

    static func firstInt(in contexts: [[String: Any]], keys: [String]) -> Int? {
        for key in keys {
            for context in contexts {
                if let value = int(context[key]) {
                    return value
                }
            }
        }
        return nil
    }

    static func firstDate(in contexts: [[String: Any]], keys: [String]) -> Date? {
        for key in keys {
            for context in contexts {
                if let value = date(context[key]) {
                    return value
                }
            }
        }
        return nil
    }
}

private enum Wave4SecretAccounts {
    static let alibabaAPI = QuotaProviderRegistry.secretAccountName(for: .alibaba, suffix: "api")
    static let minimaxAPI = QuotaProviderRegistry.secretAccountName(for: .minimax, suffix: "api")
}

// MARK: - Alibaba

private enum AlibabaQuotaError: LocalizedError, Sendable {
    case missingToken
    case missingCookie
    case invalidCookie
    case loginRequired
    case invalidCredentials
    case apiError(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Alibaba Coding Plan API key not configured."
        case .missingCookie:
            return "Alibaba Coding Plan session cookie not configured."
        case .invalidCookie:
            return "Alibaba Coding Plan cookie header is invalid."
        case .loginRequired:
            return "Alibaba Coding Plan console login is required."
        case .invalidCredentials:
            return "Alibaba Coding Plan credentials are invalid or expired."
        case .apiError(let message):
            return "Alibaba Coding Plan API error: \(message)"
        case .parseFailed(let message):
            return "Alibaba Coding Plan usage parsing failed: \(message)"
        }
    }
}

struct AlibabaQuotaUsageSnapshot: Sendable {
    let planName: String?
    let fiveHourUsed: Int?
    let fiveHourTotal: Int?
    let fiveHourReset: Date?
    let weeklyUsed: Int?
    let weeklyTotal: Int?
    let weeklyReset: Date?
    let monthlyUsed: Int?
    let monthlyTotal: Int?
    let monthlyReset: Date?
    let updatedAt: Date

    func toQuotaSnapshot(note: String? = nil) -> QuotaSnapshot {
        QuotaSnapshot(
            providerID: .alibaba,
            source: .web,
            primaryWindow: quotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .alibaba).primaryLabel,
                usedRatio: quotaRatio(used: fiveHourUsed.map(Double.init), total: fiveHourTotal.map(Double.init)),
                detail: usageDetail(used: fiveHourUsed, total: fiveHourTotal),
                resetsAt: fiveHourReset
            ),
            secondaryWindow: quotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .alibaba).secondaryLabel ?? "Weekly",
                usedRatio: quotaRatio(used: weeklyUsed.map(Double.init), total: weeklyTotal.map(Double.init)),
                detail: usageDetail(used: weeklyUsed, total: weeklyTotal),
                resetsAt: weeklyReset
            ),
            tertiaryWindow: quotaWindow(
                label: "Monthly",
                usedRatio: quotaRatio(used: monthlyUsed.map(Double.init), total: monthlyTotal.map(Double.init)),
                detail: usageDetail(used: monthlyUsed, total: monthlyTotal),
                resetsAt: monthlyReset
            ),
            credits: nil,
            identity: QuotaIdentity(email: nil, organization: nil, plan: planName, detail: nil),
            updatedAt: updatedAt,
            note: note
        )
    }

    private func usageDetail(used: Int?, total: Int?) -> String? {
        guard let used, let total, total > 0 else { return nil }
        return "\(used) / \(total) used"
    }
}

private enum AlibabaRegionSupport {
    static func dashboardURL(region: QuotaAlibabaRegion) -> URL {
        switch region {
        case .international:
            return URL(string: "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/detail")!
        case .chinaMainland:
            return URL(string: "https://bailian.console.aliyun.com/cn-beijing/?tab=model#/efm/coding_plan")!
        }
    }

    static func gatewayBaseURL(region: QuotaAlibabaRegion) -> URL {
        switch region {
        case .international:
            return URL(string: "https://modelstudio.console.alibabacloud.com")!
        case .chinaMainland:
            return URL(string: "https://bailian.console.aliyun.com")!
        }
    }

    static func quotaURL(region: QuotaAlibabaRegion) -> URL {
        var components = URLComponents(url: gatewayBaseURL(region: region), resolvingAgainstBaseURL: false)!
        components.path = "/data/api.json"
        components.queryItems = [
            URLQueryItem(name: "action", value: "zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2"),
            URLQueryItem(name: "product", value: "broadscope-bailian"),
            URLQueryItem(name: "api", value: "queryCodingPlanInstanceInfoV2"),
            URLQueryItem(name: "currentRegionId", value: region == .international ? "ap-southeast-1" : "cn-beijing"),
        ]
        return components.url!
    }

    static func consoleRPCURL(region: QuotaAlibabaRegion) -> URL {
        let base: String = switch region {
        case .international:
            "https://bailian-singapore-cs.alibabacloud.com"
        case .chinaMainland:
            "https://bailian-beijing-cs.aliyuncs.com"
        }
        var components = URLComponents(string: base)!
        components.path = "/data/api.json"
        components.queryItems = [
            URLQueryItem(name: "action", value: region == .international ? "IntlBroadScopeAspnGateway" : "BroadScopeAspnGateway"),
            URLQueryItem(name: "product", value: "sfm_bailian"),
            URLQueryItem(name: "api", value: "zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2"),
            URLQueryItem(name: "_v", value: "undefined"),
        ]
        return components.url!
    }

    static func refererURL(region: QuotaAlibabaRegion) -> URL {
        switch region {
        case .international:
            return URL(string: "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan")!
        case .chinaMainland:
            return URL(string: "https://bailian.console.aliyun.com/cn-beijing/?tab=model")!
        }
    }
}

private enum AlibabaSettingsSupport {
    static func apiTokenInfo() -> ResolvedProviderCredential? {
        SavedProviderTokenResolver.tokenInfo(
            account: Wave4SecretAccounts.alibabaAPI,
            envKeys: ["ALIBABA_CODING_PLAN_API_KEY"]
        )
    }

    static func cookieInfo() -> ResolvedProviderCredential? {
        guard let info = SavedProviderTokenResolver.tokenInfo(for: .alibaba, envKeys: ["ALIBABA_CODING_PLAN_COOKIE"]),
              let normalized = wave4NormalizedCookieHeader(info.value)
        else {
            return nil
        }
        return ResolvedProviderCredential(value: normalized, sourceLabel: info.sourceLabel)
    }

    static func secToken(from cookieHeader: String) -> String? {
        CookieHeaderNormalizer.pairs(from: cookieHeader)
            .first(where: { $0.name == "sec_token" })?
            .value
    }
}

#if os(macOS) && canImport(SweetCookieKit)
private enum AlibabaBrowserCookieImporter {
    private static let cookieDomains = [
        "bailian-singapore-cs.alibabacloud.com",
        "bailian-beijing-cs.aliyuncs.com",
        "modelstudio.console.alibabacloud.com",
        "bailian.console.aliyun.com",
        "alibabacloud.com",
        "aliyun.com",
    ]
    private static let browserOrder: [Browser] = {
        let preferred: [Browser] = [.chrome, .chromeBeta, .brave, .edge, .arc, .firefox, .safari]
        let defaults = Browser.defaultImportOrder
        return preferred.filter(defaults.contains) + defaults.filter { !preferred.contains($0) }
    }()

    static func candidateSessions() -> [QuotaBrowserCookieSession] {
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: cookieDomains)
        var sessions: [QuotaBrowserCookieSession] = []

        for browser in browserOrder {
            let regularSessions: [QuotaBrowserCookieSession] = (try? client.records(matching: query, in: browser, logger: nil))?.compactMap { source in
                let cookies = BrowserCookieClient.makeHTTPCookies(source.records, origin: query.origin)
                guard AlibabaChromiumCookieFallbackImporter.isAuthenticatedSession(cookies) else { return nil }
                return QuotaBrowserCookieSession(cookies: cookies, sourceLabel: source.label)
            } ?? []

            if !regularSessions.isEmpty {
                sessions.append(contentsOf: regularSessions)
                continue
            }

            if browser.usesChromiumProfileStore,
               let fallback = try? AlibabaChromiumCookieFallbackImporter.importSession(browser: browser, domains: cookieDomains)
            {
                sessions.append(fallback)
            }
        }

        var seen = Set<String>()
        return sessions.filter { seen.insert($0.cookieHeader).inserted }
    }
}
#endif

enum AlibabaUsageFetcher {
    static func fetchUsage(apiKey: String, region: QuotaAlibabaRegion, now: Date = Date()) async throws -> AlibabaQuotaUsageSnapshot {
        var request = URLRequest(url: AlibabaRegionSupport.quotaURL(region: region))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiKey, forHTTPHeaderField: "X-DashScope-API-Key")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue(AlibabaRegionSupport.gatewayBaseURL(region: region).absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(AlibabaRegionSupport.dashboardURL(region: region).absoluteString, forHTTPHeaderField: "Referer")
        let commodityCode = region == .international ? "sfm_codingplan_public_intl" : "sfm_codingplan_public_cn"
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["queryCodingPlanInstanceInfoRequest": ["commodityCode": commodityCode]]
        )

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw AlibabaQuotaError.invalidCredentials
            }
            throw AlibabaQuotaError.apiError("HTTP \(response.statusCode)")
        }
        return try parseUsageSnapshot(from: data, now: now, authMode: "api")
    }

    static func fetchUsage(cookieHeader: String, region: QuotaAlibabaRegion, now: Date = Date()) async throws -> AlibabaQuotaUsageSnapshot {
        guard let secToken = AlibabaSettingsSupport.secToken(from: cookieHeader) else {
            throw AlibabaQuotaError.loginRequired
        }

        var request = URLRequest(url: AlibabaRegionSupport.consoleRPCURL(region: region))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue(AlibabaRegionSupport.gatewayBaseURL(region: region).absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(AlibabaRegionSupport.refererURL(region: region).absoluteString, forHTTPHeaderField: "Referer")

        let params: [String: Any] = [
            "Api": "zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2",
            "V": "1.0",
            "Data": [
                "queryCodingPlanInstanceInfoRequest": [
                    "commodityCode": region == .international ? "sfm_codingplan_public_intl" : "sfm_codingplan_public_cn",
                    "onlyLatestOne": true,
                ],
            ],
        ]
        let paramsData = try JSONSerialization.data(withJSONObject: params)
        let paramsString = String(decoding: paramsData, as: UTF8.self)
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "params", value: paramsString),
            URLQueryItem(name: "region", value: region == .international ? "ap-southeast-1" : "cn-beijing"),
            URLQueryItem(name: "sec_token", value: secToken),
        ]
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw AlibabaQuotaError.loginRequired
            }
            throw AlibabaQuotaError.apiError("HTTP \(response.statusCode)")
        }
        return try parseUsageSnapshot(from: data, now: now, authMode: "web")
    }

    static func parseUsageSnapshot(from data: Data, now: Date = Date(), authMode: String) throws -> AlibabaQuotaUsageSnapshot {
        let object = try JSONSerialization.jsonObject(with: data)
        let dictionaries = Wave4JSONLookup.allDictionaries(in: object)

        if let statusCode = Wave4JSONLookup.firstInt(in: dictionaries, keys: ["statusCode", "status_code", "code"]),
           statusCode != 0, statusCode != 200
        {
            let message = Wave4JSONLookup.firstString(in: dictionaries, keys: ["statusMessage", "status_msg", "message", "msg"])
                ?? "status code \(statusCode)"
            if statusCode == 401 || statusCode == 403 {
                throw authMode == "web" ? AlibabaQuotaError.loginRequired : AlibabaQuotaError.invalidCredentials
            }
            throw AlibabaQuotaError.apiError(message)
        }

        let activeInstance = Wave4JSONLookup.firstDictionary(in: object) { dict in
            dict.keys.contains("per5HourTotalQuota") || dict.keys.contains("perWeekTotalQuota") || dict.keys.contains("perBillMonthTotalQuota")
        }
        let contexts = [activeInstance].compactMap { $0 } + dictionaries
        let planName = Wave4JSONLookup.firstString(in: contexts, keys: ["planName", "instanceName", "packageName"])

        let snapshot = AlibabaQuotaUsageSnapshot(
            planName: planName,
            fiveHourUsed: Wave4JSONLookup.firstInt(in: contexts, keys: ["per5HourUsedQuota", "perFiveHourUsedQuota"]),
            fiveHourTotal: Wave4JSONLookup.firstInt(in: contexts, keys: ["per5HourTotalQuota", "perFiveHourTotalQuota"]),
            fiveHourReset: Wave4JSONLookup.firstDate(in: contexts, keys: ["per5HourQuotaNextRefreshTime", "perFiveHourQuotaNextRefreshTime"]),
            weeklyUsed: Wave4JSONLookup.firstInt(in: contexts, keys: ["perWeekUsedQuota"]),
            weeklyTotal: Wave4JSONLookup.firstInt(in: contexts, keys: ["perWeekTotalQuota"]),
            weeklyReset: Wave4JSONLookup.firstDate(in: contexts, keys: ["perWeekQuotaNextRefreshTime"]),
            monthlyUsed: Wave4JSONLookup.firstInt(in: contexts, keys: ["perBillMonthUsedQuota", "perMonthUsedQuota"]),
            monthlyTotal: Wave4JSONLookup.firstInt(in: contexts, keys: ["perBillMonthTotalQuota", "perMonthTotalQuota"]),
            monthlyReset: Wave4JSONLookup.firstDate(in: contexts, keys: ["perBillMonthQuotaNextRefreshTime", "perMonthQuotaNextRefreshTime"]),
            updatedAt: now
        )

        guard snapshot.fiveHourTotal != nil || snapshot.weeklyTotal != nil || snapshot.monthlyTotal != nil || planName != nil else {
            throw AlibabaQuotaError.parseFailed("Missing coding plan quota fields.")
        }
        return snapshot
    }
}

struct AlibabaQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .alibaba)

    func isConfigured() -> Bool {
        let sourceMode = QuotaPreferences.sourcePreference(for: .alibaba)
        if sourceMode == .apiKey {
            return AlibabaSettingsSupport.apiTokenInfo() != nil
        }
        if sourceMode == .web {
            return !cookieCandidates().isEmpty
        }
        return AlibabaSettingsSupport.apiTokenInfo() != nil || !cookieCandidates().isEmpty
    }

    func fetch() async throws -> QuotaSnapshot {
        try await fetchOutcome().snapshot
    }

    func fetchOutcome() async throws -> QuotaProviderFetchOutcome {
        let sourceMode = QuotaPreferences.sourcePreference(for: .alibaba)
        let region = QuotaPreferences.alibabaRegion
        var lastError: Error?

        if sourceMode != .web, let apiToken = AlibabaSettingsSupport.apiTokenInfo() {
            do {
                let snapshot = try await AlibabaUsageFetcher.fetchUsage(apiKey: apiToken.value, region: region)
                return QuotaProviderFetchOutcome(
                    snapshot: snapshot.toQuotaSnapshot(note: apiToken.sourceLabel),
                    sourceLabel: apiToken.sourceLabel,
                    debugProbe: wave4DebugProbe(
                        providerID: .alibaba,
                        attemptedSource: "api",
                        resolvedSource: "api",
                        provenanceLabel: apiToken.sourceLabel,
                        requestContext: AlibabaRegionSupport.quotaURL(region: region).absoluteString,
                        lastValidation: "Alibaba Coding Plan API payload accepted."
                    )
                )
            } catch {
                lastError = error
                if sourceMode == .apiKey {
                    throw wave4Failure(
                        providerID: .alibaba,
                        message: error.localizedDescription,
                        sourceLabel: apiToken.sourceLabel,
                        attemptedSource: "api",
                        resolvedSource: "api",
                        provenanceLabel: apiToken.sourceLabel,
                        requestContext: AlibabaRegionSupport.quotaURL(region: region).absoluteString
                    )
                }
            }
        }

        if sourceMode != .apiKey {
            let candidates = cookieCandidates()
            for candidate in candidates {
                do {
                    let snapshot = try await AlibabaUsageFetcher.fetchUsage(cookieHeader: candidate.cookieHeader, region: region)
                    if candidate.shouldCacheOnSuccess {
                        QuotaCookieCache.store(providerID: .alibaba, cookieHeader: candidate.cookieHeader, sourceLabel: candidate.provenanceLabel)
                    }
                    return QuotaProviderFetchOutcome(
                        snapshot: snapshot.toQuotaSnapshot(note: candidate.provenanceLabel),
                        sourceLabel: candidate.sourceLabel,
                        debugProbe: wave4DebugProbe(
                            providerID: .alibaba,
                            attemptedSource: candidate.sourceKind.rawValue,
                            resolvedSource: candidate.sourceKind.rawValue,
                            provenanceLabel: candidate.provenanceLabel,
                            requestContext: AlibabaRegionSupport.consoleRPCURL(region: region).absoluteString,
                            lastValidation: "Alibaba Coding Plan console payload accepted."
                        )
                    )
                } catch {
                    lastError = error
                    if candidate.sourceKind == .cache {
                        QuotaCookieCache.clear(providerID: .alibaba)
                    }
                }
            }
        }

        throw wave4Failure(
            providerID: .alibaba,
            message: lastError?.localizedDescription ?? "Alibaba Coding Plan credentials are not configured.",
            sourceLabel: sourceMode == .apiKey ? "API token" : "Web login",
            attemptedSource: sourceMode.rawValue,
            requestContext: sourceMode == .apiKey
                ? AlibabaRegionSupport.quotaURL(region: region).absoluteString
                : AlibabaRegionSupport.consoleRPCURL(region: region).absoluteString
        )
    }

    private func cookieCandidates() -> [QuotaResolvedCookieCandidate] {
#if os(macOS) && canImport(SweetCookieKit)
        let sessions = AlibabaBrowserCookieImporter.candidateSessions()
#else
        let sessions: [QuotaBrowserCookieSession] = []
#endif
        return QuotaCookieCandidateResolver.candidates(
            providerID: .alibaba,
            envKeys: ["ALIBABA_CODING_PLAN_COOKIE"],
            browserSessions: sessions
        )
    }
}

// MARK: - MiniMax

private enum MiniMaxQuotaError: LocalizedError, Sendable {
    case missingToken
    case missingCookie
    case invalidCredentials
    case apiError(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "MiniMax API token not configured."
        case .missingCookie:
            return "MiniMax session cookie not configured."
        case .invalidCredentials:
            return "MiniMax credentials are invalid or expired."
        case .apiError(let message):
            return "MiniMax API error: \(message)"
        case .parseFailed(let message):
            return "MiniMax usage parsing failed: \(message)"
        }
    }
}

struct MiniMaxCookieOverride: Sendable {
    let cookieHeader: String
    let authorizationToken: String?
    let groupID: String?
}

private enum MiniMaxCookieSupport {
    static func override(from raw: String?) -> MiniMaxCookieOverride? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard let cookieHeader = wave4NormalizedCookieHeader(raw) else { return nil }
        let authorizationToken = firstCapture(pattern: #"(?i)\bauthorization:\s*bearer\s+([A-Za-z0-9._\-+=/]+)"#, in: raw)
        let groupID = firstCapture(pattern: #"(?i)\bgroup[_]?id=([0-9]{4,})"#, in: raw)
        return MiniMaxCookieOverride(cookieHeader: cookieHeader, authorizationToken: authorizationToken, groupID: groupID)
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = text[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }
}

struct MiniMaxQuotaUsageSnapshot: Sendable {
    let planName: String?
    let availablePrompts: Int?
    let currentPrompts: Int?
    let remainingPrompts: Int?
    let windowMinutes: Int?
    let usedPercent: Double?
    let resetsAt: Date?
    let updatedAt: Date

    func toQuotaSnapshot(note: String? = nil) -> QuotaSnapshot {
        QuotaSnapshot(
            providerID: .minimax,
            source: .web,
            primaryWindow: quotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .minimax).primaryLabel,
                usedRatio: usedPercent.map { min(max($0 / 100.0, 0), 1) },
                detail: detailText(),
                resetsAt: resetsAt
            ),
            secondaryWindow: nil,
            tertiaryWindow: nil,
            credits: nil,
            identity: QuotaIdentity(email: nil, organization: nil, plan: planName, detail: nil),
            updatedAt: updatedAt,
            note: note
        )
    }

    private func detailText() -> String? {
        if let availablePrompts, availablePrompts > 0, let windowMinutes, windowMinutes > 0 {
            if windowMinutes % 60 == 0 {
                return "\(availablePrompts) prompts / \(windowMinutes / 60)h"
            }
            return "\(availablePrompts) prompts / \(windowMinutes)m"
        }
        if let currentPrompts, let availablePrompts {
            return "\(currentPrompts) / \(availablePrompts) prompts"
        }
        return nil
    }
}

private enum MiniMaxRegionSupport {
    static func webBaseURL(region: QuotaMiniMaxRegion) -> URL {
        switch region {
        case .global:
            return URL(string: "https://platform.minimax.io")!
        case .chinaMainland:
            return URL(string: "https://platform.minimaxi.com")!
        }
    }

    static func apiBaseURL(region: QuotaMiniMaxRegion) -> URL {
        switch region {
        case .global:
            return URL(string: "https://api.minimax.io")!
        case .chinaMainland:
            return URL(string: "https://api.minimaxi.com")!
        }
    }

    static func codingPlanURL(region: QuotaMiniMaxRegion) -> URL {
        var components = URLComponents(url: webBaseURL(region: region), resolvingAgainstBaseURL: false)!
        components.path = "/user-center/payment/coding-plan"
        components.queryItems = [URLQueryItem(name: "cycle_type", value: "3")]
        return components.url!
    }

    static func remainsURL(region: QuotaMiniMaxRegion) -> URL {
        apiBaseURL(region: region).appendingPathComponent("v1/api/openplatform/coding_plan/remains")
    }
}

private enum MiniMaxSettingsSupport {
    static func apiTokenInfo() -> ResolvedProviderCredential? {
        SavedProviderTokenResolver.tokenInfo(account: Wave4SecretAccounts.minimaxAPI, envKeys: ["MINIMAX_API_KEY"])
    }

    static func cookieInfo() -> ResolvedProviderCredential? {
        guard let info = SavedProviderTokenResolver.tokenInfo(for: .minimax, envKeys: ["MINIMAX_COOKIE", "MINIMAX_COOKIE_HEADER"]),
              let normalized = wave4NormalizedCookieHeader(info.value)
        else {
            return nil
        }
        return ResolvedProviderCredential(value: normalized, sourceLabel: info.sourceLabel)
    }
}

#if os(macOS) && canImport(SweetCookieKit)
private enum MiniMaxBrowserCookieImporter {
    private static let cookieDomains = [
        "platform.minimax.io",
        "openplatform.minimax.io",
        "minimax.io",
        "platform.minimaxi.com",
        "openplatform.minimaxi.com",
        "minimaxi.com",
    ]

    static func candidateSessions() -> [QuotaBrowserCookieSession] {
        QuotaBrowserCookieImporter.candidateSessions(
            domains: cookieDomains,
            browserOrder: Browser.defaultImportOrder,
            requiredCookieNames: nil,
            allowDomainFallback: true
        )
    }
}
#endif

enum MiniMaxUsageFetcher {
    static func fetchUsage(apiToken: String, region: QuotaMiniMaxRegion, now: Date = Date()) async throws -> MiniMaxQuotaUsageSnapshot {
        var request = URLRequest(url: MiniMaxRegionSupport.remainsURL(region: region))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw MiniMaxQuotaError.invalidCredentials
            }
            throw MiniMaxQuotaError.apiError("HTTP \(response.statusCode)")
        }
        return try parseRemains(data: data, now: now)
    }

    static func fetchUsage(cookie: MiniMaxCookieOverride, region: QuotaMiniMaxRegion, now: Date = Date()) async throws -> MiniMaxQuotaUsageSnapshot {
        var request = URLRequest(url: MiniMaxRegionSupport.codingPlanURL(region: region))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(cookie.cookieHeader, forHTTPHeaderField: "Cookie")
        if let authorizationToken = cookie.authorizationToken {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue(MiniMaxRegionSupport.webBaseURL(region: region).absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(MiniMaxRegionSupport.codingPlanURL(region: region).absoluteString, forHTTPHeaderField: "Referer")

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw MiniMaxQuotaError.invalidCredentials
            }
            throw MiniMaxQuotaError.apiError("HTTP \(response.statusCode)")
        }

        if response.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json") == true {
            return try parseRemains(data: data, now: now)
        }
        let html = String(decoding: data, as: UTF8.self)
        return try parseHTML(html: html, now: now)
    }

    static func parseRemains(data: Data, now: Date = Date()) throws -> MiniMaxQuotaUsageSnapshot {
        let object = try JSONSerialization.jsonObject(with: data)
        let dictionaries = Wave4JSONLookup.allDictionaries(in: object)

        let total = Wave4JSONLookup.firstInt(in: dictionaries, keys: ["current_interval_total_count", "currentIntervalTotalCount"])
        let remaining = Wave4JSONLookup.firstInt(in: dictionaries, keys: ["current_interval_usage_count", "currentIntervalUsageCount"])
        let usedPercent: Double? = {
            guard let total, total > 0, let remaining else { return nil }
            return min(100, max(0, Double(max(0, total - remaining)) / Double(total) * 100))
        }()
        let start = Wave4JSONLookup.firstDate(in: dictionaries, keys: ["start_time", "startTime"])
        let end = Wave4JSONLookup.firstDate(in: dictionaries, keys: ["end_time", "endTime"])
        let remains = Wave4JSONLookup.firstInt(in: dictionaries, keys: ["remains_time", "remainsTime"])
        let resetsAt: Date? = if let end, end > now {
            end
        } else if let remains, remains > 0 {
            now.addingTimeInterval(remains > 1_000_000 ? TimeInterval(remains) / 1000.0 : TimeInterval(remains))
        } else {
            nil
        }
        let windowMinutes: Int? = {
            guard let start, let end else { return nil }
            let minutes = Int(end.timeIntervalSince(start) / 60.0)
            return minutes > 0 ? minutes : nil
        }()
        let planName = Wave4JSONLookup.firstString(in: dictionaries, keys: ["current_subscribe_title", "currentSubscribeTitle", "plan_name", "planName", "combo_title", "comboTitle"])

        guard total != nil || usedPercent != nil || planName != nil else {
            throw MiniMaxQuotaError.parseFailed("Missing coding plan data.")
        }

        return MiniMaxQuotaUsageSnapshot(
            planName: planName,
            availablePrompts: total,
            currentPrompts: (total != nil && remaining != nil) ? max(0, (total ?? 0) - (remaining ?? 0)) : nil,
            remainingPrompts: remaining,
            windowMinutes: windowMinutes,
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            updatedAt: now
        )
    }

    static func parseHTML(html: String, now: Date = Date()) throws -> MiniMaxQuotaUsageSnapshot {
        if let nextDataJSON = nextDataJSONData(fromHTML: html),
           let snapshot = try? parseRemains(data: nextDataJSON, now: now)
        {
            return snapshot
        }

        let text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let planName = firstCapture(pattern: #"(?i)Coding\s*Plan\s*([A-Za-z0-9][A-Za-z0-9\s._-]{0,32})"#, in: text)
        let availablePrompts = firstCapture(pattern: #"(?i)available\s+usage[:\s]*([0-9][0-9,]*)\s*prompts?"#, in: text)
            .flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
        let duration = firstPairCapture(pattern: #"(?i)available\s+usage[:\s]*[0-9][0-9,]*\s*prompts?\s*/\s*([0-9]+(?:\.[0-9]+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|days?|d)"#, in: text)
        let windowMinutes: Int? = {
            guard let duration, let number = Double(duration.0) else { return nil }
            return duration.1.lowercased().hasPrefix("d")
                ? Int(number * 24.0 * 60.0)
                : duration.1.lowercased().hasPrefix("h")
                    ? Int(number * 60.0)
                    : Int(number)
        }()
        let usedPercent = firstCapture(pattern: #"(?i)([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*used"#, in: text).flatMap(Double.init)

        guard planName != nil || availablePrompts != nil || usedPercent != nil else {
            throw MiniMaxQuotaError.parseFailed("Missing coding plan data.")
        }

        return MiniMaxQuotaUsageSnapshot(
            planName: planName,
            availablePrompts: availablePrompts,
            currentPrompts: nil,
            remainingPrompts: nil,
            windowMinutes: windowMinutes,
            usedPercent: usedPercent,
            resetsAt: nil,
            updatedAt: now
        )
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        let value = text[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }

    private static func firstPairCapture(pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let first = Range(match.range(at: 1), in: text),
              let second = Range(match.range(at: 2), in: text)
        else {
            return nil
        }
        return (
            text[first].trimmingCharacters(in: .whitespacesAndNewlines),
            text[second].trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func nextDataJSONData(fromHTML html: String) -> Data? {
        let marker = #"id="__NEXT_DATA__""#
        guard let markerRange = html.range(of: marker) else { return nil }
        guard let openTagEnd = html[markerRange.upperBound...].firstIndex(of: ">") else { return nil }
        guard let closeRange = html.range(of: "</script>", range: openTagEnd..<html.endIndex) else { return nil }
        let content = html[html.index(after: openTagEnd)..<closeRange.lowerBound]
        guard let data = String(content).data(using: .utf8) else { return nil }
        return data
    }
}

struct MiniMaxQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .minimax)

    func isConfigured() -> Bool {
        let sourceMode = QuotaPreferences.sourcePreference(for: .minimax)
        if sourceMode == .apiKey {
            return MiniMaxSettingsSupport.apiTokenInfo() != nil
        }
        if sourceMode == .web {
            return !cookieCandidates().isEmpty
        }
        return MiniMaxSettingsSupport.apiTokenInfo() != nil || !cookieCandidates().isEmpty
    }

    func fetch() async throws -> QuotaSnapshot {
        try await fetchOutcome().snapshot
    }

    func fetchOutcome() async throws -> QuotaProviderFetchOutcome {
        let sourceMode = QuotaPreferences.sourcePreference(for: .minimax)
        let region = QuotaPreferences.minimaxRegion
        var lastError: Error?
        let storageTokens = sourceMode == .web || sourceMode == .auto
            ? MiniMaxLocalStorageImporter.importAccessTokens()
            : []

        if sourceMode != .web, let apiToken = MiniMaxSettingsSupport.apiTokenInfo() {
            do {
                let snapshot = try await MiniMaxUsageFetcher.fetchUsage(apiToken: apiToken.value, region: region)
                return QuotaProviderFetchOutcome(
                    snapshot: snapshot.toQuotaSnapshot(note: apiToken.sourceLabel),
                    sourceLabel: apiToken.sourceLabel,
                    debugProbe: wave4DebugProbe(
                        providerID: .minimax,
                        attemptedSource: "api",
                        resolvedSource: "api",
                        provenanceLabel: apiToken.sourceLabel,
                        requestContext: MiniMaxRegionSupport.remainsURL(region: region).absoluteString,
                        lastValidation: "MiniMax API remains payload accepted."
                    )
                )
            } catch {
                lastError = error
                if sourceMode == .apiKey {
                    throw wave4Failure(
                        providerID: .minimax,
                        message: error.localizedDescription,
                        sourceLabel: apiToken.sourceLabel,
                        attemptedSource: "api",
                        resolvedSource: "api",
                        provenanceLabel: apiToken.sourceLabel,
                        requestContext: MiniMaxRegionSupport.remainsURL(region: region).absoluteString
                    )
                }
            }
        }

        if sourceMode != .apiKey {
            let candidates = cookieCandidates()
            for candidate in candidates {
                let allowStorageFallback = QuotaPreferences.webCredentialMode(for: .minimax) != .manual && candidate.sourceKind != .manual
                let cookieOverrides = enrichedCookieOverrides(
                    for: candidate,
                    storageTokens: storageTokens,
                    allowStorageFallback: allowStorageFallback
                )
                for cookie in cookieOverrides {
                    do {
                        let snapshot = try await MiniMaxUsageFetcher.fetchUsage(cookie: cookie, region: region)
                        if candidate.shouldCacheOnSuccess {
                            QuotaCookieCache.store(providerID: .minimax, cookieHeader: candidate.cookieHeader, sourceLabel: candidate.provenanceLabel)
                        }
                        return QuotaProviderFetchOutcome(
                            snapshot: snapshot.toQuotaSnapshot(note: candidate.provenanceLabel),
                            sourceLabel: candidate.sourceLabel,
                            debugProbe: wave4DebugProbe(
                                providerID: .minimax,
                                attemptedSource: candidate.sourceKind.rawValue,
                                resolvedSource: candidate.sourceKind.rawValue,
                                provenanceLabel: candidate.provenanceLabel,
                                requestContext: MiniMaxRegionSupport.codingPlanURL(region: region).absoluteString,
                                lastValidation: cookie.authorizationToken == nil
                                    ? "MiniMax coding plan payload accepted."
                                    : "MiniMax coding plan payload accepted with local storage token/group fallback."
                            )
                        )
                    } catch {
                        lastError = error
                        if candidate.sourceKind == .cache {
                            QuotaCookieCache.clear(providerID: .minimax)
                        }
                    }
                }
            }
        }

        throw wave4Failure(
            providerID: .minimax,
            message: lastError?.localizedDescription ?? "MiniMax credentials are not configured.",
            sourceLabel: sourceMode == .apiKey ? "API token" : "Web login",
            attemptedSource: sourceMode.rawValue,
            requestContext: sourceMode == .apiKey
                ? MiniMaxRegionSupport.remainsURL(region: region).absoluteString
                : MiniMaxRegionSupport.codingPlanURL(region: region).absoluteString
        )
    }

    private func cookieCandidates() -> [QuotaResolvedCookieCandidate] {
#if os(macOS) && canImport(SweetCookieKit)
        let sessions = MiniMaxBrowserCookieImporter.candidateSessions()
#else
        let sessions: [QuotaBrowserCookieSession] = []
#endif
        return QuotaCookieCandidateResolver.candidates(
            providerID: .minimax,
            envKeys: ["MINIMAX_COOKIE", "MINIMAX_COOKIE_HEADER"],
            browserSessions: sessions
        )
    }

    private func enrichedCookieOverrides(
        for candidate: QuotaResolvedCookieCandidate,
        storageTokens: [MiniMaxLocalStorageTokenInfo],
        allowStorageFallback: Bool
    ) -> [MiniMaxCookieOverride] {
        guard let base = MiniMaxCookieSupport.override(from: candidate.cookieHeader) else {
            return []
        }
        guard allowStorageFallback else {
            return [base]
        }

        let normalizedCandidateLabel = MiniMaxLocalStorageImporter.normalizeSourceLabel(candidate.provenanceLabel)
        let matchingTokens = storageTokens.filter {
            MiniMaxLocalStorageImporter.normalizeSourceLabel($0.sourceLabel) == normalizedCandidateLabel
        }
        let fallbackTokens = matchingTokens.isEmpty ? storageTokens : matchingTokens

        var results: [MiniMaxCookieOverride] = [base]
        for token in fallbackTokens {
            results.append(
                MiniMaxCookieOverride(
                    cookieHeader: base.cookieHeader,
                    authorizationToken: base.authorizationToken ?? token.accessToken,
                    groupID: base.groupID ?? token.groupID
                )
            )
        }

        var seen = Set<String>()
        return results.filter { override in
            let key = "\(override.cookieHeader)|\(override.authorizationToken ?? "")|\(override.groupID ?? "")"
            return seen.insert(key).inserted
        }
    }
}

// MARK: - Factory

enum FactoryQuotaError: LocalizedError, Sendable {
    case missingCookie
    case notLoggedIn
    case apiError(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCookie:
            return "Droid session cookie not configured."
        case .notLoggedIn:
            return "Droid session expired or is not logged in."
        case .apiError(let message):
            return "Droid API error: \(message)"
        case .parseFailed(let message):
            return "Droid usage parsing failed: \(message)"
        }
    }
}

private struct FactoryAuthResponse: Codable, Sendable {
    let organization: FactoryOrganization?
}

private struct FactoryOrganization: Codable, Sendable {
    let name: String?
    let subscription: FactorySubscription?
}

private struct FactorySubscription: Codable, Sendable {
    let factoryTier: String?
    let orbSubscription: FactoryOrbSubscription?
}

private struct FactoryOrbSubscription: Codable, Sendable {
    let plan: FactoryPlan?
}

private struct FactoryPlan: Codable, Sendable {
    let name: String?
}

private struct FactoryUsageResponse: Codable, Sendable {
    let usage: FactoryUsageData?
    let userId: String?
}

private struct FactoryUsageData: Codable, Sendable {
    let startDate: Int64?
    let endDate: Int64?
    let standard: FactoryTokenUsage?
    let premium: FactoryTokenUsage?
}

private struct FactoryTokenUsage: Codable, Sendable {
    let userTokens: Int64?
    let totalAllowance: Int64?
    let usedRatio: Double?
}

private struct FactoryQuotaUsageSnapshot: Sendable {
    let standardUsedRatio: Double
    let premiumUsedRatio: Double
    let periodEnd: Date?
    let planName: String?
    let tier: String?
    let organizationName: String?
    let userID: String?
    let updatedAt: Date

    func toQuotaSnapshot(note: String? = nil) -> QuotaSnapshot {
        let plan = [tier.map { "Factory \($0.capitalized)" }, planName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        return QuotaSnapshot(
            providerID: .factory,
            source: .web,
            primaryWindow: quotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .factory).primaryLabel,
                usedRatio: standardUsedRatio / 100.0,
                detail: periodEnd.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" },
                resetsAt: periodEnd
            ),
            secondaryWindow: quotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .factory).secondaryLabel ?? "Premium",
                usedRatio: premiumUsedRatio / 100.0,
                detail: nil,
                resetsAt: periodEnd
            ),
            tertiaryWindow: nil,
            credits: nil,
            identity: QuotaIdentity(
                email: nil,
                organization: organizationName,
                plan: plan.isEmpty ? nil : plan,
                detail: userID
            ),
            updatedAt: updatedAt,
            note: note
        )
    }
}

#if os(macOS) && canImport(SweetCookieKit)
private enum FactoryBrowserCookieImporter {
    private static let cookieDomains = ["factory.ai", "app.factory.ai", "auth.factory.ai", "api.factory.ai"]
    private static let requiredCookieNames: Set<String> = [
        "wos-session",
        "__Secure-next-auth.session-token",
        "next-auth.session-token",
        "__Secure-authjs.session-token",
        "authjs.session-token",
        "session",
        "access-token",
    ]

    static func candidateSessions() -> [QuotaBrowserCookieSession] {
        QuotaBrowserCookieImporter.candidateSessions(
            domains: cookieDomains,
            browserOrder: Browser.defaultImportOrder,
            requiredCookieNames: requiredCookieNames,
            allowDomainFallback: true
        )
    }
}
#endif

private enum FactoryUsageFetcher {
    static let appBaseURL = URL(string: "https://app.factory.ai")!
    static let authBaseURL = URL(string: "https://auth.factory.ai")!
    static let apiBaseURL = URL(string: "https://api.factory.ai")!
    private static let staleTokenCookieNames: Set<String> = ["access-token", "__recent_auth"]
    private static let sessionCookieNames: Set<String> = ["session", "wos-session"]
    private static let authSessionCookieNames: Set<String> = [
        "__Secure-next-auth.session-token",
        "next-auth.session-token",
        "__Secure-authjs.session-token",
        "authjs.session-token",
    ]

    static func fetchUsage(cookieHeader: String, now: Date = Date()) async throws -> FactoryQuotaUsageSnapshot {
        try await fetchUsage(cookieHeader: cookieHeader, bearerToken: bearerToken(fromHeader: cookieHeader), now: now)
    }

    static func fetchUsage(bearerToken: String, now: Date = Date()) async throws -> FactoryQuotaUsageSnapshot {
        let baseURLs = [apiBaseURL, appBaseURL]
        var lastError: Error?
        for baseURL in baseURLs {
            do {
                return try await fetchUsage(cookieHeader: "", bearerToken: bearerToken, baseURL: baseURL, now: now)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FactoryQuotaError.notLoggedIn
    }

    static func fetchUsage(cookieHeader: String, bearerToken: String?, now: Date = Date()) async throws -> FactoryQuotaUsageSnapshot {
        let baseURLs = baseURLCandidates(fromCookieHeader: cookieHeader, default: appBaseURL)
        var lastError: Error?
        for baseURL in baseURLs {
            do {
                return try await fetchUsageWithRetry(cookieHeader: cookieHeader, bearerToken: bearerToken, baseURL: baseURL, now: now)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FactoryQuotaError.notLoggedIn
    }

    private static func fetchUsageWithRetry(
        cookieHeader: String,
        bearerToken: String?,
        baseURL: URL,
        now: Date
    ) async throws -> FactoryQuotaUsageSnapshot {
        do {
            return try await fetchUsage(cookieHeader: cookieHeader, bearerToken: bearerToken, baseURL: baseURL, now: now)
        } catch let error as FactoryQuotaError {
            if case .notLoggedIn = error, bearerToken != nil {
                return try await fetchUsage(cookieHeader: cookieHeader, bearerToken: nil, baseURL: baseURL, now: now)
            }

            if case let .apiError(message) = error, message.contains("HTTP 409") {
                var lastError: Error = error
                if bearerToken != nil {
                    do {
                        return try await fetchUsage(cookieHeader: cookieHeader, bearerToken: nil, baseURL: baseURL, now: now)
                    } catch {
                        lastError = error
                    }
                }

                let sourceCookies = CookieHeaderNormalizer.pairs(from: cookieHeader).compactMap(makeCookiePairCookie)
                let retries: [(HTTPCookie) -> Bool] = [
                    { !staleTokenCookieNames.contains($0.name) },
                    { !sessionCookieNames.contains($0.name) },
                    { !staleTokenCookieNames.contains($0.name) && !sessionCookieNames.contains($0.name) },
                ]

                for predicate in retries {
                    let filtered = sourceCookies.filter(predicate)
                    guard filtered.count < sourceCookies.count else { continue }
                    let filteredHeader = Self.cookieHeader(from: filtered)
                    do {
                        return try await fetchUsage(
                            cookieHeader: filteredHeader,
                            bearerToken: Self.bearerToken(fromHeader: filteredHeader),
                            baseURL: baseURL,
                            now: now
                        )
                    } catch {
                        lastError = error
                    }
                }

                let authOnly = sourceCookies.filter {
                    authSessionCookieNames.contains($0.name) || $0.name == "__Host-authjs.csrf-token"
                }
                if !authOnly.isEmpty, authOnly.count < sourceCookies.count {
                    let filteredHeader = Self.cookieHeader(from: authOnly)
                    do {
                        return try await fetchUsage(
                            cookieHeader: filteredHeader,
                            bearerToken: Self.bearerToken(fromHeader: filteredHeader),
                            baseURL: baseURL,
                            now: now
                        )
                    } catch {
                        lastError = error
                    }
                }

                throw lastError
            }
            throw error
        }
    }

    private static func fetchUsage(
        cookieHeader: String,
        bearerToken: String?,
        baseURL: URL,
        now: Date
    ) async throws -> FactoryQuotaUsageSnapshot {
        let auth = try await fetchAuthInfo(cookieHeader: cookieHeader, bearerToken: bearerToken, baseURL: baseURL)
        let usage = try await fetchUsageData(cookieHeader: cookieHeader, bearerToken: bearerToken, baseURL: baseURL)
        let periodEnd = usage.usage?.endDate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000.0) }
        return FactoryQuotaUsageSnapshot(
            standardUsedRatio: percent(usage.usage?.standard),
            premiumUsedRatio: percent(usage.usage?.premium),
            periodEnd: periodEnd,
            planName: auth.organization?.subscription?.orbSubscription?.plan?.name,
            tier: auth.organization?.subscription?.factoryTier,
            organizationName: auth.organization?.name,
            userID: usage.userId,
            updatedAt: now
        )
    }

    private static func percent(_ usage: FactoryTokenUsage?) -> Double {
        if let ratio = usage?.usedRatio, ratio.isFinite {
            if ratio >= 0, ratio <= 1.001 {
                return min(100, max(0, ratio * 100.0))
            }
            if ratio >= 0, ratio <= 100.1 {
                return min(100, max(0, ratio))
            }
        }
        guard let used = usage?.userTokens, let allowance = usage?.totalAllowance, allowance > 0 else {
            return 0
        }
        return min(100, max(0, Double(used) / Double(allowance) * 100.0))
    }

    private static func baseURLCandidates(fromCookieHeader cookieHeader: String, default baseURL: URL) -> [URL] {
        let cookieNames = Set(CookieHeaderNormalizer.pairs(from: cookieHeader).map(\.name))
        var candidates: [URL] = []
        if !cookieNames.isDisjoint(with: authSessionCookieNames) {
            candidates.append(authBaseURL)
        }
        candidates.append(apiBaseURL)
        candidates.append(appBaseURL)
        candidates.append(baseURL)

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.absoluteString).inserted }
    }

    static func bearerToken(fromHeader cookieHeader: String) -> String? {
        CookieHeaderNormalizer.pairs(from: cookieHeader)
            .first(where: { $0.name == "access-token" })?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cookieHeader(from cookies: [HTTPCookie]) -> String {
        cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private static func makeCookiePairCookie(_ pair: CookieHeaderNormalizer.Pair) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: "factory.ai",
            .path: "/",
            .name: pair.name,
            .value: pair.value,
        ])
    }

    private static func fetchAuthInfo(cookieHeader: String, bearerToken: String?, baseURL: URL) async throws -> FactoryAuthResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/app/auth/me"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://app.factory.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://app.factory.ai/", forHTTPHeaderField: "Referer")
        request.setValue("web-app", forHTTPHeaderField: "x-factory-client")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw FactoryQuotaError.notLoggedIn
            }
            throw FactoryQuotaError.apiError("HTTP \(response.statusCode)")
        }
        do {
            return try JSONDecoder().decode(FactoryAuthResponse.self, from: data)
        } catch {
            throw FactoryQuotaError.parseFailed("Auth decode failed: \(error.localizedDescription)")
        }
    }

    private static func fetchUsageData(cookieHeader: String, bearerToken: String?, baseURL: URL) async throws -> FactoryUsageResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/organization/subscription/usage"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://app.factory.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://app.factory.ai/", forHTTPHeaderField: "Referer")
        request.setValue("web-app", forHTTPHeaderField: "x-factory-client")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["useCache": true])

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw FactoryQuotaError.notLoggedIn
            }
            throw FactoryQuotaError.apiError("HTTP \(response.statusCode)")
        }
        do {
            return try JSONDecoder().decode(FactoryUsageResponse.self, from: data)
        } catch {
            throw FactoryQuotaError.parseFailed("Usage decode failed: \(error.localizedDescription)")
        }
    }
}

struct FactoryQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .factory)

    func isConfigured() -> Bool {
        let mode = QuotaPreferences.webCredentialMode(for: .factory)
        if mode == .manual {
            return cookieCandidates().contains(where: { $0.sourceKind == .manual })
        }
        return !cookieCandidates().isEmpty
            || FactoryTokenStore.bearerToken() != nil
            || FactoryTokenStore.refreshToken() != nil
            || !FactoryLocalStorageImporter.importWorkOSTokens().isEmpty
            || !FactoryWorkOSAuthenticator.browserCookieCandidates().isEmpty
    }

    func fetch() async throws -> QuotaSnapshot {
        try await fetchOutcome().snapshot
    }

    func fetchOutcome() async throws -> QuotaProviderFetchOutcome {
        let mode = QuotaPreferences.webCredentialMode(for: .factory)
        let candidates = cookieCandidates()
        let requestContext = "https://app.factory.ai/api/organization/subscription/usage"
        guard mode != .manual || !candidates.isEmpty else {
            throw wave4Failure(
                providerID: .factory,
                message: "Droid session cookie not configured.",
                sourceLabel: "Web login",
                attemptedSource: mode.rawValue,
                requestContext: requestContext
            )
        }

        var lastError: Error?
        for candidate in candidates {
            do {
                let snapshot = try await FactoryUsageFetcher.fetchUsage(cookieHeader: candidate.cookieHeader)
                if candidate.shouldCacheOnSuccess {
                    QuotaCookieCache.store(providerID: .factory, cookieHeader: candidate.cookieHeader, sourceLabel: candidate.provenanceLabel)
                }
                if let bearer = FactoryUsageFetcher.bearerToken(fromHeader: candidate.cookieHeader), !bearer.isEmpty {
                    FactoryTokenStore.setBearerToken(bearer, sourceLabel: candidate.provenanceLabel)
                }
                return QuotaProviderFetchOutcome(
                    snapshot: snapshot.toQuotaSnapshot(note: candidate.provenanceLabel),
                    sourceLabel: candidate.sourceLabel,
                    debugProbe: wave4DebugProbe(
                        providerID: .factory,
                        attemptedSource: candidate.sourceKind.rawValue,
                        resolvedSource: candidate.sourceKind.rawValue,
                        provenanceLabel: candidate.provenanceLabel,
                        requestContext: requestContext,
                        lastValidation: "Droid auth and usage payloads accepted."
                    )
                )
            } catch {
                lastError = error
                if candidate.sourceKind == .cache {
                    QuotaCookieCache.clear(providerID: .factory)
                }
            }
        }

        guard mode != .manual else {
            throw wave4Failure(
                providerID: .factory,
                message: lastError?.localizedDescription ?? "Droid session cookie not configured.",
                sourceLabel: "Web login",
                attemptedSource: candidates.map(\.sourceLabel).joined(separator: " -> "),
                requestContext: requestContext
            )
        }

        if let storedBearer = FactoryTokenStore.bearerToken() {
            do {
                let snapshot = try await FactoryUsageFetcher.fetchUsage(bearerToken: storedBearer.value)
                return QuotaProviderFetchOutcome(
                    snapshot: snapshot.toQuotaSnapshot(note: storedBearer.sourceLabel),
                    sourceLabel: storedBearer.sourceLabel,
                    debugProbe: wave4DebugProbe(
                        providerID: .factory,
                        attemptedSource: "stored bearer",
                        resolvedSource: "stored bearer",
                        provenanceLabel: storedBearer.sourceLabel,
                        requestContext: requestContext,
                        lastValidation: "Droid bearer token accepted."
                    )
                )
            } catch {
                lastError = error
                FactoryTokenStore.setBearerToken(nil)
            }
        }

        if let storedRefresh = FactoryTokenStore.refreshToken() {
            do {
                let auth = try await FactoryWorkOSAuthenticator.fetchAccessToken(refreshToken: storedRefresh.value)
                FactoryTokenStore.setBearerToken(auth.access_token, sourceLabel: storedRefresh.sourceLabel)
                if let newRefresh = auth.refresh_token {
                    FactoryTokenStore.setRefreshToken(newRefresh, sourceLabel: storedRefresh.sourceLabel)
                }
                let snapshot = try await FactoryUsageFetcher.fetchUsage(bearerToken: auth.access_token)
                return QuotaProviderFetchOutcome(
                    snapshot: snapshot.toQuotaSnapshot(note: storedRefresh.sourceLabel),
                    sourceLabel: storedRefresh.sourceLabel,
                    debugProbe: wave4DebugProbe(
                        providerID: .factory,
                        attemptedSource: "stored refresh",
                        resolvedSource: "stored refresh",
                        provenanceLabel: storedRefresh.sourceLabel,
                        requestContext: "https://api.workos.com/user_management/authenticate",
                        lastValidation: "WorkOS refresh token accepted."
                    )
                )
            } catch {
                lastError = error
                if FactoryWorkOSAuthenticator.isInvalidGrant(error) || error.localizedDescription.localizedCaseInsensitiveContains("missing refresh token") {
                    FactoryTokenStore.setRefreshToken(nil)
                }
            }
        }

        for token in FactoryLocalStorageImporter.importWorkOSTokens() {
            do {
                if let accessToken = token.accessToken, !accessToken.isEmpty {
                    let snapshot = try await FactoryUsageFetcher.fetchUsage(bearerToken: accessToken)
                    FactoryTokenStore.setBearerToken(accessToken, sourceLabel: "Local storage: \(token.sourceLabel)")
                    FactoryTokenStore.setRefreshToken(token.refreshToken, sourceLabel: "Local storage: \(token.sourceLabel)")
                    return QuotaProviderFetchOutcome(
                        snapshot: snapshot.toQuotaSnapshot(note: "Local storage: \(token.sourceLabel)"),
                        sourceLabel: "Local storage",
                        debugProbe: wave4DebugProbe(
                            providerID: .factory,
                            attemptedSource: "local storage",
                            resolvedSource: "local storage",
                            provenanceLabel: token.sourceLabel,
                            requestContext: requestContext,
                            lastValidation: "Factory local-storage access token accepted."
                        )
                    )
                }

                let auth = try await FactoryWorkOSAuthenticator.fetchAccessToken(
                    refreshToken: token.refreshToken,
                    organizationID: token.organizationID
                )
                FactoryTokenStore.setBearerToken(auth.access_token, sourceLabel: "Local storage: \(token.sourceLabel)")
                FactoryTokenStore.setRefreshToken(auth.refresh_token ?? token.refreshToken, sourceLabel: "Local storage: \(token.sourceLabel)")
                let snapshot = try await FactoryUsageFetcher.fetchUsage(bearerToken: auth.access_token)
                return QuotaProviderFetchOutcome(
                    snapshot: snapshot.toQuotaSnapshot(note: "Local storage: \(token.sourceLabel)"),
                    sourceLabel: "Local storage",
                    debugProbe: wave4DebugProbe(
                        providerID: .factory,
                        attemptedSource: "local storage refresh",
                        resolvedSource: "local storage refresh",
                        provenanceLabel: token.sourceLabel,
                        requestContext: "https://api.workos.com/user_management/authenticate",
                        lastValidation: "Factory local-storage refresh token accepted."
                    )
                )
            } catch {
                lastError = error
            }
        }

        for session in FactoryWorkOSAuthenticator.browserCookieCandidates() {
            do {
                let auth = try await FactoryWorkOSAuthenticator.fetchAccessTokenWithCookies(cookieHeader: session.cookieHeader)
                FactoryTokenStore.setBearerToken(auth.access_token, sourceLabel: "WorkOS cookies: \(session.sourceLabel)")
                if let refresh = auth.refresh_token {
                    FactoryTokenStore.setRefreshToken(refresh, sourceLabel: "WorkOS cookies: \(session.sourceLabel)")
                }
                let snapshot = try await FactoryUsageFetcher.fetchUsage(bearerToken: auth.access_token)
                return QuotaProviderFetchOutcome(
                    snapshot: snapshot.toQuotaSnapshot(note: "WorkOS cookies: \(session.sourceLabel)"),
                    sourceLabel: "WorkOS cookies",
                    debugProbe: wave4DebugProbe(
                        providerID: .factory,
                        attemptedSource: "workos cookies",
                        resolvedSource: "workos cookies",
                        provenanceLabel: session.sourceLabel,
                        requestContext: "https://api.workos.com/user_management/authenticate",
                        lastValidation: "WorkOS browser cookies accepted."
                    )
                )
            } catch {
                lastError = error
            }
        }

        throw wave4Failure(
            providerID: .factory,
            message: lastError?.localizedDescription ?? "Droid session cookie not configured.",
            sourceLabel: "Web login",
            attemptedSource: [
                candidates.map(\.sourceLabel).joined(separator: " -> "),
                "stored bearer",
                "stored refresh",
                "local storage",
                "workos cookies",
            ].filter { !$0.isEmpty }.joined(separator: " -> "),
            requestContext: requestContext
        )
    }

    private func cookieCandidates() -> [QuotaResolvedCookieCandidate] {
#if os(macOS) && canImport(SweetCookieKit)
        let sessions = FactoryBrowserCookieImporter.candidateSessions()
#else
        let sessions: [QuotaBrowserCookieSession] = []
#endif
        return QuotaCookieCandidateResolver.candidates(
            providerID: .factory,
            envKeys: ["FACTORY_COOKIE_HEADER"],
            browserSessions: sessions
        )
    }
}

// MARK: - Ollama

private enum OllamaQuotaError: LocalizedError, Sendable {
    case missingCookie
    case notLoggedIn
    case invalidCredentials
    case parseFailed(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingCookie:
            return "Ollama session cookie not configured."
        case .notLoggedIn:
            return "Not logged in to Ollama."
        case .invalidCredentials:
            return "Ollama session cookie expired."
        case .parseFailed(let message):
            return "Ollama usage parsing failed: \(message)"
        case .apiError(let message):
            return "Ollama request failed: \(message)"
        }
    }
}

struct OllamaQuotaUsageSnapshot: Sendable {
    let planName: String?
    let accountEmail: String?
    let sessionUsedPercent: Double?
    let weeklyUsedPercent: Double?
    let sessionResetsAt: Date?
    let weeklyResetsAt: Date?
    let updatedAt: Date

    func toQuotaSnapshot(note: String? = nil) -> QuotaSnapshot {
        QuotaSnapshot(
            providerID: .ollama,
            source: .web,
            primaryWindow: quotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .ollama).primaryLabel,
                usedRatio: sessionUsedPercent.map { $0 / 100.0 },
                detail: nil,
                resetsAt: sessionResetsAt
            ),
            secondaryWindow: quotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .ollama).secondaryLabel ?? "Weekly",
                usedRatio: weeklyUsedPercent.map { $0 / 100.0 },
                detail: nil,
                resetsAt: weeklyResetsAt
            ),
            tertiaryWindow: nil,
            credits: nil,
            identity: QuotaIdentity(email: accountEmail, organization: nil, plan: planName, detail: nil),
            updatedAt: updatedAt,
            note: note
        )
    }
}

#if os(macOS) && canImport(SweetCookieKit)
private enum OllamaBrowserCookieImporter {
    private static let cookieDomains = ["ollama.com", "www.ollama.com"]
    private static let requiredCookieNames: Set<String> = [
        "session",
        "ollama_session",
        "__Host-ollama_session",
        "__Secure-next-auth.session-token",
        "next-auth.session-token",
    ]
    private static let browserOrder: [Browser] = {
        let defaults = Browser.defaultImportOrder
        let preferred: [Browser] = [.chrome]
        return preferred.filter(defaults.contains) + defaults.filter { !preferred.contains($0) }
    }()

    static func candidateSessions() -> [QuotaBrowserCookieSession] {
        QuotaBrowserCookieImporter.candidateSessions(
            domains: cookieDomains,
            browserOrder: browserOrder,
            requiredCookieNames: requiredCookieNames,
            allowDomainFallback: true
        )
    }
}
#endif

enum OllamaUsageFetcher {
    static func fetchUsage(cookieHeader: String, now: Date = Date()) async throws -> OllamaQuotaUsageSnapshot {
        var request = URLRequest(url: URL(string: "https://ollama.com/settings")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://ollama.com", forHTTPHeaderField: "Origin")
        request.setValue("https://ollama.com/settings", forHTTPHeaderField: "Referer")

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw OllamaQuotaError.invalidCredentials
            }
            throw OllamaQuotaError.apiError("HTTP \(response.statusCode)")
        }
        let html = String(decoding: data, as: UTF8.self)
        return try parseHTML(html: html, now: now)
    }

    static func parseHTML(html: String, now: Date = Date()) throws -> OllamaQuotaUsageSnapshot {
        let lower = html.lowercased()
        let session = parseUsageBlock(labels: ["Session usage", "Hourly usage"], html: html)
        let weekly = parseUsageBlock(labels: ["Weekly usage"], html: html)

        if session == nil, weekly == nil {
            if lower.contains("sign in to ollama") || lower.contains("log in to ollama") || lower.contains("/api/auth/signin") {
                throw OllamaQuotaError.notLoggedIn
            }
            throw OllamaQuotaError.parseFailed("Missing Ollama usage data.")
        }

        return OllamaQuotaUsageSnapshot(
            planName: firstCapture(pattern: #"Cloud Usage\s*</span>\s*<span[^>]*>([^<]+)</span>"#, in: html),
            accountEmail: firstCapture(pattern: #"id=\"header-email\"[^>]*>([^<]+)<"#, in: html),
            sessionUsedPercent: session?.usedPercent,
            weeklyUsedPercent: weekly?.usedPercent,
            sessionResetsAt: session?.resetsAt,
            weeklyResetsAt: weekly?.resetsAt,
            updatedAt: now
        )
    }

    private struct UsageBlock {
        let usedPercent: Double
        let resetsAt: Date?
    }

    private static func parseUsageBlock(labels: [String], html: String) -> UsageBlock? {
        for label in labels {
            guard let labelRange = html.range(of: label) else { continue }
            let tail = String(html[labelRange.upperBound...].prefix(800))
            let percent = firstCapture(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*%\s*used"#, in: tail).flatMap(Double.init)
                ?? firstCapture(pattern: #"width:\s*([0-9]+(?:\.[0-9]+)?)%"#, in: tail).flatMap(Double.init)
            let resetsAt = firstCapture(pattern: #"data-time=\"([^\"]+)\""#, in: tail).flatMap { QuotaUtilities.isoDate($0) }
            if let percent {
                return UsageBlock(usedPercent: percent, resetsAt: resetsAt)
            }
        }
        return nil
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = text[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }
}

struct OllamaQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .ollama)

    func isConfigured() -> Bool {
        !cookieCandidates().isEmpty
    }

    func fetch() async throws -> QuotaSnapshot {
        try await fetchOutcome().snapshot
    }

    func fetchOutcome() async throws -> QuotaProviderFetchOutcome {
        let candidates = cookieCandidates()
        let requestContext = "https://ollama.com/settings"
        guard !candidates.isEmpty else {
            throw wave4Failure(
                providerID: .ollama,
                message: "Ollama session cookie not configured.",
                sourceLabel: "Web login",
                attemptedSource: QuotaPreferences.webCredentialMode(for: .ollama).rawValue,
                requestContext: requestContext
            )
        }

        var lastError: Error?
        for candidate in candidates {
            do {
                let snapshot = try await OllamaUsageFetcher.fetchUsage(cookieHeader: candidate.cookieHeader)
                if candidate.shouldCacheOnSuccess {
                    QuotaCookieCache.store(providerID: .ollama, cookieHeader: candidate.cookieHeader, sourceLabel: candidate.provenanceLabel)
                }
                return QuotaProviderFetchOutcome(
                    snapshot: snapshot.toQuotaSnapshot(note: candidate.provenanceLabel),
                    sourceLabel: candidate.sourceLabel,
                    debugProbe: wave4DebugProbe(
                        providerID: .ollama,
                        attemptedSource: candidate.sourceKind.rawValue,
                        resolvedSource: candidate.sourceKind.rawValue,
                        provenanceLabel: candidate.provenanceLabel,
                        requestContext: requestContext,
                        lastValidation: "Ollama settings page usage accepted."
                    )
                )
            } catch {
                lastError = error
                if candidate.sourceKind == .cache {
                    QuotaCookieCache.clear(providerID: .ollama)
                }
            }
        }

        throw wave4Failure(
            providerID: .ollama,
            message: lastError?.localizedDescription ?? "Ollama session cookie not configured.",
            sourceLabel: "Web login",
            attemptedSource: candidates.map(\.sourceLabel).joined(separator: " -> "),
            requestContext: requestContext
        )
    }

    private func cookieCandidates() -> [QuotaResolvedCookieCandidate] {
#if os(macOS) && canImport(SweetCookieKit)
        let sessions = OllamaBrowserCookieImporter.candidateSessions()
#else
        let sessions: [QuotaBrowserCookieSession] = []
#endif
        return QuotaCookieCandidateResolver.candidates(
            providerID: .ollama,
            envKeys: ["OLLAMA_COOKIE_HEADER"],
            browserSessions: sessions
        )
    }
}
