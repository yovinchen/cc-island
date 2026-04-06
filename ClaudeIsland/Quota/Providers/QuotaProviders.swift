//
//  QuotaProviders.swift
//  ClaudeIsland
//

import Foundation

private struct UnsupportedQuotaProvider: QuotaProvider {
    let descriptor: QuotaProviderDescriptor
    let message: String

    func isConfigured() -> Bool { false }

    func fetch() async throws -> QuotaSnapshot {
        throw QuotaProviderError.unsupported(message)
    }
}

enum QuotaProviderRegistry {
    private static let providers: [QuotaProviderID: any QuotaProvider] = {
        let descriptors: [QuotaProviderDescriptor] = [
            QuotaProviderDescriptor(
                id: .codex,
                sourceKind: .oauth,
                credentialHint: "Reads ~/.codex/auth.json",
                supportsManualSecret: false,
                defaultEnabled: true,
                refreshInterval: 300
            ),
            QuotaProviderDescriptor(
                id: .claude,
                sourceKind: .oauth,
                credentialHint: "Reads ~/.claude/.credentials.json",
                supportsManualSecret: false,
                defaultEnabled: true,
                refreshInterval: 300
            ),
            QuotaProviderDescriptor(
                id: .gemini,
                sourceKind: .oauth,
                credentialHint: "Reads ~/.gemini/oauth_creds.json",
                supportsManualSecret: false,
                defaultEnabled: true,
                refreshInterval: 300
            ),
            QuotaProviderDescriptor(
                id: .kiro,
                sourceKind: .cli,
                credentialHint: "Uses kiro-cli /usage",
                supportsManualSecret: false,
                defaultEnabled: true,
                refreshInterval: 300
            ),
            QuotaProviderDescriptor(
                id: .openrouter,
                sourceKind: .apiKey,
                credentialHint: "Uses OPENROUTER_API_KEY or saved token",
                supportsManualSecret: true,
                defaultEnabled: true,
                refreshInterval: 300
            ),
            QuotaProviderDescriptor(
                id: .warp,
                sourceKind: .apiKey,
                credentialHint: "Uses WARP_API_KEY or saved token",
                supportsManualSecret: true,
                defaultEnabled: true,
                refreshInterval: 300
            ),
            QuotaProviderDescriptor(
                id: .kimiK2,
                sourceKind: .apiKey,
                credentialHint: "Uses KIMI_K2_API_KEY or saved token",
                supportsManualSecret: true,
                defaultEnabled: true,
                refreshInterval: 300
            ),
            QuotaProviderDescriptor(
                id: .zai,
                sourceKind: .apiKey,
                credentialHint: "Uses Z_AI_API_KEY or saved token",
                supportsManualSecret: true,
                defaultEnabled: true,
                refreshInterval: 300
            ),
        ]

        return Dictionary(uniqueKeysWithValues: descriptors.map { descriptor in
            (
                descriptor.id,
                UnsupportedQuotaProvider(
                    descriptor: descriptor,
                    message: "\(descriptor.id.displayName) quota fetcher is not wired yet."
                ) as any QuotaProvider
            )
        })
    }()

    static func provider(for id: QuotaProviderID) -> (any QuotaProvider)? {
        providers[id]
    }

    static var descriptors: [QuotaProviderDescriptor] {
        QuotaProviderID.allCases.compactMap { providers[$0]?.descriptor }
    }

    static func secretAccountName(for id: QuotaProviderID) -> String {
        "quota.token.\(id.rawValue)"
    }
}
