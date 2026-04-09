//
//  QuotaBrowserStorageSupport.swift
//  ClaudeIsland
//

import Foundation
#if os(macOS)
import Security
import SQLite3
#if canImport(CommonCrypto)
import CommonCrypto
#endif
#if canImport(SweetCookieKit)
import SweetCookieKit
#endif
#endif

#if os(macOS) && canImport(SweetCookieKit)

enum FactoryTokenStore {
    private static let bearerAccount = QuotaProviderRegistry.secretAccountName(for: .factory, suffix: "bearer")
    private static let refreshAccount = QuotaProviderRegistry.secretAccountName(for: .factory, suffix: "refresh")

    static func bearerToken() -> ResolvedProviderCredential? {
        guard let token = QuotaSecretStore.read(account: bearerAccount),
              let cleaned = QuotaRuntimeSupport.cleaned(token)
        else {
            return nil
        }
        return ResolvedProviderCredential(
            value: cleaned,
            sourceLabel: QuotaPreferences.credentialSourceLabel(account: bearerAccount) ?? "Stored Factory bearer token"
        )
    }

    static func refreshToken() -> ResolvedProviderCredential? {
        guard let token = QuotaSecretStore.read(account: refreshAccount),
              let cleaned = QuotaRuntimeSupport.cleaned(token)
        else {
            return nil
        }
        return ResolvedProviderCredential(
            value: cleaned,
            sourceLabel: QuotaPreferences.credentialSourceLabel(account: refreshAccount) ?? "Stored WorkOS refresh token"
        )
    }

    static func setBearerToken(_ token: String?, sourceLabel: String? = nil) {
        set(token, account: bearerAccount, sourceLabel: sourceLabel ?? "Stored Factory bearer token")
    }

    static func setRefreshToken(_ token: String?, sourceLabel: String? = nil) {
        set(token, account: refreshAccount, sourceLabel: sourceLabel ?? "Stored WorkOS refresh token")
    }

    private static func set(_ value: String?, account: String, sourceLabel: String) {
        guard let cleaned = QuotaRuntimeSupport.cleaned(value) else {
            QuotaSecretStore.delete(account: account)
            QuotaPreferences.setCredentialSourceLabel(nil, account: account)
            return
        }
        QuotaSecretStore.save(cleaned, account: account)
        QuotaPreferences.setCredentialSourceLabel(sourceLabel, account: account)
    }
}

struct FactoryLocalStorageTokenInfo: Sendable {
    let refreshToken: String
    let accessToken: String?
    let organizationID: String?
    let sourceLabel: String
}

enum FactoryLocalStorageImporter {
    static func importWorkOSTokens(logger: ((String) -> Void)? = nil) -> [FactoryLocalStorageTokenInfo] {
        let log: (String) -> Void = { msg in logger?("[factory-storage] \(msg)") }
        var tokens: [FactoryLocalStorageTokenInfo] = []

        let safariCandidates = safariLocalStorageCandidates()
        let chromeCandidates = chromeLocalStorageCandidates()
        if !safariCandidates.isEmpty {
            log("Safari local storage candidates: \(safariCandidates.count)")
        }
        if !chromeCandidates.isEmpty {
            log("Chromium local storage candidates: \(chromeCandidates.count)")
        }

        for candidate in safariCandidates + chromeCandidates {
            let match: WorkOSTokenMatch? = switch candidate.kind {
            case let .chromeLevelDB(url):
                readWorkOSToken(from: url)
            case let .safariSQLite(url):
                readWorkOSTokenFromSafariSQLite(dbURL: url, logger: log)
            }
            guard let match else { continue }
            log("Found WorkOS refresh token in \(candidate.label)")
            tokens.append(
                FactoryLocalStorageTokenInfo(
                    refreshToken: match.refreshToken,
                    accessToken: match.accessToken,
                    organizationID: match.organizationID,
                    sourceLabel: candidate.label
                )
            )
        }

        if tokens.isEmpty {
            log("No WorkOS refresh token found in browser local storage")
        }
        return tokens
    }

    private enum LocalStorageSourceKind {
        case chromeLevelDB(URL)
        case safariSQLite(URL)
    }

    private struct LocalStorageCandidate {
        let label: String
        let kind: LocalStorageSourceKind
    }

    private struct WorkOSTokenMatch {
        let refreshToken: String
        let accessToken: String?
        let organizationID: String?
    }

    private static func chromeLocalStorageCandidates() -> [LocalStorageCandidate] {
        let browsers: [Browser] = [
            .chrome, .chromeBeta, .chromeCanary, .arc, .arcBeta, .arcCanary,
            .dia, .chatgptAtlas, .chromium, .helium
        ]
        let roots = ChromiumProfileLocator.roots(for: browsers, homeDirectories: BrowserCookieClient.defaultHomeDirectories())
        var candidates: [LocalStorageCandidate] = []
        for root in roots {
            candidates.append(contentsOf: chromeProfileLocalStorageDirs(root: root.url, labelPrefix: root.labelPrefix))
        }
        return candidates
    }

    private static func chromeProfileLocalStorageDirs(root: URL, labelPrefix: String) -> [LocalStorageCandidate] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let profileDirs = entries.filter { url in
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true else {
                return false
            }
            let name = url.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        return profileDirs.compactMap { dir in
            let levelDBURL = dir.appendingPathComponent("Local Storage").appendingPathComponent("leveldb")
            guard FileManager.default.fileExists(atPath: levelDBURL.path) else { return nil }
            return LocalStorageCandidate(label: "\(labelPrefix) \(dir.lastPathComponent)", kind: .chromeLevelDB(levelDBURL))
        }
    }

    private static func safariLocalStorageCandidates() -> [LocalStorageCandidate] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent("com.apple.Safari")
            .appendingPathComponent("Data")
            .appendingPathComponent("Library")
            .appendingPathComponent("WebKit")
            .appendingPathComponent("WebsiteData")
            .appendingPathComponent("Default")

        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        var candidates: [LocalStorageCandidate] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent == "origin",
                  (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
            else {
                continue
            }

            let ascii = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            guard ascii.contains("app.factory.ai") || ascii.contains("auth.factory.ai") else {
                continue
            }

            let storageURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("LocalStorage")
                .appendingPathComponent("localstorage.sqlite3")
            guard FileManager.default.fileExists(atPath: storageURL.path) else { continue }
            let host = extractSafariOriginHost(from: ascii) ?? "app.factory.ai"
            candidates.append(LocalStorageCandidate(label: "Safari (\(host))", kind: .safariSQLite(storageURL)))
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key: String = switch candidate.kind {
            case let .chromeLevelDB(url): url.path
            case let .safariSQLite(url): url.path
            }
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private static func extractSafariOriginHost(from ascii: String) -> String? {
        for host in ["app.factory.ai", "auth.factory.ai", "factory.ai"] where ascii.contains(host) {
            return host
        }
        return nil
    }

    private static func readWorkOSToken(from levelDBURL: URL) -> WorkOSTokenMatch? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: levelDBURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let files = entries.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "ldb" || ext == "log"
        }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }

        for file in files {
            guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { continue }
            if let match = extractWorkOSToken(from: data) {
                return match
            }
        }
        return nil
    }

    private static func extractWorkOSToken(from data: Data) -> WorkOSTokenMatch? {
        guard let contents = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              contents.contains("workos:refresh-token")
        else {
            return nil
        }

        let refreshToken = matchToken(in: contents, pattern: "workos:refresh-token[^A-Za-z0-9_-]*([A-Za-z0-9_-]{20,})")
        guard let refreshToken else { return nil }
        let accessToken = matchToken(in: contents, pattern: "workos:access-token[^A-Za-z0-9_-]*([A-Za-z0-9_-]{20,})")
        let organizationID = extractOrganizationID(from: accessToken)
        return WorkOSTokenMatch(refreshToken: refreshToken, accessToken: accessToken, organizationID: organizationID)
    }

    private static func readWorkOSTokenFromSafariSQLite(
        dbURL: URL,
        logger: ((String) -> Void)? = nil
    ) -> WorkOSTokenMatch? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let c = sqlite3_errmsg(db) {
                logger?("Safari local storage open failed: \(String(cString: c))")
            }
            return nil
        }
        defer { sqlite3_close(db) }

        sqlite3_busy_timeout(db, 250)
        let tables = fetchTableNames(db: db, logger: logger)
        let table = tables.contains("ItemTable") ? "ItemTable" : (tables.contains("localstorage") ? "localstorage" : nil)
        guard let table else {
            logger?("Safari local storage missing ItemTable/localstorage tables (found: \(tables.sorted()))")
            return nil
        }

        let refreshToken = fetchLocalStorageValue(db: db, table: table, key: "workos:refresh-token")
        guard let refreshToken, !refreshToken.isEmpty else {
            logger?("Safari local storage missing workos:refresh-token")
            return nil
        }
        let accessToken = fetchLocalStorageValue(db: db, table: table, key: "workos:access-token")
        let organizationID = extractOrganizationID(from: accessToken)
        return WorkOSTokenMatch(refreshToken: refreshToken, accessToken: accessToken, organizationID: organizationID)
    }

    private static func extractOrganizationID(from accessToken: String?) -> String? {
        guard let accessToken, accessToken.contains(".") else { return nil }
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json["org_id"] as? String
    }

    private static func fetchTableNames(db: OpaquePointer?, logger: ((String) -> Void)? = nil) -> Set<String> {
        let sql = "SELECT name FROM sqlite_master WHERE type='table'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if let c = sqlite3_errmsg(db) {
                logger?("Safari local storage table query failed: \(String(cString: c))")
            }
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var names = Set<String>()
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) {
                names.insert(String(cString: c))
            } else {
                break
            }
        }
        return names
    }

    private static func fetchLocalStorageValue(db: OpaquePointer?, table: String, key: String) -> String? {
        let sql = "SELECT value FROM \(table) WHERE key = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = key.withCString { sqlite3_bind_text(stmt, 1, $0, -1, transient) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return decodeSQLiteValue(stmt: stmt, index: 0)
    }

    private static func decodeSQLiteValue(stmt: OpaquePointer?, index: Int32) -> String? {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_TEXT:
            guard let c = sqlite3_column_text(stmt, index) else { return nil }
            return String(cString: c)
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(stmt, index) else { return nil }
            let count = Int(sqlite3_column_bytes(stmt, index))
            let data = Data(bytes: bytes, count: count)
            return decodeValueData(data)
        default:
            return nil
        }
    }

    private static func decodeValueData(_ data: Data) -> String? {
        if let decoded = String(data: data, encoding: .utf16LittleEndian) {
            return decoded.trimmingCharacters(in: .controlCharacters)
        }
        if let decoded = String(data: data, encoding: .utf8) {
            return decoded.trimmingCharacters(in: .controlCharacters)
        }
        if let decoded = String(data: data, encoding: .isoLatin1) {
            return decoded.trimmingCharacters(in: .controlCharacters)
        }
        return nil
    }

    private static func matchToken(in contents: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        guard let match = regex.matches(in: contents, options: [], range: range).last,
              match.numberOfRanges > 1,
              let tokenRange = Range(match.range(at: 1), in: contents)
        else {
            return nil
        }
        return String(contents[tokenRange])
    }
}

struct FactoryWorkOSAuthResponse: Decodable, Sendable {
    let access_token: String
    let refresh_token: String?
    let organization_id: String?
}

enum FactoryWorkOSAuthenticator {
    private static let workOSClientIDs = [
        "client_01HXRMBQ9BJ3E7QSTQ9X2PHVB7",
        "client_01HNM792M5G5G1A2THWPXKFMXB",
    ]

    static func fetchAccessToken(
        refreshToken: String,
        organizationID: String? = nil,
        timeout: TimeInterval = 20
    ) async throws -> FactoryWorkOSAuthResponse {
        var lastError: Error?
        for clientID in workOSClientIDs {
            do {
                var body: [String: Any] = [
                    "client_id": clientID,
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                ]
                if let organizationID {
                    body["organization_id"] = organizationID
                }
                return try await fetchAccessToken(
                    body: body,
                    cookieHeader: nil,
                    timeout: timeout
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FactoryQuotaError.notLoggedIn
    }

    static func fetchAccessTokenWithCookies(
        cookieHeader: String,
        organizationID: String? = nil,
        timeout: TimeInterval = 20
    ) async throws -> FactoryWorkOSAuthResponse {
        var lastError: Error?
        for clientID in workOSClientIDs {
            do {
                var body: [String: Any] = [
                    "client_id": clientID,
                    "grant_type": "refresh_token",
                    "useCookie": true,
                ]
                if let organizationID {
                    body["organization_id"] = organizationID
                }
                return try await fetchAccessToken(
                    body: body,
                    cookieHeader: cookieHeader,
                    timeout: timeout
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? FactoryQuotaError.notLoggedIn
    }

    static func browserCookieCandidates(logger: ((String) -> Void)? = nil) -> [QuotaBrowserCookieSession] {
        let browsers: [Browser] = [.safari, .chrome, .firefox, .edge, .brave, .arc, .chromium]
        let query = BrowserCookieQuery(domains: ["workos.com"])
        let client = BrowserCookieClient()
        var sessions: [QuotaBrowserCookieSession] = []
        for browser in browsers {
            do {
                let sources = try client.records(matching: query, in: browser, logger: logger)
                for source in sources where !source.records.isEmpty {
                    let cookies = BrowserCookieClient.makeHTTPCookies(source.records, origin: query.origin)
                    guard !cookies.isEmpty else { continue }
                    sessions.append(QuotaBrowserCookieSession(cookies: cookies, sourceLabel: source.label))
                }
            } catch {
                continue
            }
        }
        var seen = Set<String>()
        return sessions.filter { seen.insert($0.cookieHeader).inserted }
    }

    static func isMissingRefreshTokenError(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let description = json["error_description"] as? String
        else {
            return false
        }
        return description.localizedCaseInsensitiveContains("missing refresh token")
    }

    static func isInvalidGrant(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("invalid_grant")
    }

    private static func fetchAccessToken(
        body: [String: Any],
        cookieHeader: String?,
        timeout: TimeInterval
    ) async throws -> FactoryWorkOSAuthResponse {
        guard let url = URL(string: "https://api.workos.com/user_management/authenticate") else {
            throw FactoryQuotaError.apiError("WorkOS auth URL unavailable")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let cookieHeader, !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FactoryQuotaError.apiError("Invalid WorkOS response")
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 400, isMissingRefreshTokenError(data) {
                throw FactoryQuotaError.missingCookie
            }
            let bodyText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "<binary>"
            let snippet = bodyText.isEmpty ? "" : ": \(bodyText.prefix(200))"
            throw FactoryQuotaError.apiError("WorkOS HTTP \(httpResponse.statusCode)\(snippet)")
        }
        return try JSONDecoder().decode(FactoryWorkOSAuthResponse.self, from: data)
    }
}

struct MiniMaxLocalStorageTokenInfo: Sendable {
    let accessToken: String
    let groupID: String?
    let sourceLabel: String
}

enum MiniMaxLocalStorageImporter {
    static func importAccessTokens(logger: ((String) -> Void)? = nil) -> [MiniMaxLocalStorageTokenInfo] {
        let log: (String) -> Void = { msg in logger?("[minimax-storage] \(msg)") }
        var tokens: [MiniMaxLocalStorageTokenInfo] = []

        let chromeCandidates = chromeLocalStorageCandidates()
        if !chromeCandidates.isEmpty {
            log("Chromium local storage candidates: \(chromeCandidates.count)")
        }

        for candidate in chromeCandidates {
            let snapshot = readLocalStorage(from: candidate.kind, logger: log)
            if !snapshot.tokens.isEmpty {
                let groupID = snapshot.groupID ?? groupID(fromJWT: snapshot.tokens.first ?? "")
                for token in snapshot.tokens {
                    tokens.append(
                        MiniMaxLocalStorageTokenInfo(
                            accessToken: token,
                            groupID: groupID,
                            sourceLabel: candidate.label
                        )
                    )
                }
            }
        }

        if tokens.isEmpty {
            let sessionCandidates = chromeSessionStorageCandidates()
            if !sessionCandidates.isEmpty {
                log("Chromium session storage candidates: \(sessionCandidates.count)")
            }
            for candidate in sessionCandidates {
                let sessionTokens = readSessionStorageTokens(from: candidate.url, logger: log)
                for token in sessionTokens {
                    tokens.append(
                        MiniMaxLocalStorageTokenInfo(
                            accessToken: token,
                            groupID: groupID(fromJWT: token),
                            sourceLabel: candidate.label
                        )
                    )
                }
            }
        }

        if tokens.isEmpty {
            let indexedCandidates = chromeIndexedDBCandidates()
            if !indexedCandidates.isEmpty {
                log("Chromium IndexedDB candidates: \(indexedCandidates.count)")
            }
            for candidate in indexedCandidates {
                let indexedTokens = readIndexedDBTokens(from: candidate.url, logger: log)
                for token in indexedTokens {
                    tokens.append(
                        MiniMaxLocalStorageTokenInfo(
                            accessToken: token,
                            groupID: groupID(fromJWT: token),
                            sourceLabel: candidate.label
                        )
                    )
                }
            }
        }

        return deduplicated(tokens)
    }

    static func normalizeSourceLabel(_ label: String) -> String {
        let suffixes = [" (Session Storage)", " (IndexedDB)"]
        for suffix in suffixes where label.hasSuffix(suffix) {
            return String(label.dropLast(suffix.count))
        }
        return label
    }

    private enum LocalStorageKind {
        case chromeLevelDB(URL)
    }

    private struct LocalStorageCandidate {
        let label: String
        let kind: LocalStorageKind
    }

    private struct SessionStorageCandidate {
        let label: String
        let url: URL
    }

    private struct IndexedDBCandidate {
        let label: String
        let url: URL
    }

    private struct LocalStorageSnapshot {
        let tokens: [String]
        let groupID: String?
    }

    private static func candidateBrowsers() -> [Browser] {
        [
            .chrome, .chromeBeta, .chromeCanary, .edge, .edgeBeta, .edgeCanary,
            .brave, .braveBeta, .braveNightly, .vivaldi, .arc, .arcBeta,
            .arcCanary, .dia, .chatgptAtlas, .chromium, .helium
        ]
    }

    private static func chromeLocalStorageCandidates() -> [LocalStorageCandidate] {
        let roots = ChromiumProfileLocator.roots(for: candidateBrowsers(), homeDirectories: BrowserCookieClient.defaultHomeDirectories())
        return roots.flatMap { chromeProfileLocalStorageDirs(root: $0.url, labelPrefix: $0.labelPrefix) }
    }

    private static func chromeSessionStorageCandidates() -> [SessionStorageCandidate] {
        let roots = ChromiumProfileLocator.roots(for: candidateBrowsers(), homeDirectories: BrowserCookieClient.defaultHomeDirectories())
        return roots.flatMap { chromeProfileSessionStorageDirs(root: $0.url, labelPrefix: $0.labelPrefix) }
    }

    private static func chromeIndexedDBCandidates() -> [IndexedDBCandidate] {
        let roots = ChromiumProfileLocator.roots(for: candidateBrowsers(), homeDirectories: BrowserCookieClient.defaultHomeDirectories())
        return roots.flatMap { chromeProfileIndexedDBDirs(root: $0.url, labelPrefix: $0.labelPrefix) }
    }

    private static func chromeProfileLocalStorageDirs(root: URL, labelPrefix: String) -> [LocalStorageCandidate] {
        profileDirectories(root: root).compactMap { dir in
            let levelDBURL = dir.appendingPathComponent("Local Storage").appendingPathComponent("leveldb")
            guard FileManager.default.fileExists(atPath: levelDBURL.path) else { return nil }
            return LocalStorageCandidate(label: "\(labelPrefix) \(dir.lastPathComponent)", kind: .chromeLevelDB(levelDBURL))
        }
    }

    private static func chromeProfileSessionStorageDirs(root: URL, labelPrefix: String) -> [SessionStorageCandidate] {
        profileDirectories(root: root).compactMap { dir in
            let sessionURL = dir.appendingPathComponent("Session Storage")
            guard FileManager.default.fileExists(atPath: sessionURL.path) else { return nil }
            return SessionStorageCandidate(label: "\(labelPrefix) \(dir.lastPathComponent) (Session Storage)", url: sessionURL)
        }
    }

    private static func chromeProfileIndexedDBDirs(root: URL, labelPrefix: String) -> [IndexedDBCandidate] {
        let targetPrefixes = [
            "https_platform.minimax.io_",
            "https_www.minimax.io_",
            "https_minimax.io_",
            "https_platform.minimaxi.com_",
            "https_minimaxi.com_",
            "https_www.minimaxi.com_",
        ]

        return profileDirectories(root: root).flatMap { dir -> [IndexedDBCandidate] in
            let indexedDBRoot = dir.appendingPathComponent("IndexedDB")
            guard let dbEntries = try? FileManager.default.contentsOfDirectory(
                at: indexedDBRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return dbEntries.compactMap { entry in
                guard let isDir = try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                      isDir == true
                else {
                    return nil
                }
                let name = entry.lastPathComponent
                guard targetPrefixes.contains(where: { name.hasPrefix($0) }),
                      name.hasSuffix(".indexeddb.leveldb")
                else {
                    return nil
                }
                return IndexedDBCandidate(label: "\(labelPrefix) \(dir.lastPathComponent) (IndexedDB)", url: entry)
            }
        }
    }

    private static func profileDirectories(root: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return entries.filter { url in
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir == true else {
                return false
            }
            let name = url.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func readLocalStorage(from kind: LocalStorageKind, logger: ((String) -> Void)? = nil) -> LocalStorageSnapshot {
        let levelDBURL: URL = switch kind {
        case let .chromeLevelDB(url): url
        }

        let origins = [
            "https://platform.minimax.io",
            "https://www.minimax.io",
            "https://minimax.io",
            "https://platform.minimaxi.com",
            "https://www.minimaxi.com",
            "https://minimaxi.com",
        ]
        var entries: [ChromiumLocalStorageEntry] = []
        for origin in origins {
            entries.append(contentsOf: ChromiumLocalStorageReader.readEntries(for: origin, in: levelDBURL, logger: logger))
        }

        var tokens: [String] = []
        var seen = Set<String>()
        var groupID: String?
        var hasMiniMaxSignal = !entries.isEmpty

        for entry in entries {
            let extracted = extractAccessTokens(from: entry.value)
            for token in extracted where !seen.contains(token) {
                seen.insert(token)
                tokens.append(token)
            }
            if groupID == nil, let match = extractGroupID(from: entry.value) {
                groupID = match
            }
        }

        if tokens.isEmpty {
            let textEntries = ChromiumLocalStorageReader.readTextEntries(in: levelDBURL, logger: logger)
            let candidateEntries = textEntries.filter { entry in
                let key = entry.key.lowercased()
                let value = entry.value.lowercased()
                return key.contains("minimax.io") || value.contains("minimax.io") ||
                    key.contains("minimaxi.com") || value.contains("minimaxi.com")
            }
            hasMiniMaxSignal = hasMiniMaxSignal || !candidateEntries.isEmpty
            for entry in candidateEntries {
                let extracted = extractAccessTokens(from: entry.value)
                for token in extracted where !seen.contains(token) {
                    if token.contains("."), !isMiniMaxJWT(token) {
                        continue
                    }
                    seen.insert(token)
                    tokens.append(token)
                }
                if groupID == nil, let match = extractGroupID(from: entry.value) {
                    groupID = match
                }
            }
        }

        if tokens.isEmpty, hasMiniMaxSignal {
            let rawCandidates = ChromiumLocalStorageReader.readTokenCandidates(in: levelDBURL, minimumLength: 60, logger: logger)
            for candidate in rawCandidates where looksLikeToken(candidate) && isMiniMaxJWT(candidate) && !seen.contains(candidate) {
                seen.insert(candidate)
                tokens.append(candidate)
                if groupID == nil {
                    groupID = Self.groupID(fromJWT: candidate)
                }
            }
        }

        return LocalStorageSnapshot(tokens: tokens, groupID: groupID)
    }

    private static func readSessionStorageTokens(from levelDBURL: URL, logger: ((String) -> Void)? = nil) -> [String] {
        let entries = ChromiumLocalStorageReader.readTextEntries(in: levelDBURL, logger: logger)
        guard !entries.isEmpty else { return [] }

        let origins = [
            "https://platform.minimax.io",
            "https://www.minimax.io",
            "https://minimax.io",
            "https://platform.minimaxi.com",
            "https://www.minimaxi.com",
            "https://minimaxi.com",
        ]
        let mapIDs = sessionStorageMapIDs(in: entries, origins: origins)
        guard !mapIDs.isEmpty else { return [] }

        let mapEntries = entries.filter { entry in
            guard let mapID = sessionStorageMapID(fromKey: entry.key) else { return false }
            return mapIDs.contains(mapID)
        }

        var tokens: [String] = []
        var seen = Set<String>()
        for entry in mapEntries {
            for token in extractAccessTokens(from: entry.value) where !seen.contains(token) {
                seen.insert(token)
                tokens.append(token)
            }
        }
        return tokens
    }

    private static func readIndexedDBTokens(from levelDBURL: URL, logger: ((String) -> Void)? = nil) -> [String] {
        let entries = ChromiumLocalStorageReader.readTextEntries(in: levelDBURL, logger: logger)
        var tokens: [String] = []
        var seen = Set<String>()
        for entry in entries {
            for token in extractAccessTokens(from: entry.value) where !seen.contains(token) {
                seen.insert(token)
                tokens.append(token)
            }
        }
        if tokens.isEmpty {
            let rawCandidates = ChromiumLocalStorageReader.readTokenCandidates(in: levelDBURL, minimumLength: 60, logger: logger)
            for candidate in rawCandidates where looksLikeToken(candidate) && !seen.contains(candidate) {
                seen.insert(candidate)
                tokens.append(candidate)
            }
        }
        return tokens
    }

    private static func sessionStorageMapIDs(
        in entries: [ChromiumLevelDBTextEntry],
        origins: [String]
    ) -> Set<Int> {
        var mapIDs = Set<Int>()
        for entry in entries where entry.key.hasPrefix("namespace-") {
            for origin in origins where entry.key.localizedCaseInsensitiveContains(origin) {
                if let mapID = Int(entry.value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    mapIDs.insert(mapID)
                }
            }
        }
        return mapIDs
    }

    private static func sessionStorageMapID(fromKey key: String) -> Int? {
        guard key.hasPrefix("map-") else { return nil }
        let parts = key.split(separator: "-", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }

    private static func extractAccessTokens(from value: String) -> [String] {
        var tokens = Set<String>()
        let patterns = [
            #"access_token[^A-Za-z0-9._\-+=/]+([A-Za-z0-9._\-+=/]{20,})"#,
            #"accessToken[^A-Za-z0-9._\-+=/]+([A-Za-z0-9._\-+=/]{20,})"#,
            #"id_token[^A-Za-z0-9._\-+=/]+([A-Za-z0-9._\-+=/]{20,})"#,
            #"idToken[^A-Za-z0-9._\-+=/]+([A-Za-z0-9._\-+=/]{20,})"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            for match in regex.matches(in: value, options: [], range: range) {
                guard match.numberOfRanges > 1, let tokenRange = Range(match.range(at: 1), in: value) else { continue }
                tokens.insert(String(value[tokenRange]))
            }
        }

        if let data = value.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
            tokens.formUnion(collectTokens(from: json))
        }
        if let jwtMatches = matchJWTs(in: value) {
            tokens.formUnion(jwtMatches)
        }

        let preferred = tokens.filter { $0.count >= 60 }
        return preferred.isEmpty ? Array(tokens) : Array(preferred)
    }

    nonisolated private static func collectTokens(from value: Any) -> [String] {
        switch value {
        case let dict as [String: Any]:
            return dict.flatMap { key, child -> [String] in
                if tokenKeys.contains(key), let string = child as? String, looksLikeToken(string) {
                    return [string]
                }
                return collectTokens(from: child)
            }
        case let array as [Any]:
            return array.flatMap(collectTokens)
        case let string as String:
            if looksLikeToken(string) {
                return [string]
            }
            if let data = string.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
                return collectTokens(from: json)
            }
            return []
        default:
            return []
        }
    }

    private static let tokenKeys: Set<String> = [
        "access_token", "accessToken", "id_token", "idToken", "token", "authToken", "authorization", "bearer",
    ]

    private static func looksLikeToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("."), trimmed.split(separator: ".").count >= 3 {
            return trimmed.count >= 60
        }
        return trimmed.count >= 60 &&
            trimmed.range(of: #"^[A-Za-z0-9._\-+=/]+$"#, options: .regularExpression) != nil
    }

    private static func matchJWTs(in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, options: [], range: range)
        guard !matches.isEmpty else { return nil }
        return matches.compactMap { match in
            guard let tokenRange = Range(match.range(at: 0), in: value) else { return nil }
            return String(value[tokenRange])
        }
    }

    private static func isMiniMaxJWT(_ token: String) -> Bool {
        guard let claims = decodeJWTClaims(token) else { return false }
        if let iss = claims["iss"] as? String, iss.localizedCaseInsensitiveContains("minimax") {
            return true
        }
        let signalKeys = ["GroupID", "GroupName", "UserName", "SubjectID", "Mail", "TokenType"]
        return signalKeys.contains(where: { claims[$0] != nil })
    }

    private static func extractGroupID(from value: String) -> String? {
        if let data = value.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let match = extractGroupID(from: json)
        {
            return match
        }

        for marker in ["groups\":[", "groupId\":\"", "group_id\":\""] {
            guard let range = value.range(of: marker) else { continue }
            let tail = String(value[range.upperBound...].prefix(200))
            if let match = longestDigitSequence(in: tail) {
                return match
            }
        }
        return nil
    }

    private static func extractGroupID(from value: Any) -> String? {
        switch value {
        case let dict as [String: Any]:
            for (key, child) in dict {
                if key.lowercased().contains("group"), let match = stringID(from: child) {
                    return match
                }
                if let nested = extractGroupID(from: child) {
                    return nested
                }
            }
        case let array as [Any]:
            for child in array {
                if let nested = extractGroupID(from: child) {
                    return nested
                }
            }
        default:
            break
        }
        return nil
    }

    private static func groupID(fromJWT token: String) -> String? {
        guard let claims = decodeJWTClaims(token) else { return nil }
        for key in ["group_id", "groupId", "groupID", "gid", "tenant_id", "tenantId", "org_id", "orgId"] {
            if let match = stringID(from: claims[key]) {
                return match
            }
        }
        for (key, value) in claims where key.lowercased().contains("group") {
            if let match = stringID(from: value) {
                return match
            }
        }
        return nil
    }

    private static func decodeJWTClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data),
              let claims = object as? [String: Any]
        else {
            return nil
        }
        return claims
    }

    private static func stringID(from value: Any?) -> String? {
        switch value {
        case let number as Int: return String(number)
        case let number as Int64: return String(number)
        case let number as NSNumber: return String(number.intValue)
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return longestDigitSequence(in: trimmed) ?? (trimmed.isEmpty ? nil : trimmed)
        default:
            return nil
        }
    }

    private static func longestDigitSequence(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[0-9]{4,}"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let candidates = regex.matches(in: text, options: [], range: range).compactMap { match -> String? in
            guard let tokenRange = Range(match.range(at: 0), in: text) else { return nil }
            return String(text[tokenRange])
        }
        return candidates.max(by: { $0.count < $1.count })
    }

    private static func deduplicated(_ tokens: [MiniMaxLocalStorageTokenInfo]) -> [MiniMaxLocalStorageTokenInfo] {
        var seen = Set<String>()
        return tokens.filter {
            let key = "\($0.accessToken)|\($0.groupID ?? "")|\(normalizeSourceLabel($0.sourceLabel))"
            return seen.insert(key).inserted
        }
    }
}

enum AlibabaChromiumCookieFallbackImporter {
    struct ChromiumCookieRecord {
        let domain: String
        let name: String
        let path: String
        let value: String
        let expires: Date?
        let isSecure: Bool
    }

    static func importSession(
        browser: Browser,
        domains: [String],
        logger: ((String) -> Void)? = nil
    ) throws -> QuotaBrowserCookieSession? {
        let stores = BrowserCookieClient().stores(for: browser).filter { $0.databaseURL != nil }
        guard !stores.isEmpty else { return nil }

        let keys = try derivedKeys(for: browser)
        for store in stores {
            let cookies = try loadCookies(from: store, domains: domains, keys: keys, logger: logger)
            guard !cookies.isEmpty else { continue }
            if isAuthenticatedSession(cookies) {
                return QuotaBrowserCookieSession(cookies: cookies, sourceLabel: store.label)
            }
        }
        return nil
    }

    static func isAuthenticatedSession(_ cookies: [HTTPCookie]) -> Bool {
        let names = Set(cookies.map(\.name))
        let hasTicket = names.contains("login_aliyunid_ticket")
        let hasAccount = names.contains("login_aliyunid_pk") || names.contains("login_current_pk") || names.contains("login_aliyunid")
        return hasTicket && hasAccount
    }

    private static func loadCookies(
        from store: BrowserCookieStore,
        domains: [String],
        keys: [Data],
        logger: ((String) -> Void)? = nil
    ) throws -> [HTTPCookie] {
        guard let sourceDB = store.databaseURL else { return [] }
        let records = try readCookiesFromLockedDB(sourceDB: sourceDB, domains: domains, keys: keys, label: store.label)
        return records.compactMap(makeCookie).filter { cookie in
            guard let expires = cookie.expiresDate else { return true }
            return expires >= Date()
        }
    }

    private static func readCookiesFromLockedDB(
        sourceDB: URL,
        domains: [String],
        keys: [Data],
        label: String
    ) throws -> [ChromiumCookieRecord] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("alibaba-chromium-cookies-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let copiedDB = tempDir.appendingPathComponent("Cookies")
        try FileManager.default.copyItem(at: sourceDB, to: copiedDB)
        for suffix in ["-wal", "-shm"] {
            let src = URL(fileURLWithPath: sourceDB.path + suffix)
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.copyItem(at: src, to: URL(fileURLWithPath: copiedDB.path + suffix))
            }
        }

        return try readCookies(fromDB: copiedDB.path, domains: domains, keys: keys, label: label)
    }

    private static func readCookies(
        fromDB path: String,
        domains: [String],
        keys: [Data],
        label: String
    ) throws -> [ChromiumCookieRecord] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw NSError(domain: "AlibabaChromiumCookieFallbackImporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open \(label) cookie database"])
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT host_key, name, path, expires_utc, is_secure, value, encrypted_value FROM cookies"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "AlibabaChromiumCookieFallbackImporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not query \(label) cookie database"])
        }
        defer { sqlite3_finalize(stmt) }

        var records: [ChromiumCookieRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let hostKey = readText(stmt, index: 0), matches(domain: hostKey, patterns: domains),
                  let name = readText(stmt, index: 1),
                  let path = readText(stmt, index: 2)
            else {
                continue
            }

            let value: String? = if let plain = readText(stmt, index: 5), !plain.isEmpty {
                plain
            } else if let encrypted = readBlob(stmt, index: 6) {
                decrypt(encrypted, usingAnyOf: keys)
            } else {
                nil
            }
            guard let value, !value.isEmpty else { continue }

            records.append(
                ChromiumCookieRecord(
                    domain: normalizeCookieDomain(hostKey),
                    name: name,
                    path: path,
                    value: value,
                    expires: chromiumExpiry(sqlite3_column_int64(stmt, 3)),
                    isSecure: sqlite3_column_int(stmt, 4) != 0
                )
            )
        }
        return records
    }

    private static func derivedKeys(for browser: Browser) throws -> [Data] {
        let keys = browser.safeStorageLabels.compactMap { safeStoragePassword(service: $0.service, account: $0.account) }
            .map(deriveKey)
        if !keys.isEmpty { return keys }
        throw NSError(domain: "AlibabaChromiumCookieFallbackImporter", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(browser.displayName) Safe Storage key not found"])
    }

    private static func safeStoragePassword(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func deriveKey(from password: String) -> Data {
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let keyLength = key.count
        _ = key.withUnsafeMutableBytes { keyBytes in
            password.utf8CString.withUnsafeBytes { passBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.bindMemory(to: Int8.self).baseAddress,
                        passBytes.count - 1,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyLength
                    )
                }
            }
        }
        return key
    }

    private static func decrypt(_ encryptedValue: Data, usingAnyOf keys: [Data]) -> String? {
        for key in keys {
            if let value = decrypt(encryptedValue, key: key) {
                return value
            }
        }
        return nil
    }

    private static func decrypt(_ encryptedValue: Data, key: Data) -> String? {
        guard encryptedValue.count > 3, String(data: encryptedValue.prefix(3), encoding: .utf8) == "v10" else {
            return nil
        }

        let payload = Data(encryptedValue.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var outLength = 0
        var out = Data(count: payload.count + kCCBlockSizeAES128)
        let outCapacity = out.count
        let status = out.withUnsafeMutableBytes { outBytes in
            payload.withUnsafeBytes { payloadBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            payloadBytes.baseAddress,
                            payload.count,
                            outBytes.baseAddress,
                            outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.count = outLength

        if let value = String(data: out, encoding: .utf8), !value.isEmpty {
            return value
        }
        if out.count > 32 {
            let trimmed = out.dropFirst(32)
            if let value = String(data: trimmed, encoding: .utf8), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    nonisolated private static func makeCookie(from record: ChromiumCookieRecord) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: record.domain,
            .path: record.path,
            .name: record.name,
            .value: record.value,
        ]
        if record.isSecure {
            properties[.secure] = true
        }
        if let expires = record.expires {
            properties[.expires] = expires
        }
        return HTTPCookie(properties: properties)
    }

    private static func readText(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let value = sqlite3_column_text(stmt, index)
        else {
            return nil
        }
        return String(cString: value)
    }

    private static func readBlob(_ stmt: OpaquePointer?, index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let bytes = sqlite3_column_blob(stmt, index)
        else {
            return nil
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, index)))
    }

    private static func matches(domain: String, patterns: [String]) -> Bool {
        let normalized = normalizeCookieDomain(domain)
        return patterns.contains { pattern in
            let normalizedPattern = normalizeCookieDomain(pattern)
            return normalized == normalizedPattern || normalized.hasSuffix(".\(normalizedPattern)")
        }
    }

    private static func normalizeCookieDomain(_ domain: String) -> String {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
        return normalized.lowercased()
    }

    private static func chromiumExpiry(_ expiresUTC: Int64) -> Date? {
        guard expiresUTC > 0 else { return nil }
        let seconds = (Double(expiresUTC) / 1_000_000.0) - 11_644_473_600.0
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

#endif
