//
//  Wave3QuotaProviders.swift
//  ClaudeIsland
//

import Foundation

// MARK: - Antigravity

struct AntigravityModelQuota: Sendable {
    let label: String
    let modelID: String
    let remainingFraction: Double?
    let resetTime: Date?

    var remainingPercent: Double {
        guard let remainingFraction else { return 0 }
        return max(0, min(100, remainingFraction * 100))
    }
}

private enum AntigravityModelFamily {
    case claude
    case geminiPro
    case geminiFlash
    case unknown
}

private struct AntigravityNormalizedModel {
    let quota: AntigravityModelQuota
    let family: AntigravityModelFamily
    let selectionPriority: Int?
}

struct AntigravityStatusSnapshot: Sendable {
    let modelQuotas: [AntigravityModelQuota]
    let accountEmail: String?
    let accountPlan: String?

    func toQuotaSnapshot(updatedAt: Date = Date()) throws -> QuotaSnapshot {
        guard !modelQuotas.isEmpty else {
            throw AntigravityStatusProbeError.parseFailed("No quota models available.")
        }

        let normalized = Self.normalizedModels(modelQuotas)
        let primaryQuota = Self.representative(for: .claude, in: normalized)
        let secondaryQuota = Self.representative(for: .geminiPro, in: normalized)
        let tertiaryQuota = Self.representative(for: .geminiFlash, in: normalized)
        let fallbackQuota: AntigravityModelQuota? = if primaryQuota == nil, secondaryQuota == nil, tertiaryQuota == nil {
            Self.fallbackRepresentative(in: normalized)
        } else {
            nil
        }

        func makeWindow(label: String, quota: AntigravityModelQuota?) -> QuotaWindow? {
            guard let quota else { return nil }
            return QuotaWindow(
                label: label,
                usedRatio: max(0, min(1, 1 - (quota.remainingFraction ?? 0))),
                detail: nil,
                resetsAt: quota.resetTime
            )
        }

        return QuotaSnapshot(
            providerID: .antigravity,
            source: .local,
            primaryWindow: makeWindow(label: QuotaProviderRegistry.descriptor(for: .antigravity).primaryLabel, quota: primaryQuota ?? fallbackQuota),
            secondaryWindow: makeWindow(label: QuotaProviderRegistry.descriptor(for: .antigravity).secondaryLabel ?? "Gemini Pro", quota: secondaryQuota),
            tertiaryWindow: makeWindow(label: "Gemini Flash", quota: tertiaryQuota),
            credits: nil,
            identity: QuotaIdentity(
                email: accountEmail,
                organization: nil,
                plan: accountPlan,
                detail: nil
            ),
            updatedAt: updatedAt,
            note: nil
        )
    }

    private static func normalizedModels(_ models: [AntigravityModelQuota]) -> [AntigravityNormalizedModel] {
        models.map { quota in
            let modelID = quota.modelID.lowercased()
            let label = quota.label.lowercased()
            let family = family(forModelID: modelID, label: label)

            let isLite = modelID.contains("lite") || label.contains("lite")
            let isAutocomplete = modelID.contains("autocomplete") || label.contains("autocomplete") || modelID.hasPrefix("tab_")
            let isLowPriorityGeminiPro = modelID.contains("pro-low") || (label.contains("pro") && label.contains("low"))

            let selectionPriority: Int? = switch family {
            case .claude:
                0
            case .geminiPro:
                if isLowPriorityGeminiPro {
                    0
                } else if !isLite, !isAutocomplete {
                    1
                } else {
                    nil
                }
            case .geminiFlash:
                (!isLite && !isAutocomplete) ? 0 : nil
            case .unknown:
                nil
            }

            return AntigravityNormalizedModel(quota: quota, family: family, selectionPriority: selectionPriority)
        }
    }

    private static func representative(
        for family: AntigravityModelFamily,
        in models: [AntigravityNormalizedModel]
    ) -> AntigravityModelQuota? {
        let candidates = models.filter { $0.family == family && $0.selectionPriority != nil }
        guard !candidates.isEmpty else { return nil }
        return candidates.min { lhs, rhs in
            let lhsPriority = lhs.selectionPriority ?? Int.max
            let rhsPriority = rhs.selectionPriority ?? Int.max
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            let lhsHasRemaining = lhs.quota.remainingFraction != nil
            let rhsHasRemaining = rhs.quota.remainingFraction != nil
            if lhsHasRemaining != rhsHasRemaining {
                return lhsHasRemaining && !rhsHasRemaining
            }
            return lhs.quota.remainingPercent < rhs.quota.remainingPercent
        }?.quota
    }

    private static func fallbackRepresentative(in models: [AntigravityNormalizedModel]) -> AntigravityModelQuota? {
        guard !models.isEmpty else { return nil }
        return models.min { lhs, rhs in
            let lhsHasRemaining = lhs.quota.remainingFraction != nil
            let rhsHasRemaining = rhs.quota.remainingFraction != nil
            if lhsHasRemaining != rhsHasRemaining {
                return lhsHasRemaining && !rhsHasRemaining
            }
            if lhs.quota.remainingPercent != rhs.quota.remainingPercent {
                return lhs.quota.remainingPercent < rhs.quota.remainingPercent
            }
            return lhs.quota.label.localizedCaseInsensitiveCompare(rhs.quota.label) == .orderedAscending
        }?.quota
    }

    private static func family(forModelID modelID: String, label: String) -> AntigravityModelFamily {
        let modelFamily = family(from: modelID)
        if modelFamily != .unknown { return modelFamily }
        return family(from: label)
    }

    private static func family(from text: String) -> AntigravityModelFamily {
        if text.contains("claude") { return .claude }
        if text.contains("gemini"), text.contains("pro") { return .geminiPro }
        if text.contains("gemini"), text.contains("flash") { return .geminiFlash }
        return .unknown
    }
}

private enum AntigravityStatusProbeError: LocalizedError, Sendable, Equatable {
    case notRunning
    case missingCSRFToken
    case portDetectionFailed(String)
    case apiError(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Antigravity language server not detected. Launch Antigravity and retry."
        case .missingCSRFToken:
            return "Antigravity CSRF token not found. Restart Antigravity and retry."
        case .portDetectionFailed(let message):
            return "Antigravity port detection failed: \(message)"
        case .apiError(let message):
            return "Antigravity API error: \(message)"
        case .parseFailed(let message):
            return "Could not parse Antigravity quota: \(message)"
        }
    }
}

struct AntigravityStatusProbe: Sendable {
    var timeout: TimeInterval = 8

    private static let processName = "language_server_macos"
    private static let getUserStatusPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"
    private static let commandModelConfigPath = "/exa.language_server_pb.LanguageServerService/GetCommandModelConfigs"
    private static let unleashPath = "/exa.language_server_pb.LanguageServerService/GetUnleashData"

    func isRunningSync() -> Bool {
        (try? Self.detectProcessInfoSync()) != nil
    }

    func fetch() async throws -> AntigravityStatusSnapshot {
        let processInfo = try await Self.detectProcessInfo(timeout: timeout)
        let ports = try await Self.listeningPorts(pid: processInfo.pid, timeout: timeout)
        let connectPort = try await Self.findWorkingPort(ports: ports, csrfToken: processInfo.csrfToken, timeout: timeout)
        let context = RequestContext(
            httpsPort: connectPort,
            httpPort: processInfo.extensionPort,
            csrfToken: processInfo.csrfToken,
            timeout: timeout
        )

        do {
            let response = try await Self.makeRequest(
                payload: RequestPayload(path: Self.getUserStatusPath, body: Self.defaultRequestBody()),
                context: context
            )
            return try Self.parseUserStatusResponse(response)
        } catch {
            let response = try await Self.makeRequest(
                payload: RequestPayload(path: Self.commandModelConfigPath, body: Self.defaultRequestBody()),
                context: context
            )
            return try Self.parseCommandModelResponse(response)
        }
    }

    static func parseUserStatusResponse(_ data: Data) throws -> AntigravityStatusSnapshot {
        let response = try JSONDecoder().decode(AntigravityUserStatusResponse.self, from: data)
        if let invalid = invalidCode(response.code) {
            throw AntigravityStatusProbeError.apiError(invalid)
        }
        guard let userStatus = response.userStatus else {
            throw AntigravityStatusProbeError.parseFailed("Missing userStatus")
        }
        let modelConfigs = userStatus.cascadeModelConfigData?.clientModelConfigs ?? []
        let models = modelConfigs.compactMap(Self.quotaFromConfig(_:))
        let email = userStatus.email
        let planName = userStatus.planStatus?.planInfo?.preferredName
        return AntigravityStatusSnapshot(modelQuotas: models, accountEmail: email, accountPlan: planName)
    }

    static func parseCommandModelResponse(_ data: Data) throws -> AntigravityStatusSnapshot {
        let response = try JSONDecoder().decode(AntigravityCommandModelConfigResponse.self, from: data)
        if let invalid = invalidCode(response.code) {
            throw AntigravityStatusProbeError.apiError(invalid)
        }
        let models = (response.clientModelConfigs ?? []).compactMap(Self.quotaFromConfig(_:))
        return AntigravityStatusSnapshot(modelQuotas: models, accountEmail: nil, accountPlan: nil)
    }

    private struct ProcessInfoResult {
        let pid: Int
        let extensionPort: Int?
        let csrfToken: String
    }

    private struct ProcessLineMatch {
        let pid: Int
        let command: String
    }

    private struct RequestPayload {
        let path: String
        let body: [String: Any]
    }

    private struct RequestContext {
        let httpsPort: Int
        let httpPort: Int?
        let csrfToken: String
        let timeout: TimeInterval
    }

    private static func detectProcessInfoSync() throws -> ProcessInfoResult {
        switch ProcessExecutor.shared.runSync("/bin/ps", arguments: ["-ax", "-o", "pid=,command="]) {
        case .success(let output):
            return try parseProcessInfo(output)
        case .failure:
            throw AntigravityStatusProbeError.notRunning
        }
    }

    private static func detectProcessInfo(timeout: TimeInterval) async throws -> ProcessInfoResult {
        let output = try await runProcess("/bin/ps", arguments: ["-ax", "-o", "pid=,command="], timeout: timeout, label: "antigravity-ps")
        return try parseProcessInfo(output)
    }

    private static func parseProcessInfo(_ output: String) throws -> ProcessInfoResult {
        let lines = output.split(separator: "\n")
        var sawAntigravity = false
        for line in lines {
            let text = String(line)
            guard let match = matchProcessLine(text) else { continue }
            let lower = match.command.lowercased()
            guard lower.contains(processName) else { continue }
            guard isAntigravityCommandLine(lower) else { continue }
            sawAntigravity = true
            guard let token = extractFlag("--csrf_token", from: match.command) else { continue }
            let port = extractPort("--extension_server_port", from: match.command)
            return ProcessInfoResult(pid: match.pid, extensionPort: port, csrfToken: token)
        }
        if sawAntigravity {
            throw AntigravityStatusProbeError.missingCSRFToken
        }
        throw AntigravityStatusProbeError.notRunning
    }

    private static func listeningPorts(pid: Int, timeout: TimeInterval) async throws -> [Int] {
        let lsof = ["/usr/sbin/lsof", "/usr/bin/lsof"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        guard let lsof else {
            throw AntigravityStatusProbeError.portDetectionFailed("lsof not available")
        }
        let output = try await runProcess(lsof, arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(pid)], timeout: timeout, label: "antigravity-lsof")
        let ports = parseListeningPorts(output)
        if ports.isEmpty {
            throw AntigravityStatusProbeError.portDetectionFailed("no listening ports found")
        }
        return ports
    }

    private static func parseListeningPorts(_ output: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var ports: Set<Int> = []
        regex.enumerateMatches(in: output, options: [], range: range) { match, _, _ in
            guard let match,
                  let range = Range(match.range(at: 1), in: output),
                  let value = Int(output[range])
            else { return }
            ports.insert(value)
        }
        return ports.sorted()
    }

    private static func findWorkingPort(ports: [Int], csrfToken: String, timeout: TimeInterval) async throws -> Int {
        for port in ports {
            if await testPortConnectivity(port: port, csrfToken: csrfToken, timeout: timeout) {
                return port
            }
        }
        throw AntigravityStatusProbeError.portDetectionFailed("no working API port found")
    }

    private static func testPortConnectivity(port: Int, csrfToken: String, timeout: TimeInterval) async -> Bool {
        do {
            _ = try await makeRequest(
                payload: RequestPayload(path: unleashPath, body: unleashRequestBody()),
                context: RequestContext(httpsPort: port, httpPort: nil, csrfToken: csrfToken, timeout: timeout)
            )
            return true
        } catch {
            return false
        }
    }

    private static func defaultRequestBody() -> [String: Any] {
        [
            "metadata": [
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "ideVersion": "unknown",
                "locale": "en",
            ],
        ]
    }

    private static func unleashRequestBody() -> [String: Any] {
        [
            "context": [
                "properties": [
                    "devMode": "false",
                    "extensionVersion": "unknown",
                    "hasAnthropicModelAccess": "true",
                    "ide": "antigravity",
                    "ideVersion": "unknown",
                    "installationId": "claudeisland",
                    "language": "UNSPECIFIED",
                    "os": "macos",
                    "requestedModelId": "MODEL_UNSPECIFIED",
                ],
            ],
        ]
    }

    private static func makeRequest(payload: RequestPayload, context: RequestContext) async throws -> Data {
        do {
            return try await sendRequest(scheme: "https", port: context.httpsPort, payload: payload, context: context)
        } catch {
            guard let httpPort = context.httpPort, httpPort != context.httpsPort else {
                throw error
            }
            return try await sendRequest(scheme: "http", port: httpPort, payload: payload, context: context)
        }
    }

    private static func sendRequest(scheme: String, port: Int, payload: RequestPayload, context: RequestContext) async throws -> Data {
        guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)\(payload.path)") else {
            throw AntigravityStatusProbeError.apiError("Invalid URL")
        }
        let body = try JSONSerialization.data(withJSONObject: payload.body, options: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = context.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(context.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = context.timeout
        config.timeoutIntervalForResource = context.timeout
        let session = URLSession(configuration: config, delegate: InsecureAntigravitySessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AntigravityStatusProbeError.apiError("Invalid response")
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw AntigravityStatusProbeError.apiError("HTTP \(http.statusCode): \(message)")
        }
        return data
    }

    private static func runProcess(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval,
        label: String
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await ProcessExecutor.shared.run(executable, arguments: arguments)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AntigravityStatusProbeError.portDetectionFailed("\(label) timed out")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func matchProcessLine(_ line: String) -> ProcessLineMatch? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let pid = Int(parts[0]) else { return nil }
        return ProcessLineMatch(pid: pid, command: String(parts[1]))
    }

    private static func isAntigravityCommandLine(_ command: String) -> Bool {
        if command.contains("--app_data_dir") && command.contains("antigravity") { return true }
        if command.contains("/antigravity/") || command.contains("\\antigravity\\") { return true }
        return false
    }

    private static func extractFlag(_ flag: String, from command: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: flag))[=\\s]+([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = regex.firstMatch(in: command, options: [], range: range),
              let tokenRange = Range(match.range(at: 1), in: command)
        else { return nil }
        return String(command[tokenRange])
    }

    private static func extractPort(_ flag: String, from command: String) -> Int? {
        guard let raw = extractFlag(flag, from: command) else { return nil }
        return Int(raw)
    }

    private static func invalidCode(_ code: AntigravityCodeValue?) -> String? {
        guard let code else { return nil }
        return code.isOK ? nil : code.rawValue
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        if let seconds = Double(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private static func quotaFromConfig(_ config: AntigravityModelConfig) -> AntigravityModelQuota? {
        guard let quota = config.quotaInfo else { return nil }
        return AntigravityModelQuota(
            label: config.label,
            modelID: config.modelOrAlias.model,
            remainingFraction: quota.remainingFraction,
            resetTime: quota.resetTime.flatMap { parseDate($0) }
        )
    }
}

private final class InsecureAntigravitySessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        #if canImport(FoundationNetworking)
        completionHandler(.performDefaultHandling, nil)
        #else
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
        #endif
    }
}

private struct AntigravityUserStatusResponse: Decodable {
    let code: AntigravityCodeValue?
    let userStatus: AntigravityUserStatus?
}

private struct AntigravityCommandModelConfigResponse: Decodable {
    let code: AntigravityCodeValue?
    let clientModelConfigs: [AntigravityModelConfig]?
}

private struct AntigravityUserStatus: Decodable {
    let email: String?
    let planStatus: AntigravityPlanStatus?
    let cascadeModelConfigData: AntigravityModelConfigData?
}

private struct AntigravityPlanStatus: Decodable {
    let planInfo: AntigravityPlanInfo?
}

private struct AntigravityPlanInfo: Decodable {
    let planName: String?
    let planDisplayName: String?
    let displayName: String?
    let productName: String?
    let planShortName: String?

    var preferredName: String? {
        [planDisplayName, displayName, productName, planName, planShortName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }
}

private struct AntigravityModelConfigData: Decodable {
    let clientModelConfigs: [AntigravityModelConfig]?
}

private struct AntigravityModelConfig: Decodable {
    let label: String
    let modelOrAlias: AntigravityModelAlias
    let quotaInfo: AntigravityQuotaInfo?
}

private struct AntigravityModelAlias: Decodable {
    let model: String
}

private struct AntigravityQuotaInfo: Decodable {
    let remainingFraction: Double?
    let resetTime: String?
}

private enum AntigravityCodeValue: Decodable {
    case int(Int)
    case string(String)

    var isOK: Bool {
        switch self {
        case .int(let value):
            return value == 0
        case .string(let value):
            let lower = value.lowercased()
            return lower == "ok" || lower == "success" || value == "0"
        }
    }

    var rawValue: String {
        switch self {
        case .int(let value):
            return "\(value)"
        case .string(let value):
            return value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported code type")
        }
    }
}

struct AntigravityQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .antigravity)

    func isConfigured() -> Bool {
        AntigravityStatusProbe().isRunningSync()
    }

    func fetch() async throws -> QuotaSnapshot {
        let snapshot = try await AntigravityStatusProbe().fetch()
        return try snapshot.toQuotaSnapshot()
    }
}

// MARK: - Vertex AI

struct VertexAIOAuthCredentials: Sendable {
    let accessToken: String
    let refreshToken: String
    let clientId: String
    let clientSecret: String
    let projectId: String?
    let email: String?
    let expiryDate: Date?

    var needsRefresh: Bool {
        guard let expiryDate else { return true }
        return Date().addingTimeInterval(300) > expiryDate
    }
}

private enum VertexAIOAuthCredentialsError: LocalizedError, Sendable {
    case notFound
    case decodeFailed(String)
    case missingTokens
    case missingClientCredentials

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "gcloud credentials not found. Run `gcloud auth application-default login`."
        case .decodeFailed(let message):
            return "Failed to decode gcloud credentials: \(message)"
        case .missingTokens:
            return "gcloud credentials exist but contain no tokens."
        case .missingClientCredentials:
            return "gcloud credentials missing client ID or secret."
        }
    }
}

enum VertexAIOAuthCredentialsStore {
    private static var credentialsFilePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let configDir = Foundation.ProcessInfo.processInfo.environment["CLOUDSDK_CONFIG"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configDir.isEmpty
        {
            return URL(fileURLWithPath: configDir).appendingPathComponent("application_default_credentials.json")
        }
        return home
            .appendingPathComponent(".config")
            .appendingPathComponent("gcloud")
            .appendingPathComponent("application_default_credentials.json")
    }

    private static var projectFilePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let configDir = Foundation.ProcessInfo.processInfo.environment["CLOUDSDK_CONFIG"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configDir.isEmpty
        {
            return URL(fileURLWithPath: configDir)
                .appendingPathComponent("configurations")
                .appendingPathComponent("config_default")
        }
        return home
            .appendingPathComponent(".config")
            .appendingPathComponent("gcloud")
            .appendingPathComponent("configurations")
            .appendingPathComponent("config_default")
    }

    static func hasCredentials() -> Bool {
        FileManager.default.fileExists(atPath: credentialsFilePath.path)
    }

    static func load() throws -> VertexAIOAuthCredentials {
        guard FileManager.default.fileExists(atPath: credentialsFilePath.path) else {
            throw VertexAIOAuthCredentialsError.notFound
        }
        return try parse(data: try Data(contentsOf: credentialsFilePath))
    }

    static func parse(data: Data) throws -> VertexAIOAuthCredentials {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VertexAIOAuthCredentialsError.decodeFailed("Invalid JSON")
        }
        if json["client_email"] is String, json["private_key"] is String {
            throw VertexAIOAuthCredentialsError.decodeFailed(
                "Service account credentials not yet supported. Use `gcloud auth application-default login`."
            )
        }
        guard let clientId = json["client_id"] as? String,
              let clientSecret = json["client_secret"] as? String
        else {
            throw VertexAIOAuthCredentialsError.missingClientCredentials
        }
        guard let refreshToken = json["refresh_token"] as? String, !refreshToken.isEmpty else {
            throw VertexAIOAuthCredentialsError.missingTokens
        }
        let accessToken = json["access_token"] as? String ?? ""
        let projectId = loadProjectId()
        let email = extractEmailFromIdToken(json["id_token"] as? String)
        let expiryDate: Date? = {
            guard let expiry = json["token_expiry"] as? String else { return nil }
            return ISO8601DateFormatter().date(from: expiry)
        }()
        return VertexAIOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            clientId: clientId,
            clientSecret: clientSecret,
            projectId: projectId,
            email: email,
            expiryDate: expiryDate
        )
    }

    static func save(_ credentials: VertexAIOAuthCredentials) throws {
        _ = credentials
    }

    private static func loadProjectId() -> String? {
        if let content = try? String(contentsOf: projectFilePath, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("project") {
                    let parts = trimmed.components(separatedBy: "=")
                    if parts.count >= 2 {
                        return parts[1].trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        return Foundation.ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT"]
            ?? Foundation.ProcessInfo.processInfo.environment["GCLOUD_PROJECT"]
            ?? Foundation.ProcessInfo.processInfo.environment["CLOUDSDK_CORE_PROJECT"]
    }

    fileprivate static func extractEmailFromIdToken(_ token: String?) -> String? {
        guard let token, !token.isEmpty else { return nil }
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json["email"] as? String
    }
}

private enum VertexAITokenRefresher {
    private static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!

    enum RefreshError: LocalizedError, Sendable {
        case expired
        case revoked
        case networkError(Error)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .expired:
                return "Refresh token expired. Run `gcloud auth application-default login` again."
            case .revoked:
                return "Refresh token was revoked. Run `gcloud auth application-default login` again."
            case .networkError(let error):
                return "Network error during token refresh: \(error.localizedDescription)"
            case .invalidResponse(let message):
                return "Invalid refresh response: \(message)"
            }
        }
    }

    static func refresh(_ credentials: VertexAIOAuthCredentials) async throws -> VertexAIOAuthCredentials {
        guard !credentials.refreshToken.isEmpty else {
            throw RefreshError.invalidResponse("No refresh token available")
        }
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyParams = [
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token",
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\(($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw RefreshError.invalidResponse("No HTTP response")
            }
            if http.statusCode == 400 || http.statusCode == 401 {
                let errorCode = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String)?.lowercased()
                switch errorCode {
                case "invalid_grant":
                    throw RefreshError.expired
                case "unauthorized_client":
                    throw RefreshError.revoked
                default:
                    throw RefreshError.invalidResponse("Status \(http.statusCode)")
                }
            }
            guard http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw RefreshError.invalidResponse("Status \(http.statusCode)")
            }

            let newAccessToken = json["access_token"] as? String ?? credentials.accessToken
            let expiresIn = (json["expires_in"] as? Double) ?? 3600
            let email = VertexAIOAuthCredentialsStore.extractEmailFromIdToken(json["id_token"] as? String) ?? credentials.email
            return VertexAIOAuthCredentials(
                accessToken: newAccessToken,
                refreshToken: credentials.refreshToken,
                clientId: credentials.clientId,
                clientSecret: credentials.clientSecret,
                projectId: credentials.projectId,
                email: email,
                expiryDate: Date().addingTimeInterval(expiresIn)
            )
        } catch let error as RefreshError {
            throw error
        } catch {
            throw RefreshError.networkError(error)
        }
    }
}

private enum VertexAIFetchError: LocalizedError, Sendable {
    case unauthorized
    case forbidden
    case noProject
    case networkError(Error)
    case invalidResponse(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Vertex AI request unauthorized. Run `gcloud auth application-default login`."
        case .forbidden:
            return "Access forbidden. Check your IAM permissions for Cloud Monitoring."
        case .noProject:
            return "No Google Cloud project configured. Run `gcloud config set project PROJECT_ID`."
        case .networkError(let error):
            return "Vertex AI network error: \(error.localizedDescription)"
        case .invalidResponse(let message):
            return "Vertex AI response was invalid: \(message)"
        case .noData:
            return "No Vertex AI usage data found for the current project."
        }
    }
}

private struct VertexAIUsageResponse: Sendable {
    let requestsUsedPercent: Double
    let tokensUsedPercent: Double?
    let resetsAt: Date?
    let resetDescription: String?
}

private enum VertexAIUsageFetcher {
    private static let monitoringEndpoint = "https://monitoring.googleapis.com/v3/projects"
    private static let usageWindowSeconds: TimeInterval = 24 * 60 * 60

    static func fetchUsage(accessToken: String, projectId: String?) async throws -> VertexAIUsageResponse {
        guard let projectId, !projectId.isEmpty else {
            throw VertexAIFetchError.noProject
        }
        return try await fetchQuotaUsage(accessToken: accessToken, projectId: projectId)
    }

    private struct MonitoringTimeSeriesResponse: Decodable {
        let timeSeries: [MonitoringTimeSeries]?
        let nextPageToken: String?
    }

    private struct MonitoringTimeSeries: Decodable {
        let metric: MonitoringMetric
        let resource: MonitoringResource
        let points: [MonitoringPoint]
    }

    private struct MonitoringMetric: Decodable {
        let labels: [String: String]?
    }

    private struct MonitoringResource: Decodable {
        let labels: [String: String]?
    }

    private struct MonitoringPoint: Decodable {
        let value: MonitoringValue
    }

    private struct MonitoringValue: Decodable {
        let doubleValue: Double?
        let int64Value: String?
    }

    private struct QuotaKey: Hashable {
        let quotaMetric: String
        let limitName: String
        let location: String
    }

    private static func fetchQuotaUsage(accessToken: String, projectId: String) async throws -> VertexAIUsageResponse {
        let usageFilter = """
        metric.type="serviceruntime.googleapis.com/quota/allocation/usage" \
        AND resource.type="consumer_quota" \
        AND resource.label.service="aiplatform.googleapis.com"
        """
        let limitFilter = """
        metric.type="serviceruntime.googleapis.com/quota/limit" \
        AND resource.type="consumer_quota" \
        AND resource.label.service="aiplatform.googleapis.com"
        """

        let usageSeries = try await fetchTimeSeries(accessToken: accessToken, projectId: projectId, filter: usageFilter)
        let limitSeries = try await fetchTimeSeries(accessToken: accessToken, projectId: projectId, filter: limitFilter)
        let usageByKey = aggregate(series: usageSeries)
        let limitByKey = aggregate(series: limitSeries)

        guard !usageByKey.isEmpty, !limitByKey.isEmpty else {
            throw VertexAIFetchError.noData
        }

        var maxPercent: Double?
        var matchedCount = 0
        for (key, limit) in limitByKey {
            guard limit > 0, let usage = usageByKey[key] else { continue }
            matchedCount += 1
            let percent = (usage / limit) * 100
            maxPercent = max(maxPercent ?? percent, percent)
        }
        guard let usedPercent = maxPercent, matchedCount > 0 else {
            throw VertexAIFetchError.noData
        }

        return VertexAIUsageResponse(
            requestsUsedPercent: usedPercent,
            tokensUsedPercent: nil,
            resetsAt: nil,
            resetDescription: nil
        )
    }

    private static func fetchTimeSeries(
        accessToken: String,
        projectId: String,
        filter: String
    ) async throws -> [MonitoringTimeSeries] {
        let now = Date()
        let start = now.addingTimeInterval(-usageWindowSeconds)
        let formatter = ISO8601DateFormatter()
        var pageToken: String?
        var allSeries: [MonitoringTimeSeries] = []

        repeat {
            guard var components = URLComponents(string: "\(monitoringEndpoint)/\(projectId)/timeSeries") else {
                throw VertexAIFetchError.invalidResponse("Invalid Monitoring URL")
            }
            var queryItems = [
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "interval.startTime", value: formatter.string(from: start)),
                URLQueryItem(name: "interval.endTime", value: formatter.string(from: now)),
                URLQueryItem(name: "aggregation.alignmentPeriod", value: "3600s"),
                URLQueryItem(name: "aggregation.perSeriesAligner", value: "ALIGN_MAX"),
                URLQueryItem(name: "view", value: "FULL"),
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems
            guard let url = components.url else {
                throw VertexAIFetchError.invalidResponse("Invalid Monitoring URL")
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw VertexAIFetchError.networkError(error)
            }
            guard let http = response as? HTTPURLResponse else {
                throw VertexAIFetchError.invalidResponse("No HTTP response")
            }
            switch http.statusCode {
            case 200:
                break
            case 401:
                throw VertexAIFetchError.unauthorized
            case 403:
                throw VertexAIFetchError.forbidden
            default:
                let body = String(data: data, encoding: .utf8) ?? ""
                throw VertexAIFetchError.invalidResponse("HTTP \(http.statusCode): \(body)")
            }

            let decoded = try JSONDecoder().decode(MonitoringTimeSeriesResponse.self, from: data)
            if let series = decoded.timeSeries {
                allSeries.append(contentsOf: series)
            }
            pageToken = decoded.nextPageToken?.isEmpty == false ? decoded.nextPageToken : nil
        } while pageToken != nil

        return allSeries
    }

    private static func aggregate(series: [MonitoringTimeSeries]) -> [QuotaKey: Double] {
        var buckets: [QuotaKey: Double] = [:]
        for entry in series {
            guard let key = quotaKey(from: entry),
                  let value = maxPointValue(from: entry.points)
            else { continue }
            buckets[key] = max(buckets[key] ?? 0, value)
        }
        return buckets
    }

    private static func quotaKey(from series: MonitoringTimeSeries) -> QuotaKey? {
        let metric = series.metric.labels ?? [:]
        let resource = series.resource.labels ?? [:]
        let quotaMetric = metric["quota_metric"] ?? metric["metric_name"] ?? ""
        let limitName = metric["limit_name"] ?? metric["quota_limit"] ?? ""
        let location = resource["location"] ?? metric["location"] ?? "global"
        guard !quotaMetric.isEmpty || !limitName.isEmpty else { return nil }
        return QuotaKey(quotaMetric: quotaMetric, limitName: limitName, location: location)
    }

    private static func maxPointValue(from points: [MonitoringPoint]) -> Double? {
        let values = points.compactMap { point in
            point.value.doubleValue ?? point.value.int64Value.flatMap(Double.init)
        }
        return values.max()
    }
}

struct VertexAIQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .vertexAI)

    func isConfigured() -> Bool {
        VertexAIOAuthCredentialsStore.hasCredentials()
    }

    func fetch() async throws -> QuotaSnapshot {
        var credentials = try VertexAIOAuthCredentialsStore.load()
        if credentials.needsRefresh {
            credentials = try await VertexAITokenRefresher.refresh(credentials)
            try? VertexAIOAuthCredentialsStore.save(credentials)
        }

        let usage: VertexAIUsageResponse?
        do {
            usage = try await VertexAIUsageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                projectId: credentials.projectId
            )
        } catch VertexAIFetchError.noData {
            usage = nil
        }

        let primaryWindow = usage.flatMap {
            quotaWindow(
                label: descriptor.primaryLabel,
                usedRatio: min(max($0.requestsUsedPercent / 100.0, 0), 1),
                detail: $0.resetDescription,
                resetsAt: $0.resetsAt
            )
        }
        let secondaryWindow = usage.flatMap { response in
            response.tokensUsedPercent.map {
                QuotaWindow(
                    label: descriptor.secondaryLabel ?? "Tokens",
                    usedRatio: min(max($0 / 100.0, 0), 1),
                    detail: response.resetDescription,
                    resetsAt: response.resetsAt
                )
            }
        }

        return QuotaSnapshot(
            providerID: .vertexAI,
            source: .oauth,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: nil,
            credits: nil,
            identity: QuotaIdentity(
                email: credentials.email,
                organization: credentials.projectId,
                plan: "gcloud",
                detail: usage == nil ? "No recent Vertex AI quota data" : nil
            ),
            updatedAt: Date(),
            note: nil
        )
    }
}

// MARK: - Kilo

enum KiloSettingsReader {
    static let apiTokenKey = "KILO_API_KEY"

    static func apiKey(environment: [String: String] = Foundation.ProcessInfo.processInfo.environment) -> String? {
        cleaned(environment[apiTokenKey])
    }

    static func apiURL(environment: [String: String] = Foundation.ProcessInfo.processInfo.environment) -> URL {
        _ = environment
        return URL(string: "https://app.kilo.ai/api/trpc")!
    }

    static func authToken(
        authFileURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        let fileURL = authFileURL ?? defaultAuthFileURL(homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return parseAuthToken(data: data)
    }

    static func defaultAuthFileURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("kilo", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
    }

    static func parseAuthToken(data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(KiloAuthFile.self, from: data) else { return nil }
        return cleaned(payload.kilo?.access)
    }

    static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value.removeFirst()
            value.removeLast()
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct KiloAuthFile: Decodable {
    let kilo: KiloSection?

    struct KiloSection: Decodable {
        let access: String?
    }
}

struct KiloUsageSnapshot: Sendable {
    let creditsUsed: Double?
    let creditsTotal: Double?
    let creditsRemaining: Double?
    let passUsed: Double?
    let passTotal: Double?
    let passRemaining: Double?
    let passBonus: Double?
    let passResetsAt: Date?
    let planName: String?
    let autoTopUpEnabled: Bool?
    let autoTopUpMethod: String?
    let updatedAt: Date

    func toQuotaSnapshot(source: QuotaSourceKind, updatedAt: Date = Date()) -> QuotaSnapshot {
        let primaryWindow: QuotaWindow? = {
            guard let total = resolvedTotal else { return nil }
            let used = resolvedUsed
            let usedRatio = total > 0 ? min(1, max(0, used / total)) : 1
            return QuotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .kilo).primaryLabel,
                usedRatio: usedRatio,
                detail: "\(Self.compactNumber(used))/\(Self.compactNumber(total)) credits",
                resetsAt: nil
            )
        }()

        let secondaryWindow: QuotaWindow? = {
            guard let total = resolvedPassTotal else { return nil }
            let used = resolvedPassUsed
            let bonus = max(0, passBonus ?? 0)
            let baseCredits = max(0, total - bonus)
            let detail: String = {
                var detail = "$\(Self.currencyNumber(used)) / $\(Self.currencyNumber(baseCredits))"
                if bonus > 0 {
                    detail += " (+ $\(Self.currencyNumber(bonus)) bonus)"
                }
                return detail
            }()
            return QuotaWindow(
                label: QuotaProviderRegistry.descriptor(for: .kilo).secondaryLabel ?? "Kilo Pass",
                usedRatio: total > 0 ? min(1, max(0, used / total)) : 1,
                detail: detail,
                resetsAt: passResetsAt
            )
        }()

        let identityDetail: String? = {
            var parts: [String] = []
            if let autoTopUpEnabled {
                if autoTopUpEnabled {
                    if let autoTopUpMethod, !autoTopUpMethod.isEmpty {
                        parts.append("Auto top-up: \(autoTopUpMethod)")
                    } else {
                        parts.append("Auto top-up: enabled")
                    }
                } else {
                    parts.append("Auto top-up: off")
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }()

        return QuotaSnapshot(
            providerID: .kilo,
            source: source,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow,
            tertiaryWindow: nil,
            credits: {
                guard let total = resolvedTotal else { return nil }
                return QuotaCredits(
                    label: "Credits",
                    used: resolvedUsed,
                    total: total,
                    remaining: creditsRemaining ?? max(0, total - resolvedUsed),
                    currencyCode: nil,
                    isUnlimited: false
                )
            }(),
            identity: QuotaIdentity(
                email: nil,
                organization: nil,
                plan: planName,
                detail: identityDetail
            ),
            updatedAt: updatedAt,
            note: nil
        )
    }

    private var resolvedTotal: Double? {
        if let creditsTotal { return max(0, creditsTotal) }
        if let creditsUsed, let creditsRemaining { return max(0, creditsUsed + creditsRemaining) }
        return nil
    }

    private var resolvedUsed: Double {
        if let creditsUsed { return max(0, creditsUsed) }
        if let total = resolvedTotal, let creditsRemaining { return max(0, total - creditsRemaining) }
        return 0
    }

    private var resolvedPassTotal: Double? {
        if let passTotal { return max(0, passTotal) }
        if let passUsed, let passRemaining { return max(0, passUsed + passRemaining) }
        return nil
    }

    private var resolvedPassUsed: Double {
        if let passUsed { return max(0, passUsed) }
        if let total = resolvedPassTotal, let passRemaining { return max(0, total - passRemaining) }
        return 0
    }

    private static func compactNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private static func currencyNumber(_ value: Double) -> String {
        String(format: "%.2f", max(0, value))
    }
}

private enum KiloUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case cliSessionMissing(String)
    case cliSessionUnreadable(String)
    case cliSessionInvalid(String)
    case unauthorized
    case endpointNotFound
    case serviceUnavailable(Int)
    case networkError(String)
    case parseFailed(String)
    case apiError(Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Kilo API credentials missing. Set KILO_API_KEY."
        case .cliSessionMissing(let path):
            return "Kilo CLI session not found at \(path). Run `kilo login`."
        case .cliSessionUnreadable(let path):
            return "Kilo CLI session file is unreadable at \(path)."
        case .cliSessionInvalid(let path):
            return "Kilo CLI session file is invalid at \(path). Run `kilo login` again."
        case .unauthorized:
            return "Kilo authentication failed (401/403). Refresh KILO_API_KEY or run `kilo login`."
        case .endpointNotFound:
            return "Kilo API endpoint not found (404). Verify the tRPC batch path and procedure names."
        case .serviceUnavailable(let code):
            return "Kilo API is currently unavailable (HTTP \(code)). Try again later."
        case .networkError(let message):
            return "Kilo network error: \(message)"
        case .parseFailed:
            return "Failed to parse Kilo API response. Response format may have changed."
        case .apiError(let code):
            return "Kilo API request failed (HTTP \(code))."
        }
    }
}

enum KiloUsageFetcher {
    private struct KiloPassFields {
        let used: Double?
        let total: Double?
        let remaining: Double?
        let bonus: Double?
        let resetsAt: Date?
    }

    private static let procedures = [
        "user.getCreditBlocks",
        "kiloPass.getState",
        "user.getAutoTopUpPaymentMethod",
    ]
    private static let optionalProcedures: Set<String> = ["user.getAutoTopUpPaymentMethod"]
    private static let maxTopLevelEntries = procedures.count

    static func fetchUsage(apiKey: String, environment: [String: String] = Foundation.ProcessInfo.processInfo.environment) async throws -> KiloUsageSnapshot {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KiloUsageError.missingCredentials
        }
        let batchURL = try makeBatchURL(baseURL: KiloSettingsReader.apiURL(environment: environment))
        var request = URLRequest(url: batchURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw KiloUsageError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw KiloUsageError.networkError("Invalid response")
        }
        if let mapped = statusError(for: httpResponse.statusCode) {
            throw mapped
        }
        guard httpResponse.statusCode == 200 else {
            throw KiloUsageError.apiError(httpResponse.statusCode)
        }
        return try parseSnapshot(data: data)
    }

    static func parseSnapshot(data: Data) throws -> KiloUsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw KiloUsageError.parseFailed("Invalid JSON")
        }
        let entriesByIndex = try responseEntriesByIndex(from: root)
        var payloadsByProcedure: [String: Any] = [:]

        for (index, procedure) in procedures.enumerated() {
            guard let entry = entriesByIndex[index] else { continue }
            if let mappedError = trpcError(from: entry) {
                if isRequiredProcedure(procedure) {
                    throw mappedError
                }
                continue
            }
            if let payload = resultPayload(from: entry) {
                payloadsByProcedure[procedure] = payload
            }
        }

        let creditFields = creditFields(from: payloadsByProcedure[procedures[0]])
        let passFields = passFields(from: payloadsByProcedure[procedures[1]])
        let planName = planName(from: payloadsByProcedure[procedures[1]])
        let autoTopUp = autoTopUpState(
            creditBlocksPayload: payloadsByProcedure[procedures[0]],
            autoTopUpPayload: payloadsByProcedure[procedures[2]]
        )

        return KiloUsageSnapshot(
            creditsUsed: creditFields.used,
            creditsTotal: creditFields.total,
            creditsRemaining: creditFields.remaining,
            passUsed: passFields.used,
            passTotal: passFields.total,
            passRemaining: passFields.remaining,
            passBonus: passFields.bonus,
            passResetsAt: passFields.resetsAt,
            planName: planName,
            autoTopUpEnabled: autoTopUp.enabled,
            autoTopUpMethod: autoTopUp.method,
            updatedAt: Date()
        )
    }

    static func _test_parseSnapshot(_ data: Data) throws -> KiloUsageSnapshot {
        try parseSnapshot(data: data)
    }

    private static func statusError(for statusCode: Int) -> KiloUsageError? {
        switch statusCode {
        case 401, 403: return .unauthorized
        case 404: return .endpointNotFound
        case 500...599: return .serviceUnavailable(statusCode)
        default: return nil
        }
    }

    private static func makeBatchURL(baseURL: URL) throws -> URL {
        let joinedProcedures = procedures.joined(separator: ",")
        let endpoint = baseURL.appendingPathComponent(joinedProcedures)
        let inputMap = Dictionary(uniqueKeysWithValues: procedures.indices.map { (String($0), ["json": NSNull()]) })
        let inputData = try JSONSerialization.data(withJSONObject: inputMap)
        guard let inputString = String(data: inputData, encoding: .utf8),
              var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        else {
            throw KiloUsageError.parseFailed("Invalid batch endpoint")
        }
        components.queryItems = [
            URLQueryItem(name: "batch", value: "1"),
            URLQueryItem(name: "input", value: inputString),
        ]
        guard let url = components.url else {
            throw KiloUsageError.parseFailed("Invalid batch endpoint")
        }
        return url
    }

    private static func responseEntriesByIndex(from root: Any) throws -> [Int: [String: Any]] {
        if let entries = root as? [[String: Any]] {
            return Dictionary(uniqueKeysWithValues: Array(entries.prefix(maxTopLevelEntries)).enumerated().map { ($0.offset, $0.element) })
        }
        if let dictionary = root as? [String: Any] {
            if dictionary["result"] != nil || dictionary["error"] != nil {
                return [0: dictionary]
            }
            let indexedEntries = dictionary.compactMap { key, value -> (Int, [String: Any])? in
                guard let index = Int(key), let entry = value as? [String: Any] else { return nil }
                return (index, entry)
            }
            if !indexedEntries.isEmpty {
                return Dictionary(uniqueKeysWithValues: indexedEntries.filter { $0.0 >= 0 && $0.0 < maxTopLevelEntries })
            }
        }
        throw KiloUsageError.parseFailed("Unexpected tRPC batch shape")
    }

    private static func trpcError(from entry: [String: Any]) -> KiloUsageError? {
        guard let errorObject = entry["error"] as? [String: Any] else { return nil }
        let code = stringValue(for: ["json", "data", "code"], in: errorObject)
            ?? stringValue(for: ["data", "code"], in: errorObject)
            ?? stringValue(for: ["code"], in: errorObject)
        let message = stringValue(for: ["json", "message"], in: errorObject)
            ?? stringValue(for: ["message"], in: errorObject)
        let combined = [code, message].compactMap { $0?.lowercased() }.joined(separator: " ")
        if combined.contains("unauthorized") || combined.contains("forbidden") {
            return .unauthorized
        }
        if combined.contains("not_found") || combined.contains("not found") {
            return .endpointNotFound
        }
        return .parseFailed("tRPC error payload")
    }

    private static func resultPayload(from entry: [String: Any]) -> Any? {
        guard let resultObject = entry["result"] as? [String: Any] else { return nil }
        if let dataObject = resultObject["data"] as? [String: Any] {
            if let jsonPayload = dataObject["json"] {
                return jsonPayload is NSNull ? nil : jsonPayload
            }
            return dataObject
        }
        if let jsonPayload = resultObject["json"] {
            return jsonPayload is NSNull ? nil : jsonPayload
        }
        return nil
    }

    private static func isRequiredProcedure(_ procedure: String) -> Bool {
        !optionalProcedures.contains(procedure)
    }

    private static func creditFields(from payload: Any?) -> (used: Double?, total: Double?, remaining: Double?) {
        let contexts = dictionaryContexts(from: payload)
        let blocks = firstArray(forKeys: ["creditBlocks"], in: contexts)
        if let blocks {
            var totalFromBlocks: Double = 0
            var remainingFromBlocks: Double = 0
            var sawTotal = false
            var sawRemaining = false
            for case let block as [String: Any] in blocks {
                if let amountMicroUSD = double(from: block["amount_mUsd"]) {
                    totalFromBlocks += amountMicroUSD / 1_000_000
                    sawTotal = true
                }
                if let balanceMicroUSD = double(from: block["balance_mUsd"]) {
                    remainingFromBlocks += balanceMicroUSD / 1_000_000
                    sawRemaining = true
                }
            }
            if sawTotal || sawRemaining {
                let total = sawTotal ? max(0, totalFromBlocks) : nil
                let remaining = sawRemaining ? max(0, remainingFromBlocks) : nil
                let used: Double? = if let total, let remaining { max(0, total - remaining) } else { nil }
                return (used, total, remaining)
            }
        }
        if let balanceMilliUSD = firstDouble(forKeys: ["totalBalance_mUsd"], in: contexts) {
            let balance = max(0, balanceMilliUSD / 1_000_000)
            return (0, balance, balance)
        }
        return (
            firstDouble(forKeys: ["used", "usedCredits", "creditsUsed"], in: contexts),
            firstDouble(forKeys: ["total", "totalCredits", "creditsTotal", "limit"], in: contexts),
            firstDouble(forKeys: ["remaining", "remainingCredits", "creditsRemaining"], in: contexts)
        )
    }

    private static func passFields(from payload: Any?) -> KiloPassFields {
        if let subscription = subscriptionData(from: payload) {
            let used = double(from: subscription["currentPeriodUsageUsd"]).map { max(0, $0) }
            let baseCredits = double(from: subscription["currentPeriodBaseCreditsUsd"]).map { max(0, $0) }
            let bonusCredits = max(0, double(from: subscription["currentPeriodBonusCreditsUsd"]) ?? 0)
            let total = baseCredits.map { $0 + bonusCredits }
            let remaining: Double? = if let total, let used { max(0, total - used) } else { nil }
            let resetsAt = date(from: subscription["nextBillingAt"])
                ?? date(from: subscription["nextRenewalAt"])
                ?? date(from: subscription["renewsAt"])
                ?? date(from: subscription["renewAt"])
            return KiloPassFields(used: used, total: total, remaining: remaining, bonus: bonusCredits > 0 ? bonusCredits : nil, resetsAt: resetsAt)
        }
        return KiloPassFields(used: nil, total: nil, remaining: nil, bonus: nil, resetsAt: nil)
    }

    private static func planName(from payload: Any?) -> String? {
        if let subscription = subscriptionData(from: payload),
           let tier = string(from: subscription["tier"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tier.isEmpty
        {
            switch tier {
            case "tier_19": return "Starter"
            case "tier_49": return "Pro"
            case "tier_199": return "Expert"
            default: return tier
            }
        }
        return "Kilo Pass"
    }

    private static func autoTopUpState(creditBlocksPayload: Any?, autoTopUpPayload: Any?) -> (enabled: Bool?, method: String?) {
        let creditContexts = dictionaryContexts(from: creditBlocksPayload)
        let autoTopUpContexts = dictionaryContexts(from: autoTopUpPayload)
        let enabled = firstBool(forKeys: ["enabled", "isEnabled", "active"], in: autoTopUpContexts)
            ?? firstBool(forKeys: ["autoTopUpEnabled"], in: creditContexts)
        let rawMethod = firstString(forKeys: ["paymentMethod", "paymentMethodType", "method", "cardBrand"], in: autoTopUpContexts)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = moneyAmount(centsKeys: ["amountCents"], milliUSDKeys: [], plainKeys: ["amount", "topUpAmount", "amountUsd"], in: autoTopUpContexts)
        let method: String? = if let rawMethod, !rawMethod.isEmpty {
            rawMethod
        } else if let amount, amount > 0 {
            currencyAmountLabel(amount)
        } else {
            nil
        }
        return (enabled, method)
    }

    private static func subscriptionData(from payload: Any?) -> [String: Any]? {
        guard let dictionary = payload as? [String: Any] else { return nil }
        if let subscription = dictionary["subscription"] as? [String: Any] {
            return subscription
        }
        let hasShape = dictionary["currentPeriodUsageUsd"] != nil
            || dictionary["currentPeriodBaseCreditsUsd"] != nil
            || dictionary["currentPeriodBonusCreditsUsd"] != nil
            || dictionary["tier"] != nil
        return hasShape ? dictionary : nil
    }

    private static func dictionaryContexts(from payload: Any?) -> [[String: Any]] {
        guard let dictionary = payload as? [String: Any] else { return [] }
        var contexts: [[String: Any]] = []
        var queue: [([String: Any], Int)] = [(dictionary, 0)]
        let maxDepth = 2
        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            contexts.append(current)
            guard depth < maxDepth else { continue }
            for value in current.values {
                if let nested = value as? [String: Any] {
                    queue.append((nested, depth + 1))
                } else if let array = value as? [Any] {
                    for case let nested as [String: Any] in array {
                        queue.append((nested, depth + 1))
                    }
                }
            }
        }
        return contexts
    }

    private static func firstArray(forKeys keys: [String], in contexts: [[String: Any]]) -> [Any]? {
        for context in contexts {
            for key in keys {
                if let values = context[key] as? [Any] { return values }
            }
        }
        return nil
    }

    private static func firstDouble(forKeys keys: [String], in contexts: [[String: Any]]) -> Double? {
        for context in contexts {
            for key in keys {
                if let value = double(from: context[key]) { return value }
            }
        }
        return nil
    }

    private static func firstString(forKeys keys: [String], in contexts: [[String: Any]]) -> String? {
        for context in contexts {
            for key in keys {
                if let value = context[key] as? String { return value }
            }
        }
        return nil
    }

    private static func firstBool(forKeys keys: [String], in contexts: [[String: Any]]) -> Bool? {
        for context in contexts {
            for key in keys {
                if let value = bool(from: context[key]) { return value }
            }
        }
        return nil
    }

    private static func moneyAmount(
        centsKeys: [String],
        milliUSDKeys: [String],
        plainKeys: [String],
        in contexts: [[String: Any]]
    ) -> Double? {
        if let cents = firstDouble(forKeys: centsKeys, in: contexts) { return cents / 100 }
        if let milliUSD = firstDouble(forKeys: milliUSDKeys, in: contexts) { return milliUSD / 1_000_000 }
        return firstDouble(forKeys: plainKeys, in: contexts)
    }

    private static func currencyAmountLabel(_ amount: Double) -> String {
        if amount.rounded(.towardZero) == amount {
            return String(format: "$%.0f", amount)
        }
        return String(format: "$%.2f", amount)
    }

    private static func stringValue(for path: [String], in dictionary: [String: Any]) -> String? {
        var cursor: Any = dictionary
        for key in path {
            guard let next = (cursor as? [String: Any])?[key] else { return nil }
            cursor = next
        }
        return cursor as? String
    }

    private static func string(from raw: Any?) -> String? {
        raw as? String
    }

    private static func double(from raw: Any?) -> Double? {
        switch raw {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    private static func bool(from raw: Any?) -> Bool? {
        switch raw {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String:
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "enabled", "on"].contains(normalized) { return true }
            if ["false", "0", "no", "disabled", "off"].contains(normalized) { return false }
            return nil
        default:
            return nil
        }
    }

    private static func date(from raw: Any?) -> Date? {
        switch raw {
        case let value as Date:
            return value
        case let value as Double:
            return dateFromEpoch(value)
        case let value as Int:
            return dateFromEpoch(Double(value))
        case let value as NSNumber:
            return dateFromEpoch(value.doubleValue)
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let numeric = Double(trimmed) {
                return dateFromEpoch(numeric)
            }
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = withFractional.date(from: trimmed) { return parsed }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: trimmed)
        default:
            return nil
        }
    }

    private static func dateFromEpoch(_ value: Double) -> Date {
        let seconds = abs(value) > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}

struct KiloQuotaProvider: QuotaProvider {
    let descriptor = QuotaProviderRegistry.descriptor(for: .kilo)

    func isConfigured() -> Bool {
        switch QuotaPreferences.sourcePreference(for: .kilo) {
        case .apiKey:
            return apiToken() != nil
        case .cli:
            return cliAuthToken() != nil
        case .auto:
            return apiToken() != nil || cliAuthToken() != nil
        default:
            return apiToken() != nil || cliAuthToken() != nil
        }
    }

    func fetch() async throws -> QuotaSnapshot {
        switch QuotaPreferences.sourcePreference(for: .kilo) {
        case .apiKey:
            guard let token = apiToken() else { throw KiloUsageError.missingCredentials }
            return try await KiloUsageFetcher.fetchUsage(apiKey: token).toQuotaSnapshot(source: .apiKey)
        case .cli:
            let token = try cliAuthTokenRequired()
            return try await KiloUsageFetcher.fetchUsage(apiKey: token).toQuotaSnapshot(source: .cli)
        case .auto:
            if let token = apiToken() {
                do {
                    return try await KiloUsageFetcher.fetchUsage(apiKey: token).toQuotaSnapshot(source: .apiKey)
                } catch let error as KiloUsageError where error == .missingCredentials || error == .unauthorized {
                    let cliToken = try cliAuthTokenRequired()
                    return try await KiloUsageFetcher.fetchUsage(apiKey: cliToken).toQuotaSnapshot(source: .cli)
                }
            }
            let cliToken = try cliAuthTokenRequired()
            return try await KiloUsageFetcher.fetchUsage(apiKey: cliToken).toQuotaSnapshot(source: .cli)
        default:
            if let token = apiToken() {
                return try await KiloUsageFetcher.fetchUsage(apiKey: token).toQuotaSnapshot(source: .apiKey)
            }
            let cliToken = try cliAuthTokenRequired()
            return try await KiloUsageFetcher.fetchUsage(apiKey: cliToken).toQuotaSnapshot(source: .cli)
        }
    }

    private func apiToken() -> String? {
        SavedProviderTokenResolver.token(for: .kilo, envKeys: [KiloSettingsReader.apiTokenKey])
    }

    private func cliAuthToken() -> String? {
        KiloSettingsReader.authToken()
    }

    private func cliAuthTokenRequired() throws -> String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let authFileURL = KiloSettingsReader.defaultAuthFileURL(homeDirectory: homeDirectory)
        guard FileManager.default.fileExists(atPath: authFileURL.path) else {
            throw KiloUsageError.cliSessionMissing(authFileURL.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: authFileURL)
        } catch {
            throw KiloUsageError.cliSessionUnreadable(authFileURL.path)
        }
        guard let token = KiloSettingsReader.parseAuthToken(data: data) else {
            throw KiloUsageError.cliSessionInvalid(authFileURL.path)
        }
        return token
    }
}
