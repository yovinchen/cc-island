//
//  QuotaProviderProtocol.swift
//  ClaudeIsland
//

import Foundation

protocol QuotaProvider: Sendable {
    var descriptor: QuotaProviderDescriptor { get }

    func isConfigured() -> Bool
    func fetch() async throws -> QuotaSnapshot
}

enum QuotaProviderError: LocalizedError, Sendable {
    case missingCredentials(String)
    case unauthorized(String)
    case invalidResponse(String)
    case network(String)
    case commandFailed(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let message),
             .unauthorized(let message),
             .invalidResponse(let message),
             .network(let message),
             .commandFailed(let message),
             .unsupported(let message):
            return message
        }
    }
}
