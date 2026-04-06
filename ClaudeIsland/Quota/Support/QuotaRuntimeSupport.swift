//
//  QuotaRuntimeSupport.swift
//  ClaudeIsland
//

import Foundation

enum QuotaRuntimeSupport {
    static func which(_ binary: String) -> String? {
        switch ProcessExecutor.shared.runSync("/usr/bin/which", arguments: [binary]) {
        case .success(let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .failure:
            return nil
        }
    }

    static func resolvedBinary(defaultBinary: String, providerID: QuotaProviderID) -> String? {
        let overrideValue = cleaned(QuotaPreferences.cliBinaryPath(for: providerID))
        return resolvedBinary(defaultBinary: defaultBinary, overrideValue: overrideValue)
    }

    static func resolvedBinary(defaultBinary: String, overrideValue: String?) -> String? {
        guard let overrideValue, !overrideValue.isEmpty else {
            return which(defaultBinary)
        }

        if overrideValue.contains("/") {
            let expanded = NSString(string: overrideValue).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: expanded) ? expanded : nil
        }

        return which(overrideValue)
    }

    static func detectVersion(binaryPath: String, argumentVariants: [[String]] = [["--version"], ["version"], ["-v"]]) -> String? {
        for arguments in argumentVariants {
            switch ProcessExecutor.shared.runSync(binaryPath, arguments: arguments) {
            case .success(let output):
                let cleanedOutput = stripANSI(output)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let line = cleanedOutput
                    .split(whereSeparator: \.isNewline)
                    .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
                    .first(where: { !$0.isEmpty })
                {
                    return line
                }
            case .failure:
                continue
            }
        }
        return nil
    }

    static func envValue(_ keys: [String], fallback: String? = nil) -> String? {
        let environment = Foundation.ProcessInfo.processInfo.environment
        for key in keys {
            if let value = cleaned(environment[key]) {
                return value
            }
        }
        return cleaned(fallback)
    }

    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuotaProviderError.invalidResponse("Invalid HTTP response")
        }
        return (data, httpResponse)
    }

    static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaProviderError.invalidResponse("Root JSON is not an object")
        }
        return json
    }

    static func cleaned(_ raw: String?) -> String? {
        QuotaUtilities.cleaned(raw)
    }

    static func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let value as String:
            return cleaned(value)
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    static func doubleValue(_ raw: Any?) -> Double? {
        switch raw {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    static func intValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    static func firstNumber(pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return doubleValue(String(text[valueRange]))
    }

    static func stripANSI(_ text: String) -> String {
        let ansiStripped = text.replacingOccurrences(
            of: #"\u001B\[[0-?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        return ansiStripped
            .replacingOccurrences(of: "\u{0008}", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }

    static func relativeResetDescription(for date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds < 60 {
            return "now"
        }
        let totalMinutes = max(1, Int(ceil(Double(seconds) / 60.0)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "in \(days)d \(hours)h" : "in \(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "in \(hours)h \(minutes)m" : "in \(hours)h"
        }
        return "in \(totalMinutes)m"
    }

    static func parseMonthDay(_ raw: String, now: Date = Date()) -> Date? {
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1])
        else {
            return nil
        }

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        var components = DateComponents()
        components.year = currentYear
        components.month = month
        components.day = day

        if let date = calendar.date(from: components), date > now {
            return date
        }

        components.year = currentYear + 1
        return calendar.date(from: components)
    }

    static func dateFromMilliseconds(_ raw: Any?) -> Date? {
        guard let value = doubleValue(raw) else { return nil }
        return Date(timeIntervalSince1970: value / 1000.0)
    }
}
