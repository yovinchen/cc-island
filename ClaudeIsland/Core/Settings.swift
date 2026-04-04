//
//  Settings.swift
//  ClaudeIsland
//
//  App settings manager using UserDefaults
//

import Foundation

/// Available notification sounds
enum NotificationSound: String, CaseIterable {
    case none = "None"
    case pop = "Pop"
    case ping = "Ping"
    case tink = "Tink"
    case glass = "Glass"
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case hero = "Hero"
    case morse = "Morse"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case basso = "Basso"

    /// The system sound name to use with NSSound, or nil for no sound
    var soundName: String? {
        self == .none ? nil : rawValue
    }
}

/// Available sound theme packs
enum SoundThemePack: String, CaseIterable {
    case system = "System"
    case zelda = "Zelda"
    case starcraft = "StarCraft"
    case mario = "Mario"
    case minimal = "Minimal"

    var displayName: String { rawValue }

    /// Sound names for each event type within this theme
    var taskCompleteSound: String? {
        switch self {
        case .system: return AppSettings.notificationSound.soundName
        case .zelda: return "Glass"
        case .starcraft: return "Ping"
        case .mario: return "Pop"
        case .minimal: return "Tink"
        }
    }

    var approvalRequestSound: String? {
        switch self {
        case .system: return "Funk"
        case .zelda: return "Bottle"
        case .starcraft: return "Morse"
        case .mario: return "Frog"
        case .minimal: return "Blow"
        }
    }

    var errorSound: String? {
        switch self {
        case .system: return "Basso"
        case .zelda: return "Sosumi"
        case .starcraft: return "Hero"
        case .mario: return "Submarine"
        case .minimal: return "Basso"
        }
    }
}

enum AppSettings {
    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let notificationSound = "notificationSound"
        static let autoExpandOnTaskComplete = "autoExpandOnTaskComplete"
        static let suppressAutoExpandWhenFocusedSession = "suppressAutoExpandWhenFocusedSession"
        static let autoCollapseDelay = "autoCollapseDelay"
        static let autoHideWhenIdle = "autoHideWhenIdle"
        static let idleHideDelay = "idleHideDelay"
        static let showUsageData = "showUsageData"
        static let soundThemePack = "soundThemePack"
        static let globalShortcutEnabled = "globalShortcutEnabled"
        // Per-tool hook enable/disable
        static let hookEnabledPrefix = "hookEnabled_"
        static let hookSetupCompleted = "hookSetupCompleted"
        static let autoRepairHooks = "autoRepairHooks"
    }

    // MARK: - Notification Sound

    /// The sound to play when Claude finishes and is ready for input
    static var notificationSound: NotificationSound {
        get {
            guard let rawValue = defaults.string(forKey: Keys.notificationSound),
                  let sound = NotificationSound(rawValue: rawValue) else {
                return .pop // Default to Pop
            }
            return sound
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.notificationSound)
        }
    }

    // MARK: - Behavior

    /// Whether the notch should auto-expand when a session finishes and waits for input
    static var autoExpandOnTaskComplete: Bool {
        get {
            if defaults.object(forKey: Keys.autoExpandOnTaskComplete) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.autoExpandOnTaskComplete)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoExpandOnTaskComplete)
        }
    }

    /// Whether a focused session should suppress auto-expansion
    static var suppressAutoExpandWhenFocusedSession: Bool {
        get {
            if defaults.object(forKey: Keys.suppressAutoExpandWhenFocusedSession) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.suppressAutoExpandWhenFocusedSession)
        }
        set {
            defaults.set(newValue, forKey: Keys.suppressAutoExpandWhenFocusedSession)
        }
    }

    // MARK: - Auto-Collapse / Idle-Hide

    /// Delay in seconds before auto-collapsing an auto-opened notch
    static var autoCollapseDelay: Double {
        get {
            if defaults.object(forKey: Keys.autoCollapseDelay) == nil {
                return 3.0
            }
            return defaults.double(forKey: Keys.autoCollapseDelay)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoCollapseDelay)
        }
    }

    /// Whether to auto-hide the notch when all sessions are idle
    static var autoHideWhenIdle: Bool {
        get {
            if defaults.object(forKey: Keys.autoHideWhenIdle) == nil {
                return false
            }
            return defaults.bool(forKey: Keys.autoHideWhenIdle)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoHideWhenIdle)
        }
    }

    /// Delay in seconds before hiding the notch when idle
    static var idleHideDelay: Double {
        get {
            if defaults.object(forKey: Keys.idleHideDelay) == nil {
                return 30.0
            }
            return defaults.double(forKey: Keys.idleHideDelay)
        }
        set {
            defaults.set(newValue, forKey: Keys.idleHideDelay)
        }
    }

    // MARK: - Usage Display

    /// Whether to show API usage data in the notch header
    static var showUsageData: Bool {
        get {
            if defaults.object(forKey: Keys.showUsageData) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.showUsageData)
        }
        set {
            defaults.set(newValue, forKey: Keys.showUsageData)
        }
    }

    // MARK: - Sound Theme Pack

    /// The active sound theme pack
    static var soundThemePack: SoundThemePack {
        get {
            guard let rawValue = defaults.string(forKey: Keys.soundThemePack),
                  let pack = SoundThemePack(rawValue: rawValue) else {
                return .system
            }
            return pack
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.soundThemePack)
        }
    }

    // MARK: - Keyboard Shortcut

    /// Whether the global keyboard shortcut is enabled
    static var globalShortcutEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.globalShortcutEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.globalShortcutEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.globalShortcutEnabled)
        }
    }

    // MARK: - Hook Setup

    /// Whether the user has completed the initial hook setup
    static var hookSetupCompleted: Bool {
        get { defaults.bool(forKey: Keys.hookSetupCompleted) }
        set { defaults.set(newValue, forKey: Keys.hookSetupCompleted) }
    }

    /// Whether to auto-repair hooks when they are externally modified
    static var autoRepairHooks: Bool {
        get {
            if defaults.object(forKey: Keys.autoRepairHooks) == nil {
                return false // Disabled by default — user must opt-in
            }
            return defaults.bool(forKey: Keys.autoRepairHooks)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoRepairHooks)
        }
    }

    // MARK: - Per-Tool Hook Settings

    /// Check if a specific tool's hook is enabled
    static func isHookEnabled(for source: SessionSource) -> Bool {
        let key = Keys.hookEnabledPrefix + source.rawValue
        if defaults.object(forKey: key) == nil {
            // Default: ALL disabled until user explicitly enables via setup or settings
            return false
        }
        return defaults.bool(forKey: key)
    }

    /// Set whether a specific tool's hook is enabled
    static func setHookEnabled(_ enabled: Bool, for source: SessionSource) {
        let key = Keys.hookEnabledPrefix + source.rawValue
        defaults.set(enabled, forKey: key)
    }
}
