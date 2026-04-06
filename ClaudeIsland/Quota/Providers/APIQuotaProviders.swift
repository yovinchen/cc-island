//
//  APIQuotaProviders.swift
//  ClaudeIsland
//

import Foundation

enum SavedProviderTokenResolver {
    static func token(for providerID: QuotaProviderID, envKeys: [String]) -> String? {
        let stored = QuotaSecretStore.read(account: QuotaProviderRegistry.secretAccountName(for: providerID))
        return QuotaRuntimeSupport.envValue(envKeys, fallback: stored)
    }
}

private enum QuotaProviderValueLookup {
    static func value(paths: [[String]], contexts: [[String: Any]]) -> Any? {
        for path in paths {
            if let value = self.value(path: path, contexts: contexts) {
                return value
            }
        }
        return nil
    }

    static func value(path: [String], contexts: [[String: Any]]) -> Any? {
        for context in contexts {
            var cursor: Any? = context
            for key in path {
                guard let dict = cursor as? [String: Any] else {
                    cursor = nil
                    break
                }
                cursor = dict[key]
            }
            if cursor != nil {
                return cursor
            }
        }
        return nil
    }

    static func dictionaries(_ raw: Any?) -> [[String: Any]] {
        raw as? [[String: Any]] ?? []
    }
}

func quotaRatio(used: Double?, total: Double?) -> Double? {
    guard let used, let total, total > 0 else { return nil }
    return min(max(used / total, 0), 1)
}

func quotaWindow(
    label: String,
    usedRatio: Double?,
    detail: String? = nil,
    resetsAt: Date? = nil
) -> QuotaWindow? {
    guard let usedRatio else { return nil }
    return QuotaWindow(
        label: label,
        usedRatio: min(max(usedRatio, 0), 1),
        detail: detail,
        resetsAt: resetsAt
    )
}

private struct OpenRouterCreditsResponse: Decodable {
    let data: OpenRouterCreditsData
}

private struct OpenRouterCreditsData: Decodable {
    let totalCredits: Double
    let totalUsage: Double

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }
}

private struct OpenRouterKeyResponse: Decodable {
    let data: OpenRouterKeyData
}

private struct OpenRouterKeyData: Decodable {
    let limit: Double?
    let usage: Double?
    let rateLimit: OpenRouterRateLimit?

    enum CodingKeys: String, CodingKey {
        case limit
        case usage
        case rateLimit = "rate_limit"
    }
}

private struct OpenRouterRateLimit: Decodable {
    let requests: Int
    let interval: String
}

struct OpenRouterQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .openrouter)

    func isConfigured() -> Bool {
        apiKey() != nil
    }

    func fetch() async throws -> QuotaSnapshot {
        guard let apiKey = apiKey() else {
            throw QuotaProviderError.missingCredentials("OpenRouter API token not configured.")
        }

        let credits = try await fetchCredits(apiKey: apiKey)
        let balance = max(0, credits.totalCredits - credits.totalUsage)
        let keyData = try? await fetchKeyData(apiKey: apiKey)

        let primaryWindow = quotaWindow(
            label: descriptor.primaryLabel,
            usedRatio: quotaRatio(used: keyData?.usage, total: keyData?.limit),
            detail: {
                guard let usage = keyData?.usage, let limit = keyData?.limit, limit > 0 else { return nil }
                return String(format: "%.0f / %.0f used", usage, limit)
            }(),
            resetsAt: nil
        )

        let note: String? = {
            guard let rateLimit = keyData?.rateLimit else { return nil }
            return "Rate limit: \(rateLimit.requests) requests / \(rateLimit.interval)"
        }()

        return QuotaSnapshot(
            providerID: .openrouter,
            source: .apiKey,
            primaryWindow: primaryWindow,
            secondaryWindow: nil,
            tertiaryWindow: nil,
            credits: QuotaCredits(
                label: "Credits",
                used: credits.totalUsage,
                total: credits.totalCredits,
                remaining: balance,
                currencyCode: "USD",
                isUnlimited: false
            ),
            identity: QuotaIdentity(
                email: nil,
                organization: nil,
                plan: nil,
                detail: String(format: "Balance: $%.2f", balance)
            ),
            updatedAt: Date(),
            note: note
        )
    }

    private func apiKey() -> String? {
        SavedProviderTokenResolver.token(for: .openrouter, envKeys: ["OPENROUTER_API_KEY"])
    }

    private func baseURL() -> URL {
        let raw = QuotaRuntimeSupport.envValue(["OPENROUTER_API_URL"]) ?? "https://openrouter.ai/api/v1"
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmed + "/")!
    }

    private func fetchCredits(apiKey: String) async throws -> OpenRouterCreditsData {
        var request = URLRequest(url: baseURL().appendingPathComponent("credits"))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            throw QuotaProviderError.invalidResponse("OpenRouter credits API returned HTTP \(response.statusCode)")
        }
        return try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data).data
    }

    private func fetchKeyData(apiKey: String) async throws -> OpenRouterKeyData {
        var request = URLRequest(url: baseURL().appendingPathComponent("key"))
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            throw QuotaProviderError.invalidResponse("OpenRouter key API returned HTTP \(response.statusCode)")
        }
        return try JSONDecoder().decode(OpenRouterKeyResponse.self, from: data).data
    }
}

struct WarpQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .warp)

    func isConfigured() -> Bool {
        apiKey() != nil
    }

    func fetch() async throws -> QuotaSnapshot {
        guard let apiKey = apiKey() else {
            throw QuotaProviderError.missingCredentials("Warp API key not configured.")
        }

        var request = URLRequest(url: URL(string: "https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("warp-app", forHTTPHeaderField: "x-warp-client-id")
        request.setValue("Warp/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("macOS", forHTTPHeaderField: "x-warp-os-category")
        request.setValue("macOS", forHTTPHeaderField: "x-warp-os-name")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let osVersion = Foundation.ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        request.setValue(osVersionString, forHTTPHeaderField: "x-warp-os-version")

        let body: [String: Any] = [
            "query": Self.graphQLQuery,
            "variables": [
                "requestContext": [
                    "clientContext": [:] as [String: Any],
                    "osContext": [
                        "category": "macOS",
                        "name": "macOS",
                        "version": osVersionString,
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
            "operationName": "GetRequestLimitInfo",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            throw QuotaProviderError.invalidResponse("Warp API returned HTTP \(response.statusCode)")
        }

        let json = try QuotaRuntimeSupport.jsonObject(from: data)
        if let rawErrors = json["errors"] as? [[String: Any]], !rawErrors.isEmpty {
            let summary = rawErrors.compactMap { QuotaRuntimeSupport.stringValue($0["message"]) }.joined(separator: " | ")
            throw QuotaProviderError.invalidResponse(summary.isEmpty ? "Warp GraphQL request failed." : summary)
        }

        guard let requestInfo = Self.requestLimitInfo(from: json) else {
            throw QuotaProviderError.invalidResponse("Warp response is missing requestLimitInfo.")
        }

        let isUnlimited = (requestInfo["isUnlimited"] as? Bool) ?? false
        let requestLimit = QuotaRuntimeSupport.intValue(requestInfo["requestLimit"]) ?? 0
        let requestsUsed = QuotaRuntimeSupport.intValue(requestInfo["requestsUsedSinceLastRefresh"]) ?? 0
        let nextRefresh = QuotaUtilities.isoDate(QuotaRuntimeSupport.stringValue(requestInfo["nextRefreshTime"]))

        let grants = Self.bonusGrantEntries(from: json)
        let bonusTotal = grants.reduce(0) { partial, grant in
            partial + (QuotaRuntimeSupport.intValue(grant["requestCreditsGranted"]) ?? 0)
        }
        let bonusRemaining = grants.reduce(0) { partial, grant in
            partial + (QuotaRuntimeSupport.intValue(grant["requestCreditsRemaining"]) ?? 0)
        }
        let nextExpiringGrant = grants
            .filter { (QuotaRuntimeSupport.intValue($0["requestCreditsRemaining"]) ?? 0) > 0 }
            .compactMap { grant -> (Date, Int)? in
                guard let rawExpiration = QuotaRuntimeSupport.stringValue(grant["expiration"]),
                      let expiration = QuotaUtilities.isoDate(rawExpiration)
                else {
                    return nil
                }
                return (expiration, QuotaRuntimeSupport.intValue(grant["requestCreditsRemaining"]) ?? 0)
            }
            .sorted { $0.0 < $1.0 }
            .first

        let primaryWindow = quotaWindow(
            label: descriptor.primaryLabel,
            usedRatio: isUnlimited ? 0 : quotaRatio(used: Double(requestsUsed), total: Double(requestLimit)),
            detail: isUnlimited ? "Unlimited" : "\(requestsUsed)/\(requestLimit) credits",
            resetsAt: isUnlimited ? nil : nextRefresh
        )

        let secondaryWindow = quotaWindow(
            label: descriptor.secondaryLabel ?? "Add-on credits",
            usedRatio: bonusTotal > 0 ? quotaRatio(used: Double(max(0, bonusTotal - bonusRemaining)), total: Double(bonusTotal)) : nil,
            detail: {
                guard bonusTotal > 0 else { return nil }
                if let nextExpiringGrant {
                    return "\(bonusRemaining)/\(bonusTotal) credits • \(nextExpiringGrant.1) expires \(nextExpiringGrant.0.formatted(date: .abbreviated, time: .shortened))"
                }
                return "\(bonusRemaining)/\(bonusTotal) credits"
            }(),
            resetsAt: nextExpiringGrant?.0
        )

        return QuotaSnapshot(
            providerID: .warp,
            source: .apiKey,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: nil,
            credits: nil,
            identity: QuotaIdentity(
                email: nil,
                organization: nil,
                plan: nil,
                detail: isUnlimited ? "Unlimited" : nil
            ),
            updatedAt: Date(),
            note: nil
        )
    }

    private static let graphQLQuery = """
    query GetRequestLimitInfo($requestContext: RequestContext!) {
      user(requestContext: $requestContext) {
        __typename
        ... on UserOutput {
          user {
            requestLimitInfo {
              isUnlimited
              nextRefreshTime
              requestLimit
              requestsUsedSinceLastRefresh
            }
            bonusGrants {
              requestCreditsGranted
              requestCreditsRemaining
              expiration
            }
            workspaces {
              bonusGrantsInfo {
                grants {
                  requestCreditsGranted
                  requestCreditsRemaining
                  expiration
                }
              }
            }
          }
        }
      }
    }
    """

    private func apiKey() -> String? {
        SavedProviderTokenResolver.token(for: .warp, envKeys: ["WARP_API_KEY", "WARP_TOKEN"])
    }

    private static func requestLimitInfo(from root: [String: Any]) -> [String: Any]? {
        (((root["data"] as? [String: Any])?["user"] as? [String: Any])?["user"] as? [String: Any])?["requestLimitInfo"] as? [String: Any]
    }

    private static func bonusGrantEntries(from root: [String: Any]) -> [[String: Any]] {
        var grants: [[String: Any]] = []
        if let user = ((root["data"] as? [String: Any])?["user"] as? [String: Any])?["user"] as? [String: Any] {
            grants.append(contentsOf: QuotaProviderValueLookup.dictionaries(user["bonusGrants"]))

            for workspace in QuotaProviderValueLookup.dictionaries(user["workspaces"]) {
                if let bonusInfo = workspace["bonusGrantsInfo"] as? [String: Any] {
                    grants.append(contentsOf: QuotaProviderValueLookup.dictionaries(bonusInfo["grants"]))
                }
            }
        }
        return grants
    }
}

struct KimiK2QuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .kimiK2)

    func isConfigured() -> Bool {
        apiKey() != nil
    }

    func fetch() async throws -> QuotaSnapshot {
        guard let apiKey = apiKey() else {
            throw QuotaProviderError.missingCredentials("Kimi K2 API key not configured.")
        }

        var request = URLRequest(url: URL(string: "https://kimi-k2.ai/api/user/credits")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            throw QuotaProviderError.invalidResponse("Kimi K2 API returned HTTP \(response.statusCode)")
        }

        let root = try QuotaRuntimeSupport.jsonObject(from: data)
        let contexts = Self.contexts(from: root)
        let consumed = QuotaRuntimeSupport.doubleValue(QuotaProviderValueLookup.value(paths: Self.consumedPaths, contexts: contexts)) ?? 0
        let remaining = QuotaRuntimeSupport.doubleValue(QuotaProviderValueLookup.value(paths: Self.remainingPaths, contexts: contexts))
            ?? QuotaRuntimeSupport.doubleValue(response.value(forHTTPHeaderField: "X-Credits-Remaining"))
            ?? 0
        let averageTokens = QuotaRuntimeSupport.doubleValue(QuotaProviderValueLookup.value(paths: Self.averageTokenPaths, contexts: contexts))
        let updatedAt = Self.timestamp(from: contexts) ?? Date()

        let total = max(0, consumed + remaining)
        let credits = QuotaCredits(
            label: "Credits",
            used: consumed,
            total: total > 0 ? total : nil,
            remaining: remaining,
            currencyCode: nil,
            isUnlimited: false
        )

        return QuotaSnapshot(
            providerID: .kimiK2,
            source: .apiKey,
            primaryWindow: quotaWindow(
                label: descriptor.primaryLabel,
                usedRatio: total > 0 ? consumed / total : nil,
                detail: total > 0 ? String(format: "%.0f / %.0f credits used", consumed, total) : nil,
                resetsAt: nil
            ),
            secondaryWindow: nil,
            tertiaryWindow: nil,
            credits: credits,
            identity: QuotaIdentity(
                email: nil,
                organization: nil,
                plan: nil,
                detail: averageTokens.map { "Avg tokens/request: \(Int($0))" }
            ),
            updatedAt: updatedAt,
            note: averageTokens.map { "Average tokens/request: \(Int($0))" }
        )
    }

    private static let consumedPaths: [[String]] = [
        ["total_credits_consumed"],
        ["totalCreditsConsumed"],
        ["total_credits_used"],
        ["totalCreditsUsed"],
        ["credits_consumed"],
        ["creditsConsumed"],
        ["consumedCredits"],
        ["usedCredits"],
        ["total"],
        ["usage", "total"],
        ["usage", "consumed"],
    ]

    private static let remainingPaths: [[String]] = [
        ["credits_remaining"],
        ["creditsRemaining"],
        ["remaining_credits"],
        ["remainingCredits"],
        ["available_credits"],
        ["availableCredits"],
        ["credits_left"],
        ["creditsLeft"],
        ["usage", "credits_remaining"],
        ["usage", "remaining"],
    ]

    private static let averageTokenPaths: [[String]] = [
        ["average_tokens_per_request"],
        ["averageTokensPerRequest"],
        ["average_tokens"],
        ["averageTokens"],
        ["avg_tokens"],
        ["avgTokens"],
    ]

    private static let timestampPaths: [[String]] = [
        ["updated_at"],
        ["updatedAt"],
        ["timestamp"],
        ["time"],
        ["last_update"],
        ["lastUpdated"],
    ]

    private func apiKey() -> String? {
        SavedProviderTokenResolver.token(for: .kimiK2, envKeys: ["KIMI_K2_API_KEY", "KIMI_API_KEY", "KIMI_KEY"])
    }

    private static func contexts(from root: [String: Any]) -> [[String: Any]] {
        var contexts: [[String: Any]] = [root]
        if let data = root["data"] as? [String: Any] {
            contexts.append(data)
            if let usage = data["usage"] as? [String: Any] {
                contexts.append(usage)
            }
            if let credits = data["credits"] as? [String: Any] {
                contexts.append(credits)
            }
        }
        if let result = root["result"] as? [String: Any] {
            contexts.append(result)
            if let usage = result["usage"] as? [String: Any] {
                contexts.append(usage)
            }
            if let credits = result["credits"] as? [String: Any] {
                contexts.append(credits)
            }
        }
        if let usage = root["usage"] as? [String: Any] {
            contexts.append(usage)
        }
        if let credits = root["credits"] as? [String: Any] {
            contexts.append(credits)
        }
        return contexts
    }

    private static func timestamp(from contexts: [[String: Any]]) -> Date? {
        for path in timestampPaths {
            if let raw = QuotaProviderValueLookup.value(paths: [path], contexts: contexts) {
                if let millis = QuotaRuntimeSupport.doubleValue(raw), millis > 10_000 {
                    return Date(timeIntervalSince1970: millis / 1000.0)
                }
                if let iso = QuotaRuntimeSupport.stringValue(raw) {
                    if let date = QuotaUtilities.isoDate(iso) {
                        return date
                    }
                }
            }
        }
        return nil
    }
}

struct ZAIQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .zai)

    func isConfigured() -> Bool {
        apiKey() != nil
    }

    func fetch() async throws -> QuotaSnapshot {
        guard let apiKey = apiKey() else {
            throw QuotaProviderError.missingCredentials("z.ai API key not configured.")
        }

        var request = URLRequest(url: endpointURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200 else {
            throw QuotaProviderError.invalidResponse("z.ai API returned HTTP \(response.statusCode)")
        }

        let root = try QuotaRuntimeSupport.jsonObject(from: data)
        let success = (root["success"] as? Bool) ?? ((root["code"] as? Int) == 200)
        guard success else {
            let message = QuotaRuntimeSupport.stringValue(root["msg"]) ?? "z.ai quota request failed."
            throw QuotaProviderError.invalidResponse(message)
        }

        guard let dataObject = root["data"] as? [String: Any] else {
            throw QuotaProviderError.invalidResponse("z.ai response is missing data.")
        }

        let rawLimits = QuotaProviderValueLookup.dictionaries(dataObject["limits"])
        let tokenLimit = rawLimits.first { QuotaRuntimeSupport.stringValue($0["type"]) == "TOKENS_LIMIT" }
        let timeLimit = rawLimits.first { QuotaRuntimeSupport.stringValue($0["type"]) == "TIME_LIMIT" }

        let primarySource = tokenLimit ?? timeLimit
        let primaryWindow = primarySource.flatMap { rawLimit in
            makeWindow(
                label: tokenLimit != nil ? descriptor.primaryLabel : (descriptor.secondaryLabel ?? descriptor.primaryLabel),
                rawLimit: rawLimit,
                fallbackMonthly: tokenLimit == nil
            )
        }
        let secondaryWindow: QuotaWindow? = {
            guard tokenLimit != nil, let timeLimit else { return nil }
            return makeWindow(
                label: descriptor.secondaryLabel ?? "Window",
                rawLimit: timeLimit,
                fallbackMonthly: true
            )
        }()

        let plan = Self.planName(from: dataObject)
        let note = Self.usageDetailNote(from: tokenLimit ?? timeLimit)

        return QuotaSnapshot(
            providerID: .zai,
            source: .apiKey,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: nil,
            credits: nil,
            identity: QuotaIdentity(
                email: nil,
                organization: nil,
                plan: plan,
                detail: nil
            ),
            updatedAt: Date(),
            note: note
        )
    }

    private func apiKey() -> String? {
        SavedProviderTokenResolver.token(for: .zai, envKeys: ["Z_AI_API_KEY"])
    }

    private func endpointURL() -> URL {
        if let fullURL = QuotaRuntimeSupport.envValue(["Z_AI_QUOTA_URL"]) {
            return URL(string: fullURL)!
        }

        if let host = QuotaRuntimeSupport.envValue(["Z_AI_API_HOST"]) {
            let normalizedHost = host.hasPrefix("http://") || host.hasPrefix("https://") ? host : "https://\(host)"
            return URL(string: normalizedHost.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/monitor/usage/quota/limit")!
        }

        return QuotaPreferences.zaiRegion.baseURL.appendingPathComponent("api/monitor/usage/quota/limit")
    }

    private func makeWindow(label: String, rawLimit: [String: Any], fallbackMonthly: Bool) -> QuotaWindow? {
        let usedRatio = Self.usedRatio(from: rawLimit)
        let resetsAt = QuotaRuntimeSupport.dateFromMilliseconds(rawLimit["nextResetTime"])
        return quotaWindow(
            label: label,
            usedRatio: usedRatio,
            detail: Self.windowDetail(from: rawLimit, fallbackMonthly: fallbackMonthly),
            resetsAt: resetsAt
        )
    }

    private static func usedRatio(from rawLimit: [String: Any]) -> Double? {
        let percentage = QuotaRuntimeSupport.doubleValue(rawLimit["percentage"])
        let limit = QuotaRuntimeSupport.doubleValue(rawLimit["usage"])
        let currentValue = QuotaRuntimeSupport.doubleValue(rawLimit["currentValue"])
        let remaining = QuotaRuntimeSupport.doubleValue(rawLimit["remaining"])

        if let limit, limit > 0 {
            if let remaining {
                let usedFromRemaining = limit - remaining
                if let currentValue {
                    return min(max(max(usedFromRemaining, currentValue) / limit, 0), 1)
                }
                return min(max(usedFromRemaining / limit, 0), 1)
            }
            if let currentValue {
                return min(max(currentValue / limit, 0), 1)
            }
        }

        if let percentage {
            let normalized = percentage > 1 ? percentage / 100.0 : percentage
            return min(max(normalized, 0), 1)
        }

        return nil
    }

    private static func windowDetail(from rawLimit: [String: Any], fallbackMonthly: Bool) -> String? {
        let unit = QuotaRuntimeSupport.intValue(rawLimit["unit"]) ?? 0
        let number = QuotaRuntimeSupport.intValue(rawLimit["number"]) ?? 0
        guard number > 0 else {
            return fallbackMonthly ? "Monthly" : nil
        }

        let unitLabel: String?
        switch unit {
        case 1:
            unitLabel = number == 1 ? "day" : "days"
        case 3:
            unitLabel = number == 1 ? "hour" : "hours"
        case 5:
            unitLabel = number == 1 ? "minute" : "minutes"
        default:
            unitLabel = nil
        }

        guard let unitLabel else {
            return fallbackMonthly ? "Monthly" : nil
        }
        return "\(number) \(unitLabel) window"
    }

    private static func usageDetailNote(from rawLimit: [String: Any]?) -> String? {
        guard let rawLimit,
              let usageDetails = rawLimit["usageDetails"] as? [[String: Any]],
              !usageDetails.isEmpty
        else {
            return nil
        }

        let topEntries = usageDetails.prefix(2).compactMap { detail -> String? in
            guard let model = QuotaRuntimeSupport.stringValue(detail["modelCode"]),
                  let usage = QuotaRuntimeSupport.intValue(detail["usage"])
            else {
                return nil
            }
            return "\(model) \(usage)"
        }

        guard !topEntries.isEmpty else { return nil }
        return "Top usage: " + topEntries.joined(separator: " • ")
    }

    private static func planName(from dataObject: [String: Any]) -> String? {
        [
            QuotaRuntimeSupport.stringValue(dataObject["planName"]),
            QuotaRuntimeSupport.stringValue(dataObject["plan"]),
            QuotaRuntimeSupport.stringValue(dataObject["plan_type"]),
            QuotaRuntimeSupport.stringValue(dataObject["packageName"]),
        ]
        .compactMap { $0 }
        .first
    }
}
