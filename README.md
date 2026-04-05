<div align="center">
  <img src="ClaudeIsland/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Logo" width="100" height="100">
  <h3 align="center">Claude Island</h3>
  <p align="center">
    macOS Notch 悬浮窗应用 — 实时监控 Claude Code、Codex、Gemini、Cursor 等 AI 编程工具
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

## 功能特性

- **Notch 悬浮窗** — 仿 Dynamic Island 风格，从 MacBook 刘海区域弹出
- **多工具支持** — Claude Code、Codex CLI、Gemini CLI、Cursor、OpenCode、Copilot、Droid、Qoder、CodeBuddy、Trae
- **实时会话监控** — 同时追踪多个 AI 编程工具的会话状态
- **权限审批** — 直接在 Notch 中批准/拒绝工具执行请求
- **macOS 原生通知** — 权限请求和任务完成时发送系统通知
- **聊天记录** — 完整对话历史，支持 Markdown 渲染
- **智能通知** — 任务完成自动展开、鼠标离开自动收起、空闲自动隐藏
- **用量显示** — API 速率限制与上下文窗口用量环形指示器
- **StatusLine 集成** — Claude Code StatusLine 桥接，实时同步速率限制数据
- **Ghostty 终端标题** — 在 Ghostty 终端标签页显示当前项目和会话信息
- **Hook 自动修复** — 其他工具覆盖 Hook 配置时可选自动修复
- **Hook 版本管理** — 自动检测并升级过期的 Hook 配置
- **全局快捷键** — `⌘⇧I` 切换 Notch 展开/收起
- **多语言** — 支持英文和简体中文
- **用户可控的 Hook** — 首次启动时需用户明确同意才注入 Hook

## 系统要求

- macOS 15.6+
- Xcode 16.0+（从源码构建时需要）
- 至少安装一个支持的 AI 编程工具

## 安装

### 直接下载

从 [Releases](https://github.com/farouqaldori/claude-island/releases/latest) 下载最新 `.dmg` 文件，拖入 `/Applications` 即可。

### 从源码构建

#### 1. 克隆仓库

```bash
git clone https://github.com/farouqaldori/claude-island.git
cd claude-island
```

#### 2. 解析依赖

项目使用 Swift Package Manager 管理依赖。Xcode 首次打开会自动解析，也可手动触发：

```bash
xcodebuild -resolvePackageDependencies -project ClaudeIsland.xcodeproj
```

依赖列表：
- [Sparkle](https://github.com/sparkle-project/Sparkle) — 自动更新
- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown 渲染
- [Mixpanel](https://github.com/mixpanel/mixpanel-swift) — 匿名使用统计

#### 3. 构建

**Xcode 图形界面：**

```
打开 ClaudeIsland.xcodeproj → 选择 Scheme "ClaudeIsland" → ⌘B（构建）或 ⌘R（运行）
```

**命令行构建（无签名）：**

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

构建产物位于：

```
~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/Claude\ Island.app
```

**带签名构建（用于分发）：**

```bash
xcodebuild \
  -project ClaudeIsland.xcodeproj \
  -scheme ClaudeIsland \
  -configuration Release \
  DEVELOPMENT_TEAM="你的团队ID" \
  build
```

#### 4. 运行

```bash
open ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release/Claude\ Island.app
```

或在 Xcode 中直接按 `⌘R` 运行。

## 本地打包测试

### 生成 DMG 安装包

项目提供了打包脚本，可一键生成 DMG：

```bash
# 先构建 Release 版本
xcodebuild \
  -project ClaudeIsland.xcodeproj \
  -scheme ClaudeIsland \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# 找到构建产物
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/Build/Products/Release -name "Claude Island.app" -maxdepth 1)

# 创建 DMG
hdiutil create -volname "ClaudeIsland" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  ClaudeIsland.dmg
```

### 本地测试流程

1. **构建并运行**：在 Xcode 中 `⌘R`，应用会自动出现在 Notch 区域
2. **首次启动**：弹出 Hook 设置界面，自动检测已安装的 AI 工具
3. **安装 Hook**：选择要集成的工具，点击"安装"
4. **触发测试**：打开终端运行 Claude Code 或其他 AI 工具，观察 Notch 状态变化
5. **权限审批测试**：在 AI 工具中触发需要权限的操作（如文件编辑），在 Notch 中审批
6. **快捷键测试**：按 `⌘⇧I` 切换 Notch 展开/收起

### 调试技巧

- 在 Xcode 控制台查看实时日志输出
- Hook 通信通过 Unix Socket `/tmp/claude-island.sock` 进行
- 可使用 `socat` 模拟 Hook 事件进行调试：

```bash
echo '{"type":"session_start","session_id":"test"}' | socat - UNIX-CONNECT:/tmp/claude-island.sock
```

---

## Hook 注入系统

### 架构概述

Claude Island 通过 **Hook 注入** 实时获取 AI 工具的运行状态。架构分为三层：

```
AI 工具 (Claude Code / Codex / Gemini / ...)
    ↓  触发 Hook 事件（stdin JSON）
Launcher 脚本 (~/.claude-island/bin/claude-island-bridge-launcher.sh)
    ↓  4 级路径发现，exec 桥接二进制
Bridge 二进制 (claude-island-bridge)
    ↓  事件规范化 + 环境收集 + 终端标题
Unix Socket (/tmp/claude-island.sock)
    ↓  JSON 通信
Claude Island App (NotchView)
```

### 支持的 AI 工具

| 工具 | 配置文件 | 配置目录 | Hook 类型 | 注册事件数 | 权限超时 |
|------|---------|---------|----------|-----------|---------|
| **Claude Code** | `settings.json` | `~/.claude` | Bridge CLI (`command`) | 10 | 86400s (24h) |
| **Codex CLI** | `hooks.json` | `~/.codex` | Python 脚本 (`bash`) | 10 | 86400s (24h) |
| **Codex Desktop** | — | `~/.codex` | 文件监听（无需 Hook） | — | — |
| **Gemini CLI** | `settings.json` | `~/.gemini` | Bridge CLI (`command`) | 6 | 30s |
| **Cursor** | `hooks.json` | `~/.cursor` | Bridge CLI (`command`) | 5 | 30s |
| **OpenCode** | `claude-island.js` | `~/.config/opencode/plugins` | JS 插件 | 5 | 5s |
| **Copilot** | `config.json` | `~/.copilot` | Bridge CLI (`command`) | 4 | 默认 |
| **Droid** | `settings.json` | `~/.droid` | Bridge CLI (`command`) | 6 | 默认 |
| **Qoder** | `settings.json` | `~/.qoder` | Bridge CLI (`command`) | 6 | 默认 |
| **CodeBuddy** | `settings.json` | `~/.codebuddy` | Bridge CLI (`command`) | 6 | 默认 |
| **Trae** | — | `~/.trae` | — | — | — |

> 🚫 Trae 暂不支持：Trae IDE 使用 `.rules` 配置（Markdown 格式），Trae Agent 使用 YAML 配置，均不提供 Hooks API。待官方支持后适配。

### Hook 支持矩阵

各 AI 工具对 Hook 事件的支持情况：

| Hook 事件 | Claude Code | Codex CLI | Codex Desktop | Gemini CLI | Cursor | OpenCode | Copilot | Droid | Qoder | CodeBuddy | Trae |
|-----------|:-----------:|:---------:|:-------------:|:----------:|:------:|:--------:|:-------:|:-----:|:-----:|:---------:|:----:|
| SessionStart | ✅ | ✅ | 📁 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🚫 |
| SessionEnd | ✅ | ✅ | 📁 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🚫 |
| UserPromptSubmit | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| PreToolUse | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | 🚫 |
| PostToolUse | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | 🚫 |
| PermissionRequest | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Stop | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🚫 |
| SubagentStop | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Notification | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ | 🚫 |
| PreCompact | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

> ✅ = 支持　❌ = 不支持　📁 = 通过文件监听实现（非 Hook）　🚫 = 暂不支持（工具未提供 Hooks API）

### 功能支持矩阵

各 AI 工具的功能支持情况：

| 功能 | Claude Code | Codex CLI | Codex Desktop | Gemini CLI | Cursor | OpenCode | Copilot | Droid | Qoder | CodeBuddy | Trae |
|------|:-----------:|:---------:|:-------------:|:----------:|:------:|:--------:|:-------:|:-----:|:-----:|:---------:|:----:|
| 实时状态监控 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🚫 |
| 工具执行追踪 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | 🚫 |
| 权限审批（Notch） | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 权限响应格式 | hookSpecificOutput | 通用 JSON | — | — | — | — | — | — | — | — | — |
| Always Allow (acceptEdits) | ✅ | ❌ | — | — | — | — | — | — | — | — | — |
| Bypass (bypassPermissions) | ✅ | ❌ | — | — | — | — | — | — | — | — | — |
| 聊天记录解析 | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 子代理追踪 | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 上下文压缩通知 | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| StatusLine 集成 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| 终端标题 (Ghostty) | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🚫 |
| 终端跳转 | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🚫 |
| macOS 系统通知 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🚫 |

> 🚫 Trae 注：当前代码向 `~/.trae/settings.json` 写入 Claude Code 格式的 Hook 配置，但 Trae IDE 使用 `.rules` 文件（Markdown 格式）且 Trae Agent 使用 YAML 配置，均不支持 JSON hooks API。集成实际无效，待 Trae 官方提供 Hooks API 后适配。

### Hook 事件

应用通过 Hook 监听以下事件：

| 事件名 | 触发时机 | 推断状态 | 说明 |
|--------|---------|---------|------|
| `SessionStart` | 用户启动 AI 会话 | `waiting_for_input` | 创建/激活 Session |
| `SessionEnd` | 会话关闭 | `ended` | 清理 Session |
| `UserPromptSubmit` | 用户发送消息 | `processing` | 更新聊天历史 |
| `PreToolUse` | 工具执行前 | `running_tool` | 追踪工具进度 |
| `PostToolUse` | 工具执行后 | `processing` | 更新工具状态 |
| `PermissionRequest` | 工具需要审批 | `waiting_for_approval` | 弹出审批 UI + 系统通知 |
| `Stop` | AI 助手停止 | `waiting_for_input` | 任务完成通知 |
| `SubagentStop` | 子代理停止 | `waiting_for_input` | 子任务完成 |
| `Notification` | 通用通知 | `unknown` | 错误、警告等 |
| `PreCompact` | 上下文压缩前 | `compacting` | 支持 auto/manual 两种模式 |

### Claude Code 写入格式

安装后写入 `~/.claude/settings.json`：

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source claude"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source claude"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source claude",
            "timeout": 86400
          }
        ]
      }
    ],
    "PreCompact": [
      { "matcher": "auto", "hooks": [{ "type": "command", "command": "..." }] },
      { "matcher": "manual", "hooks": [{ "type": "command", "command": "..." }] }
    ]
  },
  "statusLine": {
    "command": "~/.claude-island/bin/claude-island-statusline",
    "type": "command"
  },
  "_claude_island_hook_version": 2
}
```

**配置说明：**
- 带 `matcher: "*"` 的事件匹配所有工具名
- `PermissionRequest` 设置 24 小时超时以支持长时间等待审批
- `PreCompact` 分别匹配 `auto`（自动）和 `manual`（手动）压缩
- `_claude_island_hook_version` 用于自动升级检测
- `statusLine` 配置 Claude Code 状态栏桥接脚本

### Socket 通信协议

Bridge 将事件发送到 Unix Socket `/tmp/claude-island.sock`，Payload 格式：

```json
{
  "session_id": "abc-123",
  "source": "claude",
  "cwd": "/Users/name/project",
  "event": "PreToolUse",
  "status": "running_tool",
  "approval_channel": "none",
  "tty": "/dev/ttys003",
  "pid": 12345,
  "tool": "Bash",
  "tool_input": { "command": "npm test" },
  "tool_use_id": "toolu_xxx",
  "_ppid": 12340,
  "_env": {
    "TERM_PROGRAM": "ghostty",
    "TMUX": "",
    "KITTY_WINDOW_ID": ""
  }
}
```

**字段说明：**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `session_id` | string | 是 | 会话唯一标识 |
| `source` | string | 是 | 来源工具：`claude`/`codex`/`gemini`/`cursor`/`copilot`/`opencode`/`qoder`/`droid`/`codebuddy`/`trae` |
| `cwd` | string | 是 | 工作目录 |
| `event` | string | 是 | 规范化事件名（见上表） |
| `status` | string | 是 | 推断状态 |
| `approval_channel` | string | 是 | `"none"` 或 `"socket"`（权限请求时） |
| `tty` | string | 否 | TTY 设备路径 |
| `pid` | number | 否 | 进程 ID |
| `tool` | string | 否 | 工具名（如 `Bash`、`Edit`、`Read`） |
| `tool_input` | object | 否 | 工具输入参数 |
| `tool_use_id` | string | 否 | 工具调用 ID |
| `_ppid` | number | 是 | Bridge 进程的父进程 ID |
| `_env` | object | 是 | 终端环境变量（用于会话关联） |

**收集的环境变量：**

```
TERM_PROGRAM, ITERM_SESSION_ID, TERM_SESSION_ID,
TMUX, TMUX_PANE, KITTY_WINDOW_ID, __CFBundleIdentifier,
CONDUCTOR_WORKSPACE_NAME, CONDUCTOR_PORT, CURSOR_TRACE_ID,
CMUX_WORKSPACE_ID, CMUX_SURFACE_ID, CMUX_SOCKET_PATH
```

### 权限审批流程

```
1. AI 工具发起 PermissionRequest（如执行 Bash 命令）
2. Bridge 发送 JSON 到 Socket 并保持连接不关闭
3. App 接收事件 → 更新 Notch UI → 发送 macOS 系统通知
4. 用户在 Notch 中点击"批准"或"拒绝"
5. App 通过同一 Socket 连接返回响应：
   { "decision": "allow" }  或  { "decision": "deny" }
6. Bridge 将响应写入 stdout → AI 工具继续执行
```

**超时：** PermissionRequest 连接保持最长 86400 秒（24 小时）。

### Bridge 二进制

`claude-island-bridge` 是原生 Swift CLI，位于 `Claude Island.app/Contents/Helpers/`。

**调用方式：**

```bash
echo '<hook_json>' | claude-island-bridge --source claude
```

**`--source` 参数：**

| 值 | 对应工具 |
|---|---------|
| `claude` | Claude Code（默认值） |
| `codex` | Codex CLI |
| `gemini` | Gemini CLI |
| `cursor` | Cursor |
| `copilot` | GitHub Copilot |
| `opencode` | OpenCode |
| `qoder` | Qoder |
| `droid` | Droid |
| `codebuddy` | CodeBuddy |
| `trae` | Trae |

**Bridge 功能：**

1. **事件规范化** — 将各工具不同格式的事件名统一映射（支持 snake_case、camelCase、kebab-case）
2. **TTY 检测** — 通过 `isatty()` + `ttyname()` + `$TTY` 环境变量获取终端设备
3. **环境收集** — 采集终端相关环境变量用于会话关联
4. **终端标题** — 为 Ghostty 终端设置 OSC2 标签标题
5. **Socket 通信** — 普通事件 fire-and-forget，权限请求保持连接等待响应

### Launcher 脚本（4 级路径发现）

`~/.claude-island/bin/claude-island-bridge-launcher.sh` 负责定位 Bridge 二进制：

```bash
#!/bin/zsh
H=/Contents/Helpers/claude-island-bridge

# 1. 直接路径（最常见：app 在 /Applications）
B="/Applications/Claude Island.app${H}"
[ -x "$B" ] && exec "$B" "$@"

# 2. 备选安装路径
for P in "/Applications/Claude Island.app" \
         "/Applications/claude-island.app" \
         "$HOME/Applications/Claude Island.app"; do
  B="${P}${H}"; [ -x "$B" ] && exec "$B" "$@"
done

# 3. 缓存路径（App 启动时写入，支持 Xcode 开发构建）
C=~/.claude-island/bin/.bridge-cache
if [ -f "$C" ]; then
  P="$(cat "$C")"
  B="${P}${H}"
  [ -x "$B" ] && exec "$B" "$@"
fi

# 4. Spotlight 搜索（最终回退）
P="$(/usr/bin/mdfind 'kMDItemCFBundleIdentifier == "com.celestial.ClaudeIsland"' | head -1)"
B="${P}${H}"
[ -x "$B" ] && { mkdir -p ~/.claude-island/bin; echo "$P" > "$C"; exec "$B" "$@"; }

echo "claude-island-bridge: app not found." >&2
exit 127
```

**设计要点：**
- 路径 `~/.claude-island/bin/` 不含空格，避免 shell 分词问题
- App 每次启动自动更新 `.bridge-cache` 文件
- Xcode 开发构建通过缓存路径自动适配

### StatusLine 桥接

`~/.claude-island/bin/claude-island-statusline` 脚本由 Claude Code StatusLine 调用：

```bash
#!/bin/bash
input=$(cat)
# 将 rate_limits 写入临时文件供 App 读取
_rl=$(echo "$input" | jq -c '.rate_limits // empty' 2>/dev/null)
[ -n "$_rl" ] && echo "$_rl" > /tmp/claude-island-rl.json
```

**输入字段：** Claude Code 在每次助手消息后通过 stdin 传入 JSON，包含 `rate_limits`、`model`、`context_window` 等信息。

### Ghostty 终端标题

Bridge 在 `SessionStart` 和 `UserPromptSubmit` 事件时通过 OSC2 设置终端标签标题：

```
\x1B]2;{project} · {userText} · {sessionPrefix}\x07
```

**支持的终端：** Ghostty、xterm-ghostty（不在 tmux 中时）

**检测方式：** `$TERM_PROGRAM` 环境变量

### macOS 系统通知

通过 `UNUserNotificationCenter` 发送原生通知：

| 触发条件 | 通知标题 | 通知内容 |
|---------|---------|---------|
| 工具需要权限审批 | Permission Request | `{toolName} needs approval in {project}` |
| 任务完成（等待输入） | Task Complete | `Claude is ready for input in {project}` |
| Claude 提问 | Claude's Question | `{question}` |

可在设置中通过 `enableSystemNotifications` 开关控制。

### Hook 版本管理

- `_claude_island_hook_version` 字段写入配置文件
- App 启动时检测版本号，低于当前版本自动升级
- 升级时先移除旧条目再写入新条目，确保配置干净

### Hook 管理

- **设置菜单** → "AI 工具 Hooks" 区域显示各工具的状态
- 点击工具行可 **启用/禁用** 对应的 Hook
- "修复全部" 按钮可为所有已启用的工具重新安装 Hook
- "自动修复 Hook" 开关 — 开启后，当 Hook 被其他工具移除时自动重新安装

---

## 项目结构

```
ClaudeIsland/
├── App/                          # 应用生命周期（AppDelegate、WindowManager）
├── Core/                         # 设置、NotchViewModel、NotchActivityCoordinator
├── Models/                       # SessionState、ChatMessage、SessionPhase
├── Services/
│   ├── Hooks/                    # Hook 安装器、Socket 服务器、文件监听、自动修复
│   ├── Notification/             # macOS 原生通知管理
│   ├── Session/                  # 会话监控、对话解析器
│   ├── State/                    # SessionStore（中央状态管理 Actor）
│   ├── Usage/                    # UsageDataManager（API 用量追踪）
│   ├── Sound/                    # SoundPackManager（通知音效）
│   ├── Shared/                   # 快捷键管理、进程执行器
│   ├── Codex/                    # Codex 集成（CLI Hook + Desktop 文件监听）
│   ├── Tmux/                     # Tmux 会话管理
│   └── ...
├── UI/
│   ├── Views/                    # NotchView、菜单视图、Hook 设置、聊天视图
│   ├── Components/               # 用量环、状态图标、Markdown 渲染器
│   └── Window/                   # Notch 窗口、窗口控制器
├── Resources/
│   ├── claude-island-bridge-launcher.sh  # Bridge 路径发现脚本
│   ├── claude-island-statusline.sh       # StatusLine 桥接脚本
│   ├── en.lproj/                 # 英文本地化
│   └── zh-Hans.lproj/           # 简体中文本地化
└── Utilities/

ClaudeIslandBridge/               # Swift CLI 桥接二进制
├── main.swift                    # 入口 — 读取 stdin JSON，事件映射，Socket 转发
├── EventMapper.swift             # 将各工具事件映射为统一协议
├── SocketClient.swift            # Unix Domain Socket 客户端
├── PermissionHandler.swift       # 权限请求双向通信
├── TerminalTitleManager.swift    # Ghostty OSC2 终端标题
└── TTYDetector.swift             # TTY 设备检测
```

## 统计分析

Claude Island 使用 Mixpanel 进行匿名使用统计：

- **App Launched** — 应用版本、构建号、macOS 版本
- **Session Started** — 检测到新的 AI 会话

不收集任何个人数据或对话内容。

## 许可证

Apache 2.0
