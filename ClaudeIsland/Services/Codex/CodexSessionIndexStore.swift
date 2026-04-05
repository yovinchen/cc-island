//
//  CodexSessionIndexStore.swift
//  ClaudeIsland
//
//  Parses ~/.codex/session_index.jsonl to discover Codex Desktop sessions.
//

import Foundation

struct CodexSessionEntry: Equatable, Sendable {
    let sessionId: String
    let projectDir: String
    let createdAt: Date?
    let status: String
}

struct CodexSessionIndexStore {
    private static let indexPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl").path
    }()

    static func parse() -> [CodexSessionEntry] {
        guard let data = FileManager.default.contents(atPath: indexPath),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }

        var entries: [CodexSessionEntry] = []
        for line in content.components(separatedBy: .newlines) where !line.isEmpty {
            guard let lineData = line.data(using: .utf8) else { continue }

            if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                let sessionId = json["session_id"] as? String ?? json["sessionId"] as? String ?? ""
                let projectDir = json["project_dir"] as? String ?? json["projectDir"] as? String ?? ""
                let status = json["status"] as? String ?? "unknown"

                var createdAt: Date?
                if let ts = json["created_at"] as? String ?? json["createdAt"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    createdAt = formatter.date(from: ts)
                }

                guard !sessionId.isEmpty else { continue }

                entries.append(CodexSessionEntry(
                    sessionId: sessionId,
                    projectDir: projectDir,
                    createdAt: createdAt,
                    status: status
                ))
            }
        }

        return entries
    }

    static var indexFileExists: Bool {
        FileManager.default.fileExists(atPath: indexPath)
    }

    static var indexFilePath: String { indexPath }
}
