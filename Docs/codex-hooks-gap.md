# Codex CLI Hooks — 差距分析

> 官方文档: https://developers.openai.com/codex/hooks
> 配置参考: https://developers.openai.com/codex/config-reference
> 高级配置: https://developers.openai.com/codex/config-advanced
> 源码: https://github.com/openai/codex/tree/main/codex-rs/hooks
> 分析日期: 2026-04-05

## 官方支持的事件（最新）

Codex CLI 当前官方支持 5 个 hook 事件：

| 事件 | 作用域 | matcher 目标 | 说明 |
|------|--------|-------------|------|
| **SessionStart** | session | — | 会话启动时触发 |
| **UserPromptSubmit** | turn | — | 用户提交 prompt 前触发，可阻止或增强 |
| **PreToolUse** | turn | tool_name（目前仅 Bash） | 工具调用前触发，可 deny/allow |
| **PostToolUse** | turn | tool_name（目前仅 Bash） | 工具调用后触发，可替换结果 |
| **Stop** | turn | — | 代理回合结束时触发，可令 Codex 继续执行 |

### 官方 hook 输出协议

- **通用字段**: `continue`(bool), `stopReason`(string), `systemMessage`(string), `suppressOutput`(bool)
- **PreToolUse**: `permissionDecision: "deny"/"allow"/"ask"` + `permissionDecisionReason`; exit code 2 = deny
- **PostToolUse**: `decision: "block"` + `reason`（不撤销已执行命令，替换工具结果）; `additionalContext`
- **Stop**: `decision: "block"` + `reason`（告诉 Codex 继续，用 reason 作为新 prompt）; exit code 2 同理
- **超时默认值**: 600 秒

### 官方 notify 配置

```toml
notify = ["command", "arg1", "arg2"]
```

支持的 TUI 通知事件类型: `agent-turn-complete`, `approval-requested`

---

## 当前已支持

| 功能 | 状态 | 实现位置 | 说明 |
|------|------|---------|------|
| hooks.json 配置 | ✅ | `HookInstaller.swift:501-949` | 嵌套 `{matcher?, hooks:[{type, command}]}` 结构 |
| config.toml 管理 | ✅ | `HookInstaller.swift:649-672` | `codex_hooks = true` 特性开关 + notify 数组 |
| SessionStart 事件 | ✅ | `HookInstaller.swift:514` | matcher: `"startup\|resume"` |
| UserPromptSubmit 事件 | ✅ | `HookInstaller.swift:515` | 无 matcher，匹配所有 |
| Stop 事件（via notify） | ✅ | `HookInstaller.swift:662-664` | 通过 config.toml `notify` 命令 + `--source codex_notify` |
| notify 链式转发 | ✅ | `main.swift:81-108` | 保留用户原有 notify 命令，异步串联执行 |
| codex_notify 源识别 | ✅ | `EventMapper.swift:187-202` | 根据 client 字段区分 `codex_cli` / `codex_desktop` |
| Codex Desktop 文件监听 | ✅ | `CodexSessionWatcher.swift` | session_index.jsonl + transcript delta 增量读取 |
| Desktop 审批推断 | ✅ | `CodexDesktopApprovalWatcher.swift` | 工具静默 30s 推断为等待审批 |
| 事件别名映射 | ✅ | `EventMapper.swift:224-251` | taskStarted/userMessage→UserPromptSubmit, taskComplete/agentTurnComplete→Stop |
| 旧版 notify 脚本清理 | ✅ | `HookInstaller.swift:559` | 安装时删除 legacy `codex-notify.py` |
| 安装/卸载幂等性 | ✅ | `HookInstaller.swift:550-590` | 卸载时恢复原有 notify 配置 |

---

## 尚未实现

### 1. PreToolUse 事件（高优先级）

**官方状态**: 已正式支持。matcher 针对 `tool_name`（目前仅 `Bash`）。hook 可通过 stdout JSON 返回 `permissionDecision: "deny"` 或 exit code 2 阻止工具调用。

**当前行为**: `CodexHookSource.events` 数组（第 513-516 行）仅注册 `SessionStart` 和 `UserPromptSubmit`，**未注册 `PreToolUse`**。

**影响**: 无法在 Codex CLI 执行 Bash 命令前收到通知，也无法通过 ClaudeIsland 审批/阻止 Codex 的工具调用。

**建议方案**:
1. 在 `events` 数组中添加 `.init("PreToolUse")` 或 `.init("PreToolUse", matcher: "Bash")`
2. bridge 命令使用 `--source codex` 接收 stdin JSON
3. `PermissionHandler` 可检测 PreToolUse 事件并实现审批流程（类似 Qoder 的隐式权限处理）
4. 注意: hook stdout 必须返回 Codex 格式的 JSON（`permissionDecision` 字段），而非 Claude Code 格式

---

### 2. PostToolUse 事件（高优先级）

**官方状态**: 已正式支持。matcher 针对 `tool_name`（目前仅 `Bash`）。`decision: "block"` 可替换工具结果。

**当前行为**: 未注册。Codex 工具执行后无通知。

**影响**: 无法追踪 Codex CLI 的工具执行状态（running_tool → processing 过渡），UI 上 Codex CLI 会话缺少工具级粒度。

**建议方案**:
1. 在 `events` 数组中添加 `.init("PostToolUse")`
2. EventMapper 已能处理 PostToolUse 事件（第 261-262 行），无需改动映射层
3. 仅做观察/通知，不返回 `decision: "block"`（避免干扰 Codex 行为）

---

### 3. Stop 事件作为 hooks.json 注册（中优先级）

**官方状态**: Stop 是正式的 hook 事件，支持通过 `decision: "block"` 令 Codex 继续。

**当前行为**: Stop 仅通过 `notify` 命令间接获取（codex_notify 源），未在 hooks.json 中注册。notify 传递的是精简的通知 payload，不包含完整的 hook 上下文（如 `last_assistant_message`）。

**影响**:
- notify 的 payload 格式与 hook stdin 格式不同，信息更少
- 无法使用 Stop hook 的 `decision: "block"` 能力来控制 Codex 是否继续

**建议方案**:
1. 在 `events` 数组中添加 `.init("Stop")`
2. 同时保留 notify 机制以兼容 Codex Desktop 通知

---

### 4. Hook 输出协议适配（中优先级）

**官方状态**: Codex hook 期望特定的 stdout JSON 格式：
- PreToolUse: `{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "..."}}`
- PostToolUse: `{decision: "block", reason: "..."}`
- Stop: `{decision: "block", reason: "..."}`
- 通用: `{systemMessage: "...", continue: true/false}`

**当前行为**: `PermissionHandler` 对 Codex 源无特殊处理。如果注册了 PreToolUse，bridge 返回的审批响应格式可能不被 Codex 识别。

**影响**: 即使注册了 PreToolUse/PostToolUse，审批响应可能被 Codex 忽略。

**建议方案**: 在 `PermissionHandler` 中添加 source 感知的响应格式化：
- codex 源 → Codex stdout JSON 格式
- claude 源 → Claude Code stdout JSON 格式

---

### 5. PermissionRequest 事件（低优先级 — 官方不支持）

**官方状态**: Codex CLI 没有独立的 PermissionRequest 事件。权限处理在 TUI 终端内完成。

**当前行为**: 不支持通过 ClaudeIsland Notch 审批 Codex CLI 的权限请求。

**变通方案**: 通过 PreToolUse hook 的 `permissionDecision` 机制实现类似效果（需先实现 #1）。

---

### 6. SessionEnd 事件（低优先级 — 官方不支持）

**官方状态**: Codex CLI 无 SessionEnd hook。会话结束只能通过 Stop 事件或 notify 推断。

**当前行为**: 通过 notify 的 taskComplete/agentTurnComplete 推断会话完成。Desktop 通过 session_index.jsonl 条目删除检测。

**变通方案**: 超时机制（无活动自动标记结束）。当前已实现。

---

### 7. Codex Desktop transcript 完整解析（低优先级）

**官方状态**: Codex Desktop transcript JSONL 包含完整工具调用记录（function_call, function_result 等）。

**当前行为**: `CodexSessionWatcher` 仅提取 `user_message`, `task_started`, `task_complete` 三种事件类型。

**影响**: Desktop 会话缺少工具级粒度追踪。

**建议方案**: 扩展 `desktopEvent()` 方法，解析 `function_call`→PreToolUse, `function_result`→PostToolUse 映射。

---

### 8. notify payload 元数据提取（低优先级）

**官方状态**: notify 回调 payload 可能包含 token 用量、模型信息、会话持续时间等元数据。

**当前行为**: `EventMapper` 仅提取基础字段（session_id, client, event type）。

**影响**: UI 无法展示 Codex 的 token 消耗等统计信息。

---

## Codex CLI vs Claude Code 关键差异总结

| 维度 | Claude Code | Codex CLI（最新） | claude-island 支持度 |
|------|------------|-------------------|---------------------|
| 配置格式 | settings.json (JSON) | hooks.json (JSON) + config.toml (TOML) | ✅ 完整支持 |
| hook 事件数 | ~10 | 5 (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop) | ⚠️ 仅 2/5 |
| PreToolUse | ✅ | ✅（仅 Bash） | ❌ 未注册 |
| PostToolUse | ✅ | ✅（仅 Bash） | ❌ 未注册 |
| Stop (hook) | ✅ | ✅ | ⚠️ 仅通过 notify 间接获取 |
| PermissionRequest | ✅ 独立事件 | ❌ 不支持（通过 PreToolUse deny 替代） | N/A |
| SessionEnd | ✅ | ❌ 不支持 | N/A（超时推断） |
| SubagentStop | ✅ | ❌ 不支持 | N/A |
| PreCompact | ✅ | ❌ 不支持 | N/A |
| Notification | ✅ | ❌（有 TUI notifications 但非 hook） | N/A |
| hook 输出协议 | exit code 0/2 + JSON | exit code 0/2 + JSON（字段名不同） | ⚠️ 未适配 |
| 审批能力 | socket 双向通信 | PreToolUse stdout 单次决策 | ❌ 未实现 |
| matcher | regex on tool_name | regex on tool_name（与 Claude Code 相同） | ✅ 已支持 |
| 超时默认 | 未明确 | 600 秒 | — |
| 特性开关 | 无需 | `[features] codex_hooks = true` | ✅ 自动设置 |
| Desktop 支持 | — | transcript JSONL + session_index.jsonl | ✅ 文件监听 |
| 并发执行 | 串行 | 并发（同事件多个 hook 同时执行） | — |
| Windows | ✅ | ❌ hooks 不支持 Windows | — |

## 优先级排序

1. **高**: 注册 PreToolUse + PostToolUse 事件（扩展 `events` 数组）
2. **高**: 适配 Codex hook 输出协议（`PermissionHandler` 源感知格式化）
3. **中**: 注册 Stop 为 hooks.json 事件（补充 notify 不足）
4. **低**: Desktop transcript 完整解析
5. **低**: notify payload 元数据提取
