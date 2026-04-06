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
    case kiro
    case openrouter
    case warp
    case kimiK2 = "kimi_k2"
    case zai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .kiro: return "Kiro"
        case .openrouter: return "OpenRouter"
        case .warp: return "Warp"
        case .kimiK2: return "Kimi K2"
        case .zai: return "z.ai"
        }
    }

    var shortName: String {
        switch self {
        case .openrouter: return "OR"
        case .kimiK2: return "K2"
        default: return displayName
        }
    }

    var systemImageName: String {
        switch self {
        case .codex: return "triangle.3d"
        case .claude: return "sun.max"
        case .gemini: return "sparkle"
        case .kiro: return "terminal"
        case .openrouter: return "network"
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
    let credentialHint: String
    let supportsManualSecret: Bool
    let defaultEnabled: Bool
    let refreshInterval: TimeInterval
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

    var primaryRiskScore: Double {
        snapshot?.primaryWindow?.clampedUsedRatio ?? 0
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
        if let primary = snapshot?.primaryWindow {
            return "\(primary.label) \(Int(primary.clampedUsedRatio * 100))%"
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
}
