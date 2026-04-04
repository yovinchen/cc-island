<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Claude Island</h3>
  <p align="center">
    A macOS Notch overlay app for AI coding tools — Claude Code, Codex, Gemini, Cursor, and more.
    <br />
    <br />
    <a href="https://github.com/farouqaldori/claude-island/releases/latest" target="_blank" rel="noopener noreferrer">
      <img src="https://img.shields.io/github/v/release/farouqaldori/claude-island?style=rounded&color=white&labelColor=000000&label=release" alt="Release Version" />
    </a>
    <a href="#" target="_blank" rel="noopener noreferrer">
      <img alt="GitHub Downloads" src="https://img.shields.io/github/downloads/farouqaldori/claude-island/total?style=rounded&color=white&labelColor=000000">
    </a>
  </p>
</div>

## Features

- **Notch UI** — Dynamic Island-style overlay from the MacBook notch
- **Multi-Tool Support** — Claude Code, Codex CLI, Gemini CLI, Cursor, OpenCode, Copilot
- **Live Session Monitoring** — Track multiple AI sessions in real-time
- **Permission Approvals** — Approve/deny tool executions directly from the notch
- **Chat History** — Full conversation history with markdown rendering
- **Smart Notifications** — Auto-expand on task complete, auto-collapse on mouse leave, idle auto-hide
- **Usage Display** — API rate limit and context window usage rings
- **Hook Auto-Repair** — Optional auto-repair when other tools overwrite hook configs
- **Global Shortcut** — `⌘⇧I` to toggle the notch open/closed
- **i18n** — English and Simplified Chinese
- **User-Controlled Hooks** — Hooks are only injected after explicit user consent via first-run setup

## Requirements

- macOS 15.6+
- Xcode 16.0+ (for building from source)
- At least one supported AI coding tool installed

## Install

### Download

Grab the latest `.dmg` from [Releases](https://github.com/farouqaldori/claude-island/releases/latest) and drag to `/Applications`.

### Build from Source

#### 1. Clone

```bash
git clone https://github.com/farouqaldori/claude-island.git
cd claude-island
```

#### 2. Resolve dependencies

The project uses Swift Package Manager. Xcode resolves packages automatically on first open, or you can trigger it manually:

```bash
xcodebuild -resolvePackageDependencies -project ClaudeIsland.xcodeproj
```

Dependencies:
- [Sparkle](https://github.com/sparkle-project/Sparkle) — Auto-updates
- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown rendering
- [Mixpanel](https://github.com/mixpanel/mixpanel-swift) — Anonymous analytics

#### 3. Build

**With Xcode GUI:**

```
Open ClaudeIsland.xcodeproj → Select scheme "ClaudeIsland" → ⌘B (Build) or ⌘R (Run)
```

**With command line (unsigned):**

```bash
xcodebuild \
  -project ClaudeIsland.xcodeproj \
  -scheme ClaudeIsland \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The built app is at:

```
~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/ClaudeIsland.app
```

**With code signing (for distribution):**

```bash
xcodebuild \
  -project ClaudeIsland.xcodeproj \
  -scheme ClaudeIsland \
  -configuration Release \
  DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
  build
```

#### 4. Run

```bash
open ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/ClaudeIsland.app
```

Or simply press `⌘R` in Xcode.

## Project Structure

```
ClaudeIsland/
├── App/                          # App lifecycle (AppDelegate, WindowManager)
├── Core/                         # Settings, NotchViewModel, NotchActivityCoordinator
├── Models/                       # SessionState, ChatMessage, SessionPhase
├── Services/
│   ├── Hooks/                    # HookInstaller, HookSocketServer, FileWatcher, RepairManager
│   ├── Session/                  # ClaudeSessionMonitor, ConversationParser
│   ├── State/                    # SessionStore (central state actor)
│   ├── Usage/                    # UsageDataManager (API rate limits)
│   ├── Sound/                    # SoundPackManager (themed notifications)
│   ├── Shared/                   # KeyboardShortcutManager, ProcessExecutor
│   └── ...
├── UI/
│   ├── Views/                    # NotchView, NotchMenuView, HookSetupView, ChatView
│   ├── Components/               # UsageRing, StatusIcons, MarkdownRenderer
│   └── Window/                   # NotchWindow, NotchViewController
├── Resources/
│   ├── en.lproj/                 # English strings
│   └── zh-Hans.lproj/           # Chinese (Simplified) strings
└── Utilities/

ClaudeIslandBridge/               # Swift CLI bridge (replaces Python hook scripts)
├── main.swift                    # Entry point — reads stdin JSON, forwards via socket
├── SocketClient.swift            # Unix domain socket client
├── EventMapper.swift             # Maps tool-specific events to unified protocol
└── TTYDetector.swift             # Terminal detection
```

## How It Works

### First Launch

On first launch, the notch opens a **Hook Setup** screen. It auto-detects which AI tools are installed on your system and lets you choose which ones to integrate. **No hooks are written until you click "Install".**

You can also skip setup entirely and configure hooks later in Settings.

### Hook Communication

For each enabled tool, Claude Island writes a hook entry into that tool's config file (e.g. `~/.claude/settings.json`). When the tool triggers an event (session start, tool use, permission request, etc.), the hook script sends a JSON payload to a Unix socket at `/tmp/claude-island.sock`. The app decodes the event and updates the UI in real-time.

### Permission Approval Flow

1. AI tool requests permission to run a tool (e.g. `Bash`, `Edit`)
2. Hook sends `PermissionRequest` event with the socket kept open
3. Notch expands with tool details and Approve/Deny buttons
4. User clicks → response sent back through the same socket
5. AI tool receives the decision and proceeds

### Supported Tools

| Tool | Config File | Hook Type |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | Python script via `command` |
| Codex CLI | `~/.codex/hooks.json` | Python script via `bash` |
| Gemini CLI | `~/.gemini/settings.json` | Bridge CLI via `command` |
| Cursor | `~/.cursor/hooks.json` | Bridge CLI via `command` |
| OpenCode | `~/.config/opencode/plugins/claude-island.js` | JS plugin file |
| Copilot | `~/.copilot/config.json` | Bridge CLI via `command` |

### Managing Hooks

- **Settings menu** → "AI Tool Hooks" section shows per-tool status
- Click any tool row to **enable/disable** its hook
- "Repair All" button reinstalls hooks for all enabled tools
- "Auto-repair hooks" toggle — when enabled, automatically reinstalls hooks if they get removed by other tools

## Analytics

Claude Island uses Mixpanel for anonymous usage analytics:

- **App Launched** — App version, build number, macOS version
- **Session Started** — When a new AI session is detected

No personal data or conversation content is collected.

## License

Apache 2.0
