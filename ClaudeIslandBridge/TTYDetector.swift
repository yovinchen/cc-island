//
//  TTYDetector.swift
//  ClaudeIslandBridge
//
//  Detects the current TTY/terminal device path.
//

import Foundation

enum TTYDetector {
    /// Detect the TTY path for the current process
    static func detectTTY() -> String? {
        // Try stdin first
        if isatty(STDIN_FILENO) != 0 {
            if let name = ttyname(STDIN_FILENO) {
                return String(cString: name)
            }
        }

        // Try stderr
        if isatty(STDERR_FILENO) != 0 {
            if let name = ttyname(STDERR_FILENO) {
                return String(cString: name)
            }
        }

        // Try environment variable
        if let tty = ProcessInfo.processInfo.environment["TTY"] {
            return tty
        }

        return nil
    }
}
