//
//  SettingsWindowController.swift
//  ClaudeIsland
//
//  Independent settings window controller.
//  Manages a standalone NSWindow for the full settings experience.
//

import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    static var shared: SettingsWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Island Settings"
        window.contentViewController = hostingController
        window.center()
        window.setFrameAutosaveName("ClaudeIslandSettings")
        window.minSize = NSSize(width: 920, height: 620)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0)

        let controller = SettingsWindowController(window: window)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        shared?.window?.close()
        shared = nil
    }
}
