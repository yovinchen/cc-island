//
//  QuotaModels.swift
//  ClaudeIsland
//
//  Account-level quota domain models.
//

import Foundation

enum QuotaProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude
    case gemini
    case antigravity
    case copilot
    case cursor
    case alibaba
    case factory
    case opencode
    case amp
    case augment
    case kimi
    case kilo
    case kiro
    case vertexAI = "vertexai"
    case jetbrains
    case minimax
    case ollama
    case openrouter
    case perplexity
    case warp
    case kimiK2 = "kimi_k2"
    case zai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .antigravity: return "Antigravity"
        case .copilot: return "Copilot"
        case .cursor: return "Cursor"
        case .alibaba: return "Alibaba"
        case .factory: return "Droid"
        case .opencode: return "OpenCode"
        case .amp: return "Amp"
        case .augment: return "Augment"
        case .kimi: return "Kimi"
        case .kilo: return "Kilo"
        case .kiro: return "Kiro"
        case .vertexAI: return "Vertex AI"
        case .jetbrains: return "JetBrains AI"
        case .minimax: return "MiniMax"
        case .ollama: return "Ollama"
        case .openrouter: return "OpenRouter"
        case .perplexity: return "Perplexity"
        case .warp: return "Warp"
        case .kimiK2: return "Kimi K2"
        case .zai: return "z.ai"
        }
    }

    var shortName: String {
        switch self {
        case .openrouter: return "OR"
        case .copilot: return "GH"
        case .cursor: return "CS"
        case .alibaba: return "AL"
        case .factory: return "DR"
        case .opencode: return "OC"
        case .amp: return "AMP"
        case .augment: return "AU"
        case .vertexAI: return "VA"
        case .jetbrains: return "JB"
        case .minimax: return "MM"
        case .perplexity: return "PX"
        case .kimiK2: return "K2"
        case .kilo: return "KL"
        case .ollama: return "OL"
        case .antigravity: return "AG"
        default: return displayName
        }
    }

    var systemImageName: String {
        switch self {
        case .codex: return "triangle.3d"
        case .claude: return "sun.max"
        case .gemini: return "sparkle"
        case .antigravity: return "sparkles.square.filled.on.square"
        case .copilot: return "person.crop.circle.badge.checkmark"
        case .cursor: return "cursorarrow.rays"
        case .alibaba: return "building.2"
        case .factory: return "fanblades"
        case .opencode: return "curlybraces.square"
        case .amp: return "bolt.circle"
        case .augment: return "wand.and.stars"
        case .kimi: return "moon.stars"
        case .kilo: return "creditcard.and.123"
        case .kiro: return "terminal"
        case .vertexAI: return "cloud"
        case .jetbrains: return "chevron.left.forwardslash.chevron.right"
        case .minimax: return "waveform.path.ecg"
        case .ollama: return "cube.transparent"
        case .openrouter: return "network"
        case .perplexity: return "questionmark.circle"
        case .warp: return "paperplane"
        case .kimiK2: return "creditcard"
        case .zai: return "chart.xyaxis.line"
        }
    }
}

enum QuotaSourceKind: String, Codable, Sendable {
    case oauth
    case apiKey
    case cli
    case event
    case local
    case web
}

enum QuotaSourcePreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto
    case oauth
    case apiKey
    case cli
    case local
    case web

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return String(localized: "quota.source.auto")
        case .oauth:
            return String(localized: "quota.source.oauth")
        case .apiKey:
            return String(localized: "quota.source.api_key")
        case .cli:
            return String(localized: "quota.source.cli")
        case .local:
            return String(localized: "quota.source.local")
        case .web:
            return String(localized: "quota.source.web")
        }
    }

    var sourceKind: QuotaSourceKind? {
        switch self {
        case .auto:
            return nil
        case .oauth:
            return .oauth
        case .apiKey:
            return .apiKey
        case .cli:
            return .cli
        case .local:
            return .local
        case .web:
            return .web
        }
    }

    static func from(sourceKind: QuotaSourceKind) -> QuotaSourcePreference {
        switch sourceKind {
        case .oauth:
            return .oauth
        case .apiKey:
            return .apiKey
        case .cli:
            return .cli
        case .local:
            return .local
        case .web:
            return .web
        case .event:
            return .auto
        }
    }
}

enum QuotaProviderStatus: String, Codable, Sendable {
    case connected
    case needsConfiguration
    case refreshing
    case stale
    case error
}

struct QuotaWindow: Identifiable, Equatable, Sendable {
    let label: String
    let usedRatio: Double
    let detail: String?
    let resetsAt: Date?

    var id: String { label }

    var clampedUsedRatio: Double {
        min(max(usedRatio, 0), 1)
    }
}

struct QuotaCredits: Equatable, Sendable {
    let label: String
    let used: Double?
    let total: Double?
    let remaining: Double?
    let currencyCode: String?
    let isUnlimited: Bool
}

struct QuotaIdentity: Equatable, Sendable {
    let email: String?
    let organization: String?
    let plan: String?
    let detail: String?
}

struct QuotaSnapshot: Equatable, Sendable {
    let providerID: QuotaProviderID
    let source: QuotaSourceKind
    let primaryWindow: QuotaWindow?
    let secondaryWindow: QuotaWindow?
    let tertiaryWindow: QuotaWindow?
    let credits: QuotaCredits?
    let identity: QuotaIdentity?
    let updatedAt: Date
    let note: String?
}

struct QuotaDiagnostics: Equatable, Sendable {
    var lastError: String?
    var lastSuccessAt: Date?
    var lastRefreshAttemptAt: Date?
    var sourceLabel: String?
}

struct QuotaProviderDescriptor: Equatable, Sendable {
    let id: QuotaProviderID
    let sourceKind: QuotaSourceKind
    let supportedSources: [QuotaSourceKind]
    let cliBinaryName: String?
    let primaryLabel: String
    let secondaryLabel: String?
    let credentialHint: String
    let credentialPlaceholder: String?
    let supportsManualSecret: Bool
    let defaultEnabled: Bool
    let refreshInterval: TimeInterval
    let dashboardURL: String?
    let statusURL: String?
    let sortPriority: Int
}

struct QuotaProviderRecord: Identifiable, Equatable, Sendable {
    let descriptor: QuotaProviderDescriptor
    var isEnabled: Bool
    var isConfigured: Bool
    var status: QuotaProviderStatus
    var snapshot: QuotaSnapshot?
    var diagnostics: QuotaDiagnostics

    var id: QuotaProviderID { descriptor.id }

    var displayName: String { descriptor.id.displayName }

    var primaryLabel: String {
        snapshot?.primaryWindow?.label ?? descriptor.primaryLabel
    }

    var secondaryLabel: String? {
        snapshot?.secondaryWindow?.label ?? descriptor.secondaryLabel
    }

    var dashboardURL: String? { descriptor.dashboardURL }

    var statusURL: String? { descriptor.statusURL }

    var credentialPlaceholder: String {
        descriptor.credentialPlaceholder ?? descriptor.credentialHint
    }

    var supportsSourceSelection: Bool {
        descriptor.supportedSources.count > 1
    }

    var supportsCLIConfiguration: Bool {
        descriptor.cliBinaryName != nil
    }

    var effectiveSourceLabel: String {
        diagnostics.sourceLabel ?? descriptor.sourceKind.rawValue
    }

    var accountText: String? {
        snapshot?.identity?.email
    }

    var planText: String? {
        snapshot?.identity?.plan
    }

    var organizationText: String? {
        snapshot?.identity?.organization
    }

    var detailText: String? {
        snapshot?.identity?.detail
    }

    var latestErrorText: String? {
        diagnostics.lastError
    }

    var hasSnapshot: Bool {
        snapshot != nil
    }

    var primaryRiskScore: Double {
        snapshot?.primaryWindow?.clampedUsedRatio ?? 0
    }

    var secondaryRiskScore: Double {
        snapshot?.secondaryWindow?.clampedUsedRatio ?? 0
    }

    var tertiaryRiskScore: Double {
        snapshot?.tertiaryWindow?.clampedUsedRatio ?? 0
    }

    var creditsRiskScore: Double {
        guard let credits = snapshot?.credits, !credits.isUnlimited else { return 0 }
        if let used = credits.used, let total = credits.total, total > 0 {
            return min(max(used / total, 0), 1)
        }
        if let remaining = credits.remaining, let total = credits.total, total > 0 {
            return min(max((total - remaining) / total, 0), 1)
        }
        return 0
    }

    var displayRiskScore: Double {
        [
            primaryRiskScore,
            secondaryRiskScore,
            tertiaryRiskScore,
            creditsRiskScore,
        ].max() ?? 0
    }

    var statusText: String {
        switch status {
        case .connected:
            return "Connected"
        case .needsConfiguration:
            return "Needs Configuration"
        case .refreshing:
            return "Refreshing"
        case .stale:
            return "Stale"
        case .error:
            return "Error"
        }
    }

    var lastUpdatedText: String {
        guard let updatedAt = snapshot?.updatedAt ?? diagnostics.lastSuccessAt else {
            return "Never"
        }
        return updatedAt.formatted(date: .omitted, time: .shortened)
    }

    var summaryLine: String {
        if let window = snapshot?.primaryWindow ?? snapshot?.secondaryWindow ?? snapshot?.tertiaryWindow {
            return "\(window.label) \(Int(window.clampedUsedRatio * 100))%"
        }
        if let credits = snapshot?.credits, credits.isUnlimited {
            return "Unlimited"
        }
        if let credits = snapshot?.credits, let remaining = credits.remaining {
            if credits.isUnlimited {
                return "Unlimited"
            }
            if let currency = credits.currencyCode, currency == "USD" {
                return String(format: "$%.2f left", remaining)
            }
            return String(format: "%.0f left", remaining)
        }
        if let detail = snapshot?.identity?.detail, !detail.isEmpty {
            return detail
        }
        return descriptor.credentialHint
    }

    var statusSortPriority: Int {
        switch status {
        case .error: return 0
        case .stale: return 1
        case .refreshing: return 2
        case .connected: return 3
        case .needsConfiguration: return 4
        }
    }
}
