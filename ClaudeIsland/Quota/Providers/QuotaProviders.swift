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
    private static let providerDescriptors: [QuotaProviderDescriptor] = [
        QuotaProviderDescriptor(
            id: .codex,
            sourceKind: .oauth,
            primaryLabel: "Session",
            secondaryLabel: "Weekly",
            credentialHint: "Reads ~/.codex/auth.json or Codex app-server",
            credentialPlaceholder: nil,
            supportsManualSecret: false,
            defaultEnabled: true,
            refreshInterval: 300,
            dashboardURL: "https://chatgpt.com/codex/settings/usage",
            statusURL: "https://status.openai.com/",
            sortPriority: 0
        ),
        QuotaProviderDescriptor(
            id: .claude,
            sourceKind: .oauth,
            primaryLabel: "Session",
            secondaryLabel: "Weekly",
            credentialHint: "Reads Claude OAuth credentials from Keychain or ~/.claude/.credentials.json",
            credentialPlaceholder: nil,
            supportsManualSecret: false,
            defaultEnabled: true,
            refreshInterval: 300,
            dashboardURL: "https://claude.ai/settings/usage",
            statusURL: "https://status.claude.com/",
            sortPriority: 1
        ),
        QuotaProviderDescriptor(
            id: .gemini,
            sourceKind: .oauth,
            primaryLabel: "Pro",
            secondaryLabel: "Flash",
            credentialHint: "Reads ~/.gemini/oauth_creds.json",
            credentialPlaceholder: nil,
            supportsManualSecret: false,
            defaultEnabled: true,
            refreshInterval: 300,
            dashboardURL: "https://gemini.google.com",
            statusURL: "https://www.google.com/appsstatus/dashboard/products/npdyhgECDJ6tB66MxXyo/history",
            sortPriority: 2
        ),
        QuotaProviderDescriptor(
            id: .kiro,
            sourceKind: .cli,
            primaryLabel: "Credits",
            secondaryLabel: "Bonus",
            credentialHint: "Uses kiro-cli chat --no-interactive /usage",
            credentialPlaceholder: nil,
            supportsManualSecret: false,
            defaultEnabled: true,
            refreshInterval: 300,
            dashboardURL: "https://app.kiro.dev/account/usage",
            statusURL: "https://health.aws.amazon.com/health/status",
            sortPriority: 3
        ),
        QuotaProviderDescriptor(
            id: .openrouter,
            sourceKind: .apiKey,
            primaryLabel: "API key limit",
            secondaryLabel: nil,
            credentialHint: "Uses OPENROUTER_API_KEY or a saved API key",
            credentialPlaceholder: "sk-or-v1-...",
            supportsManualSecret: true,
            defaultEnabled: true,
            refreshInterval: 300,
            dashboardURL: "https://openrouter.ai/settings/credits",
            statusURL: "https://status.openrouter.ai",
            sortPriority: 4
        ),
        QuotaProviderDescriptor(
            id: .warp,
            sourceKind: .apiKey,
            primaryLabel: "Credits",
            secondaryLabel: "Add-on credits",
            credentialHint: "Uses WARP_API_KEY / WARP_TOKEN or a saved API key",
            credentialPlaceholder: "wk-...",
            supportsManualSecret: true,
            defaultEnabled: true,
            refreshInterval: 300,
            dashboardURL: "https://docs.warp.dev/reference/cli/api-keys",
            statusURL: nil,
            sortPriority: 5
        ),
        QuotaProviderDescriptor(
            id: .kimiK2,
            sourceKind: .apiKey,
            primaryLabel: "Credits",
            secondaryLabel: nil,
            credentialHint: "Uses KIMI_K2_API_KEY / KIMI_API_KEY or a saved API key",
            credentialPlaceholder: "Paste API key…",
            supportsManualSecret: true,
            defaultEnabled: true,
            refreshInterval: 300,
            dashboardURL: "https://kimi-k2.ai/my-credits",
            statusURL: nil,
            sortPriority: 6
        ),
        QuotaProviderDescriptor(
            id: .zai,
            sourceKind: .apiKey,
            primaryLabel: "Tokens",
            secondaryLabel: "MCP",
            credentialHint: "Uses Z_AI_API_KEY or a saved API key",
            credentialPlaceholder: "Paste API key…",
            supportsManualSecret: true,
            defaultEnabled: true,
            refreshInterval: 300,
            dashboardURL: "https://z.ai/manage-apikey/subscription",
            statusURL: nil,
            sortPriority: 7
        ),
    ]

    private static let providers: [QuotaProviderID: any QuotaProvider] = Dictionary(
        uniqueKeysWithValues: providerDescriptors.map { descriptor in
            let provider: any QuotaProvider
            switch descriptor.id {
            case .openrouter:
                provider = OpenRouterQuotaProvider()
            case .warp:
                provider = WarpQuotaProvider()
            case .kimiK2:
                provider = KimiK2QuotaProvider()
            case .zai:
                provider = ZAIQuotaProvider()
            default:
                provider = UnsupportedQuotaProvider(
                    descriptor: descriptor,
                    message: "\(descriptor.id.displayName) quota fetcher is not wired yet."
                )
            }
            return (descriptor.id, provider)
        }
    )

    static func provider(for id: QuotaProviderID) -> (any QuotaProvider)? {
        providers[id]
    }

    static func descriptor(for id: QuotaProviderID) -> QuotaProviderDescriptor {
        descriptors.first(where: { $0.id == id })!
    }

    static var descriptors: [QuotaProviderDescriptor] {
        providerDescriptors.sorted { lhs, rhs in
            if lhs.sortPriority != rhs.sortPriority {
                return lhs.sortPriority < rhs.sortPriority
            }
            return lhs.id.rawValue < rhs.id.rawValue
        }
    }

    static func secretAccountName(for id: QuotaProviderID) -> String {
        "quota.token.\(id.rawValue)"
    }
}
