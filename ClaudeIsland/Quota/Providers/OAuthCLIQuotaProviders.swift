//
//  OAuthCLIQuotaProviders.swift
//  ClaudeIsland
//

import Foundation
import Security

// MARK: - Codex

private struct CodexQuotaCredentials {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let accountId: String?
    let lastRefresh: Date?

    var needsRefresh: Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > (8 * 24 * 60 * 60)
    }
}

private enum CodexQuotaCredentialsStore {
    private static let refreshEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    static func authFileURL() -> URL {
        if let codexHome = QuotaRuntimeSupport.envValue(["CODEX_HOME"]) {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")
    }

    static func hasAuthFile() -> Bool {
        FileManager.default.fileExists(atPath: authFileURL().path)
    }

    static func load() throws -> CodexQuotaCredentials {
        let url = authFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw QuotaProviderError.missingCredentials("Codex auth.json not found.")
        }

        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaProviderError.invalidResponse("Codex auth.json is invalid.")
        }

        if let apiKey = QuotaRuntimeSupport.stringValue(root["OPENAI_API_KEY"]) {
            return CodexQuotaCredentials(
                accessToken: apiKey,
                refreshToken: "",
                idToken: nil,
                accountId: nil,
                lastRefresh: nil
            )
        }

        guard let tokens = root["tokens"] as? [String: Any],
              let accessToken = QuotaRuntimeSupport.stringValue(tokens["access_token"] ?? tokens["accessToken"]),
              let refreshToken = QuotaRuntimeSupport.stringValue(tokens["refresh_token"] ?? tokens["refreshToken"])
        else {
            throw QuotaProviderError.invalidResponse("Codex auth.json does not contain OAuth tokens.")
        }

        return CodexQuotaCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: QuotaRuntimeSupport.stringValue(tokens["id_token"] ?? tokens["idToken"]),
            accountId: QuotaRuntimeSupport.stringValue(tokens["account_id"] ?? tokens["accountId"]),
            lastRefresh: QuotaUtilities.isoDate(QuotaRuntimeSupport.stringValue(root["last_refresh"]))
        )
    }

    static func refresh(_ credentials: CodexQuotaCredentials) async throws -> CodexQuotaCredentials {
        guard !credentials.refreshToken.isEmpty else {
            return credentials
        }

        var request = URLRequest(url: refreshEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ])

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw QuotaProviderError.unauthorized("Codex token refresh failed. Run `codex` to sign in again.")
        }

        let refreshed = CodexQuotaCredentials(
            accessToken: QuotaRuntimeSupport.stringValue(json["access_token"]) ?? credentials.accessToken,
            refreshToken: QuotaRuntimeSupport.stringValue(json["refresh_token"]) ?? credentials.refreshToken,
            idToken: QuotaRuntimeSupport.stringValue(json["id_token"]) ?? credentials.idToken,
            accountId: credentials.accountId,
            lastRefresh: Date()
        )

        try save(refreshed)
        return refreshed
    }

    static func save(_ credentials: CodexQuotaCredentials) throws {
        let url = authFileURL()
        var root: [String: Any] = [:]
        if let existing = try? Data(contentsOf: url),
           let existingRoot = try? JSONSerialization.jsonObject(with: existing) as? [String: Any]
        {
            root = existingRoot
        }

        var tokens: [String: Any] = [
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken,
        ]
        if let idToken = credentials.idToken {
            tokens["id_token"] = idToken
        }
        if let accountId = credentials.accountId {
            tokens["account_id"] = accountId
        }

        root["tokens"] = tokens
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

private struct CodexQuotaUsageResponse: Decodable {
    let planType: PlanType?
    let rateLimit: RateLimitDetails?
    let credits: CreditDetails?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    struct RateLimitDetails: Decodable {
        let primaryWindow: WindowSnapshot?
        let secondaryWindow: WindowSnapshot?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct WindowSnapshot: Decodable {
        let usedPercent: Double
        let resetAt: Int
        let limitWindowSeconds: Int

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    struct CreditDetails: Decodable {
        let hasCredits: Bool
        let unlimited: Bool
        let balance: Double?

        enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
            case balance
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.hasCredits = (try? container.decode(Bool.self, forKey: .hasCredits)) ?? false
            self.unlimited = (try? container.decode(Bool.self, forKey: .unlimited)) ?? false
            if let balance = try? container.decode(Double.self, forKey: .balance) {
                self.balance = balance
            } else if let balance = try? container.decode(String.self, forKey: .balance),
                      let value = Double(balance)
            {
                self.balance = value
            } else {
                self.balance = nil
            }
        }
    }

    enum PlanType: Decodable {
        case raw(String)

        var rawValue: String {
            switch self {
            case .raw(let value):
                return value
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self = .raw(try container.decode(String.self))
        }
    }
}

private enum CodexQuotaUsageFetcher {
    nonisolated private static let defaultChatGPTBaseURL = "https://chatgpt.com/backend-api/"
    nonisolated private static let chatGPTUsagePath = "/wham/usage"
    nonisolated private static let codexUsagePath = "/api/codex/usage"

    static func fetchUsage(_ credentials: CodexQuotaCredentials) async throws -> CodexQuotaUsageResponse {
        var request = URLRequest(url: resolveUsageURL())
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeIsland", forHTTPHeaderField: "User-Agent")
        if let accountId = credentials.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        switch response.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(CodexQuotaUsageResponse.self, from: data)
            } catch {
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let snippet = body.map { String($0.prefix(220)) } ?? "<non-utf8>"
                throw QuotaProviderError.invalidResponse("Codex usage API returned unexpected JSON. \(snippet)")
            }
        case 401, 403:
            throw QuotaProviderError.unauthorized("Codex OAuth token expired or invalid.")
        default:
            throw QuotaProviderError.invalidResponse("Codex usage API returned HTTP \(response.statusCode)")
        }
    }

    nonisolated private static func resolveUsageURL() -> URL {
        let baseURL = resolveChatGPTBaseURL()
        let normalized = normalizeChatGPTBaseURL(baseURL)
        let path = normalized.contains("/backend-api") ? chatGPTUsagePath : codexUsagePath
        let fullURL = normalized + path
        return URL(string: fullURL) ?? URL(string: defaultChatGPTBaseURL + chatGPTUsagePath)!
    }

    nonisolated private static func resolveChatGPTBaseURL() -> String {
        if let contents = loadConfigContents(),
           let parsed = parseChatGPTBaseURL(from: contents)
        {
            return parsed
        }
        return defaultChatGPTBaseURL
    }

    nonisolated private static func normalizeChatGPTBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = defaultChatGPTBaseURL
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if (trimmed.hasPrefix("https://chatgpt.com") || trimmed.hasPrefix("https://chat.openai.com")),
           !trimmed.contains("/backend-api")
        {
            trimmed += "/backend-api"
        }
        return trimmed
    }

    nonisolated private static func parseChatGPTBaseURL(from contents: String) -> String? {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true).first
            let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "chatgpt_base_url" else { continue }

            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            } else if value.hasPrefix("'"), value.hasSuffix("'") {
                value = String(value.dropFirst().dropLast())
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    nonisolated private static func loadConfigContents() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexHome = QuotaRuntimeSupport.envValue(["CODEX_HOME"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = (codexHome?.isEmpty == false)
            ? URL(fileURLWithPath: codexHome!)
            : home.appendingPathComponent(".codex")
        let url = root.appendingPathComponent("config.toml")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    #if DEBUG
    static func _test_resolveUsageURL(configContents: String?) -> URL {
        let baseURL = configContents.flatMap(parseChatGPTBaseURL(from:)) ?? defaultChatGPTBaseURL
        let normalized = normalizeChatGPTBaseURL(baseURL)
        let path = normalized.contains("/backend-api") ? chatGPTUsagePath : codexUsagePath
        return URL(string: normalized + path) ?? URL(string: defaultChatGPTBaseURL + chatGPTUsagePath)!
    }
    #endif
}

#if DEBUG
enum CodexQuotaTestingSupport {
    static func decodeCreditBalance(_ data: Data) throws -> Double? {
        try JSONDecoder().decode(CodexQuotaUsageResponse.CreditDetails.self, from: data).balance
    }

    static func resolveUsageURL(configContents: String?) -> URL {
        CodexQuotaUsageFetcher._test_resolveUsageURL(configContents: configContents)
    }
}
#endif

private struct CodexRPCAccountResponse: Decodable {
    let account: CodexRPCAccountDetails?
}

private enum CodexRPCAccountDetails: Decodable {
    case apiKey
    case chatgpt(email: String, planType: String)

    enum CodingKeys: String, CodingKey {
        case type
        case email
        case planType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type.lowercased() {
        case "apikey":
            self = .apiKey
        case "chatgpt":
            self = .chatgpt(
                email: try container.decodeIfPresent(String.self, forKey: .email) ?? "",
                planType: try container.decodeIfPresent(String.self, forKey: .planType) ?? ""
            )
        default:
            self = .apiKey
        }
    }
}

private struct CodexRPCRateLimitsResponse: Decodable {
    let rateLimits: CodexRPCRateLimitSnapshot
}

private struct CodexRPCRateLimitSnapshot: Decodable {
    let primary: CodexRPCRateLimitWindow?
    let secondary: CodexRPCRateLimitWindow?
    let credits: CodexRPCCreditsSnapshot?
}

private struct CodexRPCRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int?
}

private struct CodexRPCCreditsSnapshot: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

private final class CodexQuotaRPCClient: @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let stdoutLineStream: AsyncStream<Data>
    private let stdoutLineContinuation: AsyncStream<Data>.Continuation
    private var nextID = 1

    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func appendAndDrainLines(_ data: Data) -> [Data] {
            lock.lock()
            defer { lock.unlock() }

            buffer.append(data)
            var lines: [Data] = []
            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)
                if !line.isEmpty {
                    lines.append(line)
                }
            }
            return lines
        }
    }

    init(binaryPath: String) throws {
        var continuation: AsyncStream<Data>.Continuation!
        stdoutLineStream = AsyncStream<Data> { streamContinuation in
            continuation = streamContinuation
        }
        stdoutLineContinuation = continuation

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [binaryPath, "-s", "read-only", "-a", "untrusted", "app-server"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw QuotaProviderError.commandFailed("Failed to launch Codex app-server: \(error.localizedDescription)")
        }

        let buffer = LineBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { [stdoutLineContinuation] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                stdoutLineContinuation.finish()
                return
            }
            for line in buffer.appendAndDrainLines(data) {
                stdoutLineContinuation.yield(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
        }
    }

    func initialize() async throws {
        _ = try await request(method: "initialize", params: [
            "clientInfo": [
                "name": "claude-island",
                "version": "1.0.0",
            ],
        ])
        try sendNotification(method: "initialized")
    }

    func fetchAccount() async throws -> CodexRPCAccountResponse {
        let message = try await request(method: "account/read")
        return try decodeResult(from: message)
    }

    func fetchRateLimits() async throws -> CodexRPCRateLimitsResponse {
        let message = try await request(method: "account/rateLimits/read")
        return try decodeResult(from: message)
    }

    func shutdown() {
        if process.isRunning {
            process.terminate()
        }
    }

    private func request(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        let requestID = nextID
        nextID += 1
        try sendRequest(id: requestID, method: method, params: params)

        while true {
            let message = try await readNextMessage()

            if message["id"] == nil, message["method"] != nil {
                continue
            }

            guard let messageID = jsonID(message["id"]), messageID == requestID else {
                continue
            }

            if let error = message["error"] as? [String: Any],
               let messageText = QuotaRuntimeSupport.stringValue(error["message"])
            {
                throw QuotaProviderError.commandFailed("Codex app-server error: \(messageText)")
            }

            return message
        }
    }

    private func sendNotification(method: String, params: [String: Any]? = nil) throws {
        try sendPayload([
            "method": method,
            "params": params ?? [:],
        ])
    }

    private func sendRequest(id: Int, method: String, params: [String: Any]?) throws {
        try sendPayload([
            "id": id,
            "method": method,
            "params": params ?? [:],
        ])
    }

    private func sendPayload(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        stdinPipe.fileHandleForWriting.write(data)
        stdinPipe.fileHandleForWriting.write(Data([0x0A]))
    }

    private func readNextMessage() async throws -> [String: Any] {
        for await lineData in stdoutLineStream {
            if lineData.isEmpty {
                continue
            }
            if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                return json
            }
        }
        throw QuotaProviderError.invalidResponse("Codex app-server closed stdout unexpectedly.")
    }

    private func decodeResult<T: Decodable>(from message: [String: Any]) throws -> T {
        guard let result = message["result"] else {
            throw QuotaProviderError.invalidResponse("Codex app-server response is missing result.")
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func jsonID(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }
}

struct CodexQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .codex)

    func isConfigured() -> Bool {
        CodexQuotaCredentialsStore.hasAuthFile() || cliBinaryPath() != nil
    }

    func fetch() async throws -> QuotaSnapshot {
        switch QuotaPreferences.sourcePreference(for: .codex) {
        case .cli:
            return try await fetchViaRPC()
        case .oauth:
            let credentials = try CodexQuotaCredentialsStore.load()
            return try await fetchViaOAuth(credentials)
        default:
            break
        }

        if let credentials = try? CodexQuotaCredentialsStore.load() {
            do {
                return try await fetchViaOAuth(credentials)
            } catch {
                if cliBinaryPath() != nil {
                    return try await fetchViaRPC()
                }
                throw error
            }
        }
        return try await fetchViaRPC()
    }

    private func fetchViaOAuth(_ credentials: CodexQuotaCredentials) async throws -> QuotaSnapshot {
        let activeCredentials = if credentials.needsRefresh {
            try await CodexQuotaCredentialsStore.refresh(credentials)
        } else {
            credentials
        }

        let response = try await CodexQuotaUsageFetcher.fetchUsage(activeCredentials)
        let primaryWindow = response.rateLimit?.primaryWindow.map { window in
            QuotaWindow(
                label: descriptor.primaryLabel,
                usedRatio: min(max(window.usedPercent / 100.0, 0), 1),
                detail: nil,
                resetsAt: Date(timeIntervalSince1970: TimeInterval(window.resetAt))
            )
        }
        let secondaryWindow = response.rateLimit?.secondaryWindow.map { window in
            QuotaWindow(
                label: descriptor.secondaryLabel ?? "Weekly",
                usedRatio: min(max(window.usedPercent / 100.0, 0), 1),
                detail: nil,
                resetsAt: Date(timeIntervalSince1970: TimeInterval(window.resetAt))
            )
        }
        let balance = response.credits?.balance
        let identity = QuotaIdentity(
            email: QuotaUtilities.emailFromJWT(activeCredentials.idToken),
            organization: nil,
            plan: response.planType?.rawValue ?? jwtChatGPTPlanType(activeCredentials.idToken),
            detail: nil
        )

        return QuotaSnapshot(
            providerID: .codex,
            source: .oauth,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: nil,
            credits: response.credits.map {
                QuotaCredits(
                    label: "Credits",
                    used: nil,
                    total: nil,
                    remaining: balance,
                    currencyCode: "USD",
                    isUnlimited: $0.unlimited
                )
            },
            identity: identity,
            updatedAt: Date(),
            note: nil
        )
    }

    private func fetchViaRPC() async throws -> QuotaSnapshot {
        guard let binaryPath = cliBinaryPath() else {
            throw QuotaProviderError.commandFailed("codex not found.")
        }

        let rpc = try CodexQuotaRPCClient(binaryPath: binaryPath)
        defer { rpc.shutdown() }

        try await rpc.initialize()
        let limits = try await rpc.fetchRateLimits().rateLimits
        let account = try? await rpc.fetchAccount()

        let primaryWindow = limits.primary.map { window in
            QuotaWindow(
                label: descriptor.primaryLabel,
                usedRatio: min(max(window.usedPercent / 100.0, 0), 1),
                detail: nil,
                resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }
        let secondaryWindow = limits.secondary.map { window in
            QuotaWindow(
                label: descriptor.secondaryLabel ?? "Weekly",
                usedRatio: min(max(window.usedPercent / 100.0, 0), 1),
                detail: nil,
                resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            )
        }

        let identity: QuotaIdentity = {
            switch account?.account {
            case .chatgpt(let email, let planType):
                return QuotaIdentity(
                    email: email.isEmpty ? nil : email,
                    organization: nil,
                    plan: planType.isEmpty ? nil : planType,
                    detail: nil
                )
            default:
                return QuotaIdentity(email: nil, organization: nil, plan: nil, detail: nil)
            }
        }()

        return QuotaSnapshot(
            providerID: .codex,
            source: .cli,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: nil,
            credits: limits.credits.map {
                QuotaCredits(
                    label: "Credits",
                    used: nil,
                    total: nil,
                    remaining: QuotaRuntimeSupport.doubleValue($0.balance),
                    currencyCode: "USD",
                    isUnlimited: $0.unlimited
                )
            },
            identity: identity,
            updatedAt: Date(),
            note: "Source: Codex app-server"
        )
    }

    private func jwtChatGPTPlanType(_ token: String?) -> String? {
        guard let token,
              let payload = QuotaUtilities.decodeJWTClaims(token),
              let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        else {
            return nil
        }
        return QuotaRuntimeSupport.stringValue(auth["chatgpt_plan_type"])
    }

    private func cliBinaryPath() -> String? {
        QuotaRuntimeSupport.resolvedBinary(defaultBinary: "codex", providerID: .codex)
    }
}

// MARK: - Claude

private enum ClaudeCredentialSource {
    case file
    case keychain
}

private struct ClaudeQuotaCredentials {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let scopes: [String]
    let rateLimitTier: String?
    let source: ClaudeCredentialSource

    var isExpired: Bool {
        guard let expiresAt else { return true }
        return Date() >= expiresAt
    }
}

private enum ClaudeQuotaCredentialsStore {
    private static let credentialsPath = ".claude/.credentials.json"
    private static let keychainService = "Claude Code-credentials"
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let refreshEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!

    static func hasCredentials() -> Bool {
        FileManager.default.fileExists(atPath: credentialsFileURL().path) || keychainData() != nil
    }

    static func load() throws -> ClaudeQuotaCredentials {
        if let data = try? Data(contentsOf: credentialsFileURL()) {
            return try parse(data: data, source: .file)
        }
        if let data = keychainData() {
            return try parse(data: data, source: .keychain)
        }
        throw QuotaProviderError.missingCredentials("Claude OAuth credentials not found.")
    }

    static func refresh(_ credentials: ClaudeQuotaCredentials) async throws -> ClaudeQuotaCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            return credentials
        }

        var request = URLRequest(url: refreshEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: oauthClientID),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = QuotaRuntimeSupport.stringValue(json["access_token"])
        else {
            throw QuotaProviderError.unauthorized("Claude OAuth refresh failed. Run `claude` to sign in again.")
        }

        let refreshed = ClaudeQuotaCredentials(
            accessToken: accessToken,
            refreshToken: QuotaRuntimeSupport.stringValue(json["refresh_token"]) ?? refreshToken,
            expiresAt: QuotaRuntimeSupport.doubleValue(json["expires_in"]).map { Date(timeIntervalSinceNow: $0) },
            scopes: credentials.scopes,
            rateLimitTier: credentials.rateLimitTier,
            source: credentials.source
        )

        if refreshed.source == .file {
            try saveToFile(refreshed)
        }
        return refreshed
    }

    private static func credentialsFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(credentialsPath)
    }

    private static func saveToFile(_ credentials: ClaudeQuotaCredentials) throws {
        let url = credentialsFileURL()
        let oauth: [String: Any] = [
            "accessToken": credentials.accessToken,
            "refreshToken": credentials.refreshToken as Any,
            "expiresAt": credentials.expiresAt.map { $0.timeIntervalSince1970 * 1000 } as Any,
            "scopes": credentials.scopes,
            "rateLimitTier": credentials.rateLimitTier as Any,
        ]
        let root = ["claudeAiOauth": oauth]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func keychainData() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private static func parse(data: Data, source: ClaudeCredentialSource) throws -> ClaudeQuotaCredentials {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let accessToken = QuotaRuntimeSupport.stringValue(oauth["accessToken"])
        else {
            throw QuotaProviderError.invalidResponse("Claude OAuth credentials are invalid.")
        }

        let expiresAt = QuotaRuntimeSupport.doubleValue(oauth["expiresAt"]).map {
            Date(timeIntervalSince1970: $0 / 1000.0)
        }

        return ClaudeQuotaCredentials(
            accessToken: accessToken,
            refreshToken: QuotaRuntimeSupport.stringValue(oauth["refreshToken"]),
            expiresAt: expiresAt,
            scopes: oauth["scopes"] as? [String] ?? [],
            rateLimitTier: QuotaRuntimeSupport.stringValue(oauth["rateLimitTier"]),
            source: source
        )
    }
}

private struct ClaudeOAuthUsageResponse: Decodable {
    let fiveHour: ClaudeOAuthUsageWindow?
    let sevenDay: ClaudeOAuthUsageWindow?
    let sevenDayOpus: ClaudeOAuthUsageWindow?
    let sevenDaySonnet: ClaudeOAuthUsageWindow?
    let extraUsage: ClaudeOAuthExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

private struct ClaudeOAuthUsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private struct ClaudeOAuthExtraUsage: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
    }
}

private enum ClaudeQuotaUsageFetcher {
    static func fetchUsage(accessToken: String) async throws -> ClaudeOAuthUsageResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        switch response.statusCode {
        case 200:
            return try JSONDecoder().decode(ClaudeOAuthUsageResponse.self, from: data)
        case 401:
            throw QuotaProviderError.unauthorized("Claude OAuth request unauthorized.")
        default:
            throw QuotaProviderError.invalidResponse("Claude OAuth API returned HTTP \(response.statusCode)")
        }
    }
}

struct ClaudeQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .claude)

    func isConfigured() -> Bool {
        ClaudeQuotaCredentialsStore.hasCredentials() || cliBinaryPath() != nil
    }

    func fetch() async throws -> QuotaSnapshot {
        switch QuotaPreferences.sourcePreference(for: .claude) {
        case .cli:
            return try await fetchViaCLI()
        case .oauth:
            return try await fetchViaOAuth()
        default:
            break
        }

        if ClaudeQuotaCredentialsStore.hasCredentials() {
            do {
                return try await fetchViaOAuth()
            } catch {
                if cliBinaryPath() != nil {
                    return try await fetchViaCLI()
                }
                throw error
            }
        }
        return try await fetchViaCLI()
    }

    private func fetchViaOAuth() async throws -> QuotaSnapshot {
        let credentials = try ClaudeQuotaCredentialsStore.load()
        let activeCredentials = if credentials.isExpired {
            try await ClaudeQuotaCredentialsStore.refresh(credentials)
        } else {
            credentials
        }
        let response = try await ClaudeQuotaUsageFetcher.fetchUsage(accessToken: activeCredentials.accessToken)

        let primaryWindow = response.fiveHour.flatMap { makeWindow(label: descriptor.primaryLabel, window: $0) }
        let weeklyWindow = response.sevenDay ?? response.sevenDaySonnet ?? response.sevenDayOpus
        let secondaryWindow = weeklyWindow.flatMap { makeWindow(label: descriptor.secondaryLabel ?? "Weekly", window: $0) }
        let tertiarySource = response.sevenDayOpus ?? response.sevenDaySonnet
        let tertiaryLabel = response.sevenDayOpus != nil ? "Opus" : "Sonnet"
        let tertiaryWindow = tertiarySource.flatMap { makeWindow(label: tertiaryLabel, window: $0) }

        var noteParts: [String] = []
        if let sonnet = response.sevenDaySonnet?.utilization {
            noteParts.append("Sonnet \(Int((sonnet > 1 ? sonnet / 100.0 : sonnet) * 100))%")
        }
        if let opus = response.sevenDayOpus?.utilization {
            noteParts.append("Opus \(Int((opus > 1 ? opus / 100.0 : opus) * 100))%")
        }
        if let extraUsage = response.extraUsage,
           extraUsage.isEnabled == true,
           let used = extraUsage.usedCredits,
           let limit = extraUsage.monthlyLimit
        {
            noteParts.append(String(format: "Extra usage $%.2f / $%.2f", used, limit))
        }

        return QuotaSnapshot(
            providerID: .claude,
            source: .oauth,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: tertiaryWindow,
            credits: nil,
            identity: QuotaIdentity(
                email: nil,
                organization: nil,
                plan: cleanedPlanName(activeCredentials.rateLimitTier),
                detail: nil
            ),
            updatedAt: Date(),
            note: noteParts.isEmpty ? nil : noteParts.joined(separator: " • ")
        )
    }

    private func fetchViaCLI() async throws -> QuotaSnapshot {
        guard let binaryPath = cliBinaryPath() else {
            throw QuotaProviderError.commandFailed("claude not found.")
        }

        let snapshot = try await ClaudeCLIQuotaProbe(binaryPath: binaryPath).fetch()

        func makeWindow(label: String, percentLeft: Int?, reset: String?) -> QuotaWindow? {
            guard let percentLeft else { return nil }
            let usedRatio = max(0, min(1, Double(100 - percentLeft) / 100.0))
            return QuotaWindow(
                label: label,
                usedRatio: usedRatio,
                detail: nil,
                resetsAt: ClaudeCLIQuotaProbe.parseResetDate(from: reset)
            )
        }

        return QuotaSnapshot(
            providerID: .claude,
            source: .cli,
            primaryWindow: makeWindow(
                label: descriptor.primaryLabel,
                percentLeft: snapshot.sessionPercentLeft,
                reset: snapshot.primaryResetDescription
            ),
            secondaryWindow: makeWindow(
                label: descriptor.secondaryLabel ?? "Weekly",
                percentLeft: snapshot.weeklyPercentLeft,
                reset: snapshot.secondaryResetDescription
            ),
            tertiaryWindow: makeWindow(
                label: "Opus",
                percentLeft: snapshot.opusPercentLeft,
                reset: snapshot.opusResetDescription
            ),
            credits: nil,
            identity: QuotaIdentity(
                email: snapshot.accountEmail,
                organization: snapshot.accountOrganization,
                plan: snapshot.loginMethod,
                detail: nil
            ),
            updatedAt: Date(),
            note: nil
        )
    }

    private func makeWindow(label: String, window: ClaudeOAuthUsageWindow) -> QuotaWindow? {
        guard let utilization = window.utilization else { return nil }
        let usedRatio = utilization > 1 ? utilization / 100.0 : utilization
        return QuotaWindow(
            label: label,
            usedRatio: min(max(usedRatio, 0), 1),
            detail: nil,
            resetsAt: QuotaUtilities.isoDate(window.resetsAt)
        )
    }

    private func cleanedPlanName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func cliBinaryPath() -> String? {
        QuotaRuntimeSupport.resolvedBinary(defaultBinary: "claude", providerID: .claude)
    }
}

// MARK: - Gemini

private enum GeminiAuthType: String {
    case oauthPersonal = "oauth-personal"
    case apiKey = "api-key"
    case vertexAI = "vertex-ai"
    case unknown
}

private struct GeminiOAuthCredentials {
    let accessToken: String?
    let idToken: String?
    let refreshToken: String?
    let expiryDate: Date?
}

private enum GeminiUserTierID: String {
    case free = "free-tier"
    case standard = "standard-tier"
    case legacy = "legacy-tier"
}

private struct GeminiCodeAssistStatus {
    let tier: GeminiUserTierID?
    let projectId: String?
    let tierName: String?
    let paidTierName: String?
    let isGCPManaged: Bool?
    let manageSubscriptionURL: String?
}

private struct GeminiQuotaBucket: Decodable {
    let remainingFraction: Double?
    let resetTime: String?
    let modelId: String?
}

private struct GeminiQuotaResponse: Decodable {
    let buckets: [GeminiQuotaBucket]?
}

private enum GeminiQuotaCredentialsStore {
    private static let credentialsPath = "/.gemini/oauth_creds.json"
    private static let settingsPath = "/.gemini/settings.json"
    private static let tokenRefreshEndpoint = "https://oauth2.googleapis.com/token"

    static func settingsAuthType(homeDirectory: String = NSHomeDirectory()) -> GeminiAuthType {
        let url = URL(fileURLWithPath: homeDirectory + settingsPath)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let security = json["security"] as? [String: Any],
              let auth = security["auth"] as? [String: Any],
              let selectedType = auth["selectedType"] as? String
        else {
            return .unknown
        }
        return GeminiAuthType(rawValue: selectedType) ?? .unknown
    }

    static func hasCredentials() -> Bool {
        let url = URL(fileURLWithPath: NSHomeDirectory() + credentialsPath)
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func load() throws -> GeminiOAuthCredentials {
        let url = URL(fileURLWithPath: NSHomeDirectory() + credentialsPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw QuotaProviderError.missingCredentials("Gemini OAuth credentials not found.")
        }

        guard let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw QuotaProviderError.invalidResponse("Gemini credentials file is invalid.")
        }

        let expiryDate = QuotaRuntimeSupport.doubleValue(json["expiry_date"]).map {
            Date(timeIntervalSince1970: $0 / 1000.0)
        }

        return GeminiOAuthCredentials(
            accessToken: QuotaRuntimeSupport.stringValue(json["access_token"]),
            idToken: QuotaRuntimeSupport.stringValue(json["id_token"]),
            refreshToken: QuotaRuntimeSupport.stringValue(json["refresh_token"]),
            expiryDate: expiryDate
        )
    }

    static func refreshAccessToken(refreshToken: String) async throws -> String {
        guard let oauthClient = extractOAuthClientCredentials() else {
            throw QuotaProviderError.invalidResponse("Could not find Gemini CLI OAuth configuration.")
        }

        guard let url = URL(string: tokenRefreshEndpoint) else {
            throw QuotaProviderError.invalidResponse("Invalid Gemini token refresh URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id=\(oauthClient.clientId)",
            "client_secret=\(oauthClient.clientSecret)",
            "refresh_token=\(refreshToken)",
            "grant_type=refresh_token",
        ]
        .joined(separator: "&")
        .data(using: .utf8)

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        guard response.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = QuotaRuntimeSupport.stringValue(json["access_token"])
        else {
            throw QuotaProviderError.unauthorized("Gemini token refresh failed. Run `gemini` to sign in again.")
        }

        try updateStoredCredentials(refreshResponse: json)
        return accessToken
    }

    fileprivate struct GeminiOAuthClient {
        let clientId: String
        let clientSecret: String
    }

    private static func extractOAuthClientCredentials() -> GeminiOAuthClient? {
        guard let geminiPath = QuotaRuntimeSupport.resolvedBinary(defaultBinary: "gemini", providerID: .gemini) else {
            return nil
        }

        let fileManager = FileManager.default
        var realPath = geminiPath
        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: geminiPath) {
            realPath = destination.hasPrefix("/") ? destination : ((geminiPath as NSString).deletingLastPathComponent + "/" + destination)
        }

        let binDir = (realPath as NSString).deletingLastPathComponent
        let baseDir = (binDir as NSString).deletingLastPathComponent
        let possiblePaths = [
            "\(baseDir)/libexec/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            "\(baseDir)/lib/node_modules/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            "\(baseDir)/share/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            "\(baseDir)/../gemini-cli-core/dist/src/code_assist/oauth2.js",
            "\(baseDir)/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
        ]

        for path in possiblePaths {
            if let content = try? String(contentsOfFile: path, encoding: .utf8),
               let credentials = parseOAuthClientCredentials(from: content)
            {
                return credentials
            }
        }

        let bundleDirectory = "\(baseDir)/bundle"
        if let entries = try? fileManager.contentsOfDirectory(atPath: bundleDirectory) {
            let candidateFiles = entries
                .filter { entry in
                    entry.hasSuffix(".js") && (entry.hasPrefix("chunk-") || entry.hasPrefix("oauth2-provider-") || entry == "gemini.js")
                }
                .sorted()

            for fileName in candidateFiles {
                let path = "\(bundleDirectory)/\(fileName)"
                if let content = try? String(contentsOfFile: path, encoding: .utf8),
                   let credentials = parseOAuthClientCredentials(from: content)
                {
                    return credentials
                }
            }
        }

        return nil
    }

    fileprivate static func parseOAuthClientCredentials(from content: String) -> GeminiOAuthClient? {
        guard let clientId = content.firstMatch(of: /OAUTH_CLIENT_ID\s*=\s*['"]([^'"]+)['"]\s*;/)?.output.1,
              let clientSecret = content.firstMatch(of: /OAUTH_CLIENT_SECRET\s*=\s*['"]([^'"]+)['"]\s*;/)?.output.1
        else {
            return nil
        }
        return GeminiOAuthClient(clientId: String(clientId), clientSecret: String(clientSecret))
    }

    private static func updateStoredCredentials(refreshResponse: [String: Any]) throws {
        let url = URL(fileURLWithPath: NSHomeDirectory() + credentialsPath)
        guard let existing = try? Data(contentsOf: url),
              var json = try JSONSerialization.jsonObject(with: existing) as? [String: Any]
        else {
            return
        }

        json["access_token"] = QuotaRuntimeSupport.stringValue(refreshResponse["access_token"])
        if let expiresIn = QuotaRuntimeSupport.doubleValue(refreshResponse["expires_in"]) {
            json["expiry_date"] = (Date().timeIntervalSince1970 + expiresIn) * 1000
        }
        if let idToken = QuotaRuntimeSupport.stringValue(refreshResponse["id_token"]) {
            json["id_token"] = idToken
        }

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try data.write(to: url, options: .atomic)
    }
}

private enum GeminiQuotaUsageFetcher {
    private static let quotaEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
    private static let loadCodeAssistEndpoint = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    private static let projectsEndpoint = URL(string: "https://cloudresourcemanager.googleapis.com/v1/projects")!

    static func loadCodeAssistStatus(accessToken: String) async -> GeminiCodeAssistStatus {
        var request = URLRequest(url: loadCodeAssistEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"metadata\":{\"ideType\":\"GEMINI_CLI\",\"pluginType\":\"GEMINI\"}}".utf8)

        guard let (data, response) = try? await QuotaRuntimeSupport.data(for: request),
              response.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return GeminiCodeAssistStatus(
                tier: nil,
                projectId: nil,
                tierName: nil,
                paidTierName: nil,
                isGCPManaged: nil,
                manageSubscriptionURL: nil
            )
        }

        let currentTier = json["currentTier"] as? [String: Any]
        let tierID = QuotaRuntimeSupport.stringValue(currentTier?["id"])
        let projectId = parseProjectId(from: json)
        return GeminiCodeAssistStatus(
            tier: tierID.flatMap { GeminiUserTierID(rawValue: $0) },
            projectId: projectId,
            tierName: QuotaRuntimeSupport.stringValue(currentTier?["name"]),
            paidTierName: QuotaRuntimeSupport.stringValue((json["paidTier"] as? [String: Any])?["name"]),
            isGCPManaged: json["gcpManaged"] as? Bool,
            manageSubscriptionURL: QuotaRuntimeSupport.stringValue(json["manageSubscriptionUri"])
        )
    }

    static func discoverProjectId(accessToken: String) async -> String? {
        var request = URLRequest(url: projectsEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await QuotaRuntimeSupport.data(for: request),
              response.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [[String: Any]]
        else {
            return nil
        }

        for project in projects {
            guard let projectId = QuotaRuntimeSupport.stringValue(project["projectId"]) else { continue }
            if projectId.hasPrefix("gen-lang-client") {
                return projectId
            }
            if let labels = project["labels"] as? [String: String],
               labels["generative-language"] != nil
            {
                return projectId
            }
        }

        return nil
    }

    fileprivate static func parseProjectId(from json: [String: Any]) -> String? {
        if let projectId = QuotaRuntimeSupport.stringValue(json["cloudaicompanionProject"]) {
            return projectId
        }
        if let project = json["cloudaicompanionProject"] as? [String: Any] {
            if let id = QuotaRuntimeSupport.stringValue(project["id"]) {
                return id
            }
            if let projectId = QuotaRuntimeSupport.stringValue(project["projectId"]) {
                return projectId
            }
        }
        return QuotaRuntimeSupport.stringValue(json["projectId"])
    }

    static func fetchUsage(accessToken: String, projectId: String?) async throws -> GeminiQuotaResponse {
        var request = URLRequest(url: quotaEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let projectId, !projectId.isEmpty {
            request.httpBody = Data("{\"project\":\"\(projectId)\"}".utf8)
        } else {
            request.httpBody = Data("{}".utf8)
        }

        let (data, response) = try await QuotaRuntimeSupport.data(for: request)
        switch response.statusCode {
        case 200:
            return try JSONDecoder().decode(GeminiQuotaResponse.self, from: data)
        case 401:
            throw QuotaProviderError.unauthorized("Gemini OAuth token expired or invalid.")
        default:
            throw QuotaProviderError.invalidResponse("Gemini quota API returned HTTP \(response.statusCode)")
        }
    }
}

#if DEBUG
enum GeminiQuotaTestingSupport {
    static func extractOAuthClientCredentials(from content: String) -> (clientId: String, clientSecret: String)? {
        guard let credentials = GeminiQuotaCredentialsStore.parseOAuthClientCredentials(from: content) else {
            return nil
        }
        return (credentials.clientId, credentials.clientSecret)
    }

    static func parseProjectId(json: [String: Any]) -> String? {
        GeminiQuotaUsageFetcher.parseProjectId(from: json)
    }
}
#endif

struct GeminiQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .gemini)

    func isConfigured() -> Bool {
        GeminiQuotaCredentialsStore.hasCredentials()
    }

    func fetch() async throws -> QuotaSnapshot {
        switch GeminiQuotaCredentialsStore.settingsAuthType() {
        case .apiKey:
            throw QuotaProviderError.unsupported("Gemini API-key auth is not supported for account quota.")
        case .vertexAI:
            throw QuotaProviderError.unsupported("Gemini Vertex AI auth is not supported for account quota.")
        case .oauthPersonal, .unknown:
            break
        }

        let credentials = try GeminiQuotaCredentialsStore.load()
        guard let accessToken = credentials.accessToken, !accessToken.isEmpty else {
            throw QuotaProviderError.missingCredentials("Gemini access token missing.")
        }

        let initialCodeAssist = await GeminiQuotaUsageFetcher.loadCodeAssistStatus(accessToken: accessToken)
        let initialProjectId: String?
        if let projectId = initialCodeAssist.projectId {
            initialProjectId = projectId
        } else {
            initialProjectId = await GeminiQuotaUsageFetcher.discoverProjectId(accessToken: accessToken)
        }

        let resolved: (token: String, codeAssist: GeminiCodeAssistStatus, response: GeminiQuotaResponse)
        do {
            let response = try await GeminiQuotaUsageFetcher.fetchUsage(accessToken: accessToken, projectId: initialProjectId)
            resolved = (accessToken, initialCodeAssist, response)
        } catch QuotaProviderError.unauthorized(_) {
            guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
                throw QuotaProviderError.unauthorized("Gemini OAuth token expired or invalid.")
            }

            let refreshedToken = try await GeminiQuotaCredentialsStore.refreshAccessToken(refreshToken: refreshToken)
            let refreshedCodeAssist = await GeminiQuotaUsageFetcher.loadCodeAssistStatus(accessToken: refreshedToken)
            let refreshedProjectId: String?
            if let projectId = refreshedCodeAssist.projectId {
                refreshedProjectId = projectId
            } else {
                refreshedProjectId = await GeminiQuotaUsageFetcher.discoverProjectId(accessToken: refreshedToken)
            }
            let refreshedResponse = try await GeminiQuotaUsageFetcher.fetchUsage(accessToken: refreshedToken, projectId: refreshedProjectId)
            resolved = (refreshedToken, refreshedCodeAssist, refreshedResponse)
        }

        let codeAssist = resolved.codeAssist
        let response = resolved.response
        let buckets = response.buckets ?? []
        guard !buckets.isEmpty else {
            throw QuotaProviderError.invalidResponse("Gemini quota API returned no buckets.")
        }

        var bestPerModel: [String: GeminiQuotaBucket] = [:]
        for bucket in buckets {
            guard let modelId = bucket.modelId, bucket.remainingFraction != nil else { continue }
            if let existing = bestPerModel[modelId], (bucket.remainingFraction ?? 1) >= (existing.remainingFraction ?? 1) {
                continue
            }
            bestPerModel[modelId] = bucket
        }

        let ordered = bestPerModel.values.sorted { ($0.modelId ?? "") < ($1.modelId ?? "") }
        let flashLiteBucket = ordered.first { ($0.modelId ?? "").contains("flash-lite") }
        let flashBucket = ordered.first { ($0.modelId ?? "").contains("flash") && !($0.modelId ?? "").contains("flash-lite") }
        let proBucket = ordered.first { bucket in
            let model = bucket.modelId ?? ""
            return !model.contains("flash")
        } ?? flashBucket ?? flashLiteBucket

        let primaryWindow = proBucket.flatMap {
            makeWindow(label: descriptor.primaryLabel, bucket: $0)
        }
        let secondaryWindow = (flashBucket ?? flashLiteBucket).flatMap {
            makeWindow(label: descriptor.secondaryLabel ?? "Flash", bucket: $0)
        }
        let tertiaryWindow: QuotaWindow? = {
            guard let bucket = flashLiteBucket,
                  bucket.modelId != (flashBucket ?? flashLiteBucket)?.modelId
            else {
                return nil
            }
            return makeWindow(label: "Flash Lite", bucket: bucket)
        }()

        let flashLiteNote: String? = {
            guard let flashLiteBucket,
                  flashLiteBucket.modelId != flashBucket?.modelId,
                  let remainingFraction = flashLiteBucket.remainingFraction
            else {
                return nil
            }
            return "Flash Lite \(Int((1 - remainingFraction) * 100))%"
        }()

        return QuotaSnapshot(
            providerID: .gemini,
            source: .oauth,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: tertiaryWindow,
            credits: nil,
            identity: QuotaIdentity(
                email: QuotaUtilities.emailFromJWT(credentials.idToken),
                organization: nil,
                plan: planText(tier: codeAssist.tier, hostedDomain: hostedDomain(from: credentials.idToken)),
                detail: detailText(codeAssist: codeAssist)
            ),
            updatedAt: Date(),
            note: noteText(codeAssist: codeAssist, flashLiteNote: flashLiteNote)
        )
    }

    private func makeWindow(label: String, bucket: GeminiQuotaBucket) -> QuotaWindow? {
        guard let remainingFraction = bucket.remainingFraction else { return nil }
        let usedRatio = min(max(1 - remainingFraction, 0), 1)
        return QuotaWindow(
            label: label,
            usedRatio: usedRatio,
            detail: bucket.modelId,
            resetsAt: QuotaUtilities.isoDate(bucket.resetTime)
        )
    }

    private func hostedDomain(from idToken: String?) -> String? {
        guard let token = idToken,
              let claims = QuotaUtilities.decodeJWTClaims(token)
        else {
            return nil
        }
        return QuotaRuntimeSupport.stringValue(claims["hd"])
    }

    private func planText(tier: GeminiUserTierID?, hostedDomain: String?) -> String? {
        switch (tier, hostedDomain) {
        case (.standard, _):
            return "Paid"
        case (.free, .some):
            return "Workspace"
        case (.free, .none):
            return "Free"
        case (.legacy, _):
            return "Legacy"
        case (.none, _):
            return nil
        }
    }

    private func detailText(codeAssist: GeminiCodeAssistStatus) -> String? {
        var parts: [String] = []
        if let tierName = codeAssist.tierName, !tierName.isEmpty {
            parts.append(tierName)
        }
        if let projectId = codeAssist.projectId, !projectId.isEmpty {
            parts.append("Project \(projectId)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func noteText(codeAssist: GeminiCodeAssistStatus, flashLiteNote: String?) -> String? {
        var notes: [String] = []
        if let flashLiteNote, !flashLiteNote.isEmpty {
            notes.append(flashLiteNote)
        }
        if let paidTierName = codeAssist.paidTierName,
           !paidTierName.isEmpty,
           paidTierName != codeAssist.tierName
        {
            notes.append(paidTierName)
        }
        if let managed = codeAssist.isGCPManaged {
            notes.append(managed ? "Google-managed project" : "User-managed project")
        }
        return notes.isEmpty ? nil : notes.joined(separator: " • ")
    }
}

// MARK: - Kiro

private struct KiroCLICommandResult {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
    let terminatedForIdle: Bool
}

struct KiroQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .kiro)

    func isConfigured() -> Bool {
        binaryPath() != nil
    }

    func fetch() async throws -> QuotaSnapshot {
        try await ensureLoggedIn()
        let output = try await runUsageCommand()
        let snapshot = try parseUsage(output: output)

        let primaryWindow = quotaWindow(
            label: descriptor.primaryLabel,
            usedRatio: snapshot.creditsTotal > 0 ? snapshot.creditsUsed / snapshot.creditsTotal : nil,
            detail: String(format: "%.0f / %.0f covered in plan", snapshot.creditsUsed, snapshot.creditsTotal),
            resetsAt: snapshot.resetsAt
        )
        let bonusDetail: String? = {
            guard let bonusUsed = snapshot.bonusCreditsUsed,
                  let bonusTotal = snapshot.bonusCreditsTotal
            else { return nil }
            if let expiryDays = snapshot.bonusExpiryDays {
                return String(format: "%.0f / %.0f used • expires in %dd", bonusUsed, bonusTotal, expiryDays)
            }
            return String(format: "%.0f / %.0f used", bonusUsed, bonusTotal)
        }()
        let secondaryWindow = quotaWindow(
            label: descriptor.secondaryLabel ?? "Bonus",
            usedRatio: quotaRatio(used: snapshot.bonusCreditsUsed, total: snapshot.bonusCreditsTotal),
            detail: bonusDetail,
            resetsAt: snapshot.bonusExpiryDays.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: Date()) }
        )

        return QuotaSnapshot(
            providerID: .kiro,
            source: .cli,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: nil,
            credits: QuotaCredits(
                label: "Credits",
                used: snapshot.creditsUsed,
                total: snapshot.creditsTotal,
                remaining: max(0, snapshot.creditsTotal - snapshot.creditsUsed),
                currencyCode: nil,
                isUnlimited: false
            ),
            identity: QuotaIdentity(
                email: nil,
                organization: snapshot.planName,
                plan: snapshot.planName,
                detail: nil
            ),
            updatedAt: snapshot.updatedAt,
            note: nil
        )
    }

    private struct Snapshot {
        let planName: String
        let creditsUsed: Double
        let creditsTotal: Double
        let bonusCreditsUsed: Double?
        let bonusCreditsTotal: Double?
        let bonusExpiryDays: Int?
        let resetsAt: Date?
        let updatedAt: Date
    }

    private func ensureLoggedIn() async throws {
        let result = try await runCommand(arguments: ["whoami"], timeout: 5, idleTimeout: 5)
        let combined = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? result.stdout
            : result.stderr
        let normalized = QuotaRuntimeSupport.stripANSI(combined).lowercased()

        if normalized.contains("not logged in") || normalized.contains("login required") {
            throw QuotaProviderError.unauthorized("Not logged in to Kiro. Run `kiro-cli login`.")
        }
        if result.terminationStatus != 0 {
            throw QuotaProviderError.commandFailed(combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func runUsageCommand() async throws -> String {
        let result = try await runCommand(arguments: ["chat", "--no-interactive", "/usage"], timeout: 20, idleTimeout: 10)
        let combined = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? result.stdout
            : result.stderr
        let normalized = QuotaRuntimeSupport.stripANSI(combined).lowercased()

        if normalized.contains("not logged in")
            || normalized.contains("login required")
            || normalized.contains("failed to initialize auth portal")
            || normalized.contains("oauth error")
        {
            throw QuotaProviderError.unauthorized("Not logged in to Kiro. Run `kiro-cli login`.")
        }

        if result.terminatedForIdle, !Self.isUsageOutputComplete(combined) {
            throw QuotaProviderError.commandFailed("Kiro CLI usage command timed out.")
        }

        if combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw QuotaProviderError.commandFailed("Kiro CLI returned no usage output.")
        }

        return combined
    }

    private func runCommand(arguments: [String], timeout: TimeInterval, idleTimeout: TimeInterval) async throws -> KiroCLICommandResult {
        guard let binary = binaryPath() else {
            throw QuotaProviderError.commandFailed("kiro-cli not found.")
        }

        final class ActivityState: @unchecked Sendable {
            private let lock = NSLock()
            nonisolated(unsafe) private var lastActivityAt = Date()
            nonisolated(unsafe) private var hasReceivedOutput = false
            nonisolated(unsafe) private var stdoutData = Data()
            nonisolated(unsafe) private var stderrData = Data()

            nonisolated func appendStdout(_ data: Data) {
                lock.lock()
                defer { lock.unlock() }
                stdoutData.append(data)
                lastActivityAt = Date()
                hasReceivedOutput = true
            }

            nonisolated func appendStderr(_ data: Data) {
                lock.lock()
                defer { lock.unlock() }
                stderrData.append(data)
                lastActivityAt = Date()
                hasReceivedOutput = true
            }

            nonisolated func snapshot() -> (stdout: Data, stderr: Data, lastActivityAt: Date, hasReceivedOutput: Bool) {
                lock.lock()
                defer { lock.unlock() }
                return (stdoutData, stderrData, lastActivityAt, hasReceivedOutput)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = {
            var environment = Foundation.ProcessInfo.processInfo.environment
            environment["TERM"] = "xterm-256color"
            return environment
        }()

        let activity = ActivityState()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                activity.appendStdout(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                activity.appendStderr(data)
            }
        }

        do {
            try process.run()
        } catch {
            throw QuotaProviderError.commandFailed("Failed to launch kiro-cli: \(error.localizedDescription)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let deadline = Date().addingTimeInterval(timeout)
                var terminatedForIdle = false

                while process.isRunning {
                    if Date() >= deadline {
                        process.terminate()
                        process.waitUntilExit()
                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(throwing: QuotaProviderError.commandFailed("Kiro CLI command timed out."))
                        return
                    }

                    let state = activity.snapshot()
                    if state.hasReceivedOutput, Date().timeIntervalSince(state.lastActivityAt) >= idleTimeout {
                        terminatedForIdle = true
                        process.terminate()
                        process.waitUntilExit()
                        break
                    }

                    Thread.sleep(forTimeInterval: 0.1)
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let snapshot = activity.snapshot()
                let stdout = snapshot.stdout + remainingStdout
                let stderr = snapshot.stderr + remainingStderr

                continuation.resume(returning: KiroCLICommandResult(
                    stdout: String(data: stdout, encoding: .utf8) ?? "",
                    stderr: String(data: stderr, encoding: .utf8) ?? "",
                    terminationStatus: process.terminationStatus,
                    terminatedForIdle: terminatedForIdle
                ))
            }
        }
    }

    private func binaryPath() -> String? {
        QuotaRuntimeSupport.resolvedBinary(defaultBinary: "kiro-cli", providerID: .kiro)
    }

    private func parseUsage(output: String) throws -> Snapshot {
        let stripped = QuotaRuntimeSupport.stripANSI(output)
        let lowered = stripped.lowercased()

        if lowered.contains("could not retrieve usage information") {
            throw QuotaProviderError.invalidResponse("Kiro could not retrieve usage information.")
        }

        var planName = "Kiro"
        if let planMatch = stripped.range(of: #"\|\s*(KIRO\s+\w+)"#, options: .regularExpression) {
            planName = String(stripped[planMatch]).replacingOccurrences(of: "|", with: "").trimmingCharacters(in: .whitespaces)
        }
        if let planMatch = stripped.range(of: #"Plan:\s*(.+)"#, options: .regularExpression) {
            let planLine = stripped[planMatch].replacingOccurrences(of: "Plan:", with: "")
            if let firstLine = planLine.split(separator: "\n").first {
                planName = String(firstLine).trimmingCharacters(in: .whitespaces)
            }
        }

        let isManagedPlan = lowered.contains("managed by admin") || lowered.contains("managed by organization")

        var resetsAt: Date?
        if let resetMatch = stripped.range(of: #"resets on (\d{2}/\d{2})"#, options: .regularExpression),
           let dateRange = String(stripped[resetMatch]).range(of: #"\d{2}/\d{2}"#, options: .regularExpression)
        {
            resetsAt = QuotaRuntimeSupport.parseMonthDay(String(String(stripped[resetMatch])[dateRange]))
        }

        var creditsUsed: Double = 0
        var creditsTotal: Double = 50
        var creditsPercent: Double?

        if let creditsMatch = stripped.range(of: #"\((\d+\.?\d*)\s+of\s+(\d+)\s+covered"#, options: .regularExpression) {
            let text = String(stripped[creditsMatch])
            let numbers = text.matches(of: /(\d+\.?\d*)/).map { Double($0.output.1) ?? 0 }
            if numbers.count >= 2 {
                creditsUsed = numbers[0]
                creditsTotal = numbers[1]
            }
        }

        if let percentMatch = stripped.range(of: #"█+\s*(\d+)%"#, options: .regularExpression),
           let rawPercent = String(stripped[percentMatch]).range(of: #"\d+"#, options: .regularExpression)
        {
            creditsPercent = Double(String(String(stripped[percentMatch])[rawPercent]))
        } else if creditsTotal > 0 {
            creditsPercent = (creditsUsed / creditsTotal) * 100.0
        }

        if isManagedPlan, creditsPercent == nil {
            return Snapshot(
                planName: planName,
                creditsUsed: 0,
                creditsTotal: 0,
                bonusCreditsUsed: nil,
                bonusCreditsTotal: nil,
                bonusExpiryDays: nil,
                resetsAt: nil,
                updatedAt: Date()
            )
        }

        guard creditsPercent != nil else {
            throw QuotaProviderError.invalidResponse("Kiro usage output format was not recognized.")
        }

        var bonusUsed: Double?
        var bonusTotal: Double?
        var bonusExpiryDays: Int?
        if let bonusMatch = stripped.range(of: #"Bonus credits:\s*(\d+\.?\d*)/(\d+)"#, options: .regularExpression) {
            let text = String(stripped[bonusMatch])
            let numbers = text.matches(of: /(\d+\.?\d*)/).map { Double($0.output.1) ?? 0 }
            if numbers.count >= 2 {
                bonusUsed = numbers[0]
                bonusTotal = numbers[1]
            }
        }
        if let expiryMatch = stripped.range(of: #"expires in (\d+) days?"#, options: .regularExpression),
           let rawDays = String(stripped[expiryMatch]).range(of: #"\d+"#, options: .regularExpression)
        {
            bonusExpiryDays = Int(String(String(stripped[expiryMatch])[rawDays]))
        }

        return Snapshot(
            planName: planName,
            creditsUsed: creditsUsed,
            creditsTotal: creditsTotal,
            bonusCreditsUsed: bonusUsed,
            bonusCreditsTotal: bonusTotal,
            bonusExpiryDays: bonusExpiryDays,
            resetsAt: resetsAt,
            updatedAt: Date()
        )
    }

    private static func isUsageOutputComplete(_ output: String) -> Bool {
        let normalized = QuotaRuntimeSupport.stripANSI(output).lowercased()
        return normalized.contains("covered in plan")
            || normalized.contains("resets on")
            || normalized.contains("bonus credits")
            || normalized.contains("plan:")
            || normalized.contains("managed by admin")
    }
}
