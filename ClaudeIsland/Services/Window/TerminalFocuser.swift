//
//  TerminalFocuser.swift
//  ClaudeIsland
//
//  Focuses the terminal window for a session.
//  Supports tmux+yabai, iTerm2, Kitty, and generic terminal apps via NSWorkspace.
//

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.claudeisland", category: "TerminalFocuser")

actor TerminalFocuser {
    static let shared = TerminalFocuser()

    private init() {}

    /// Focus the terminal window associated with a session.
    /// Tries multiple strategies in order: tmux+yabai, env-based, PID-based.
    func focusTerminal(session: SessionState) async -> Bool {
        // Strategy 1: tmux + yabai (existing behavior)
        if session.isInTmux {
            let success = await focusViaTmux(session)
            if success { return true }
        }

        // Strategy 2: Use env vars to identify and focus the terminal app
        if let env = session.env {
            let success = await focusViaEnv(env)
            if success { return true }
        }

        // Strategy 3: Walk process tree to find terminal app
        if let pid = session.pid {
            let success = await focusViaPid(pid)
            if success { return true }
        }

        return false
    }

    // MARK: - Strategy 1: tmux + yabai

    private func focusViaTmux(_ session: SessionState) async -> Bool {
        if let pid = session.pid {
            return await YabaiController.shared.focusWindow(forClaudePid: pid)
        } else {
            return await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
        }
    }

    // MARK: - Strategy 2: Env-based terminal focus

    private func focusViaEnv(_ env: [String: String]) async -> Bool {
        guard let termProgram = env["TERM_PROGRAM"] else { return false }

        switch termProgram.lowercased() {
        case "iterm.app":
            return await focusITerm2(sessionId: env["ITERM_SESSION_ID"])
        case "kitty":
            return await focusKitty(windowId: env["KITTY_WINDOW_ID"])
        default:
            // Generic: activate by bundle identifier or app name
            return activateTerminalApp(termProgram: termProgram)
        }
    }

    private func focusITerm2(sessionId: String?) async -> Bool {
        // Use AppleScript to activate iTerm2
        let script: String
        if let sessionId = sessionId {
            // Try to focus specific session
            script = """
            tell application "iTerm2"
                activate
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if unique ID of aSession is "\(sessionId)" then
                                select aTab
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        } else {
            script = """
            tell application "iTerm2"
                activate
            end tell
            """
        }

        return await runAppleScript(script)
    }

    private func focusKitty(windowId: String?) async -> Bool {
        if let windowId = windowId {
            // Try kitty remote control
            do {
                _ = try await ProcessExecutor.shared.run("/usr/local/bin/kitty", arguments: [
                    "@", "focus-window", "--match", "id:\(windowId)"
                ])
                return true
            } catch {
                // Fall back to generic activation
            }
        }

        return activateTerminalApp(termProgram: "kitty")
    }

    // MARK: - Strategy 3: PID-based focus

    private func focusViaPid(_ pid: Int) async -> Bool {
        // Walk up process tree to find terminal app
        let terminalBundleIds = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty",
            "org.alacritty",
            "com.github.wez.wezterm",
            "co.zeit.hyper",
            "com.microsoft.VSCode"
        ]

        let runningApps = NSWorkspace.shared.runningApplications

        // Get parent PIDs up the tree
        var currentPid = pid
        for _ in 0..<20 {  // Max 20 levels up
            let parentPid = getParentPid(currentPid)
            if parentPid <= 1 { break }

            // Check if this PID belongs to a known terminal app
            if let app = runningApps.first(where: { $0.processIdentifier == parentPid }) {
                if let bundleId = app.bundleIdentifier, terminalBundleIds.contains(bundleId) {
                    app.activate()
                    logger.debug("Focused terminal via PID walk: \(app.localizedName ?? "unknown", privacy: .public)")
                    return true
                }
            }

            currentPid = Int(parentPid)
        }

        return false
    }

    // MARK: - Helpers

    private func activateTerminalApp(termProgram: String) -> Bool {
        let bundleIdMap: [String: String] = [
            "apple_terminal": "com.apple.Terminal",
            "iterm.app": "com.googlecode.iterm2",
            "ghostty": "com.mitchellh.ghostty",
            "kitty": "net.kovidgoyal.kitty",
            "alacritty": "org.alacritty",
            "wezterm": "com.github.wez.wezterm",
            "hyper": "co.zeit.hyper",
            "vscode": "com.microsoft.VSCode",
            "tmux": "" // tmux itself isn't an app
        ]

        let key = termProgram.lowercased()

        // Try bundle identifier lookup
        if let bundleId = bundleIdMap[key], !bundleId.isEmpty {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
                app.activate()
                logger.debug("Activated terminal: \(termProgram, privacy: .public)")
                return true
            }
        }

        // Try matching by localized name
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased().contains(key) == true
        }) {
            app.activate()
            logger.debug("Activated terminal by name: \(termProgram, privacy: .public)")
            return true
        }

        return false
    }

    private func runAppleScript(_ source: String) async -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }

        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            logger.debug("AppleScript error: \(error, privacy: .public)")
            return false
        }
        return true
    }

    private func getParentPid(_ pid: Int) -> Int32 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]

        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else { return 0 }

        return info.kp_eproc.e_ppid
    }
}
