# Claude Code Hooks — 差距分析

> 官方文档: https://code.claude.com/docs/en/hooks
> 分析日期: 2026-04-05
> 基于 Claude Code v2.1.76+ 及本项目 `HookInstaller.swift` (hookVersion=2) / `EventMapper.swift`

---

## 当前已支持

| 功能 | 状态 | 本项目实现方式 |
|------|------|---------------|
| 10 个核心事件注册 | ✅ | UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Stop, SubagentStop, SessionStart, SessionEnd, Notification, PreCompact |
| matcher 通配符 | ✅ | PreToolUse/PostToolUse 使用 `"*"`; PermissionRequest 使用 `"*"` + 86400s timeout; PreCompact 使用 `"auto"` + `"manual"` 双 matcher |
| PermissionRequest 权限审批 | ✅ | bridge → Unix socket → Notch UI → `HookResponse{decision, reason}` 写回 stdout |
| StatusLine 集成 | ✅ | `claude-island-statusline` 脚本写入 `~/.claude/settings.json` 的 `statusLine.command` |
| hook 版本管理 | ✅ | `_claude_island_hook_version` 字段，自动检测并升级 |
| tool_use_id 缓存 | ✅ | `HookSocketServer` 用 FIFO 缓存 PreToolUse 的 tool_use_id，关联后续 PermissionRequest |
| 事件名归一化 | ✅ | `EventMapper.normalizeEventName()` 支持多种别名映射（含 Gemini/Codex/Cursor 别名） |
| stdin JSON 字段提取 | ✅ | session_id, cwd, tool_name, tool_input, tool_use_id, prompt, tool_response, last_assistant_message, notification_type, message, rate_limits, error |
| 会话级快捷操作 | ✅ | Always Allow (addRules), Accept Edits (setMode), Bypass (setMode) |
| 隐式权限（Qoder/CodeBuddy） | ✅ | `PermissionHandler.isImplicitPermissionRequest()` 对 PreToolUse 危险工具触发审批 |

---

## 尚未实现

### 1. Setup 事件

**官方说明**: v2.1.10+ 新增。在 `--init`、`--init-only`、`--maintenance` CLI 启动时触发，用于执行环境初始化（如安装依赖、校验配置）。

**stdin 字段**: 共享字段 (`session_id`, `cwd`, `hook_event_name`) + `flags` (触发的 CLI 标志)。

**当前行为**: 未在 `updateClaudeSettings()` 中注册 Setup 事件，`EventMapper` 未映射。

**影响**: 低。Claude Island 作为 GUI 监控工具，不需要在 CLI 初始化阶段执行操作。

**实现建议**: 如需支持，在 `hookEvents` 数组添加 `("Setup", withoutMatcher)` 并在 EventMapper 添加 `"setup": "Setup"` 映射。

---

### 2. Elicitation 事件

**官方说明**: v2.1.76+ 新增。当 MCP 服务器请求用户输入（交互式对话/表单）时触发。Hook 可通过 `hookSpecificOutput` 程序化提供响应，跳过用户交互。

**stdin 字段**: 共享字段 + `mcp_server_name`, `action`, `mode`, `elicitation_id`, `content`。

**hookSpecificOutput 格式**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "Elicitation",
    "action": "accept",
    "content": { "field": "value" }
  }
}
```

**当前行为**: 未注册、未映射、未处理。

**影响**: 中。随着 MCP 生态扩展，Elicitation 场景会增多。Claude Island 可展示 elicitation 请求并允许用户在 Notch UI 中响应。

**实现建议**:
1. `updateClaudeSettings()` 添加 `("Elicitation", withoutMatcher)`
2. `EventMapper` 添加 `"elicitation": "Elicitation"` 映射
3. `HookSocketServer` 中新增 Elicitation 响应流程（类似 PermissionRequest）

---

### 3. ElicitationResult 事件

**官方说明**: v2.1.76+ 新增。用户响应 elicitation 后触发，允许 hook 修改或拦截响应。

**stdin 字段**: 共享字段 + `mcp_server_name`, `action`, `mode`, `elicitation_id`, `content`。

**hookSpecificOutput 格式**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "ElicitationResult",
    "action": "decline",
    "content": {}
  }
}
```

**当前行为**: 未实现。

**影响**: 低。属于 Elicitation 的配套事件，优先级跟随 Elicitation。

---

### 4. PostCompact 事件

**官方说明**: v2.1.76+ 新增。上下文压缩完成后触发。

**stdin 字段**: 共享字段 + `trigger`（触发方式）, `compact_summary`（压缩摘要）。

**hookSpecificOutput**: 无决策控制，仅用于后续任务（如日志记录、通知）。

**当前行为**: 仅注册了 PreCompact（auto/manual），PostCompact 未注册。

**影响**: 低。可用于在 UI 中展示压缩摘要，但非核心功能。

**实现建议**: 在 `hookEvents` 添加 `("PostCompact", withoutMatcher)`，EventMapper 添加映射。

---

### 5. PreToolUse hookSpecificOutput — permissionDecision + updatedInput + additionalContext

**官方支持**:
- `permissionDecision`: `"allow"` / `"deny"` / `"ask"` / `"defer"` (v2.1.89+)
- `permissionDecisionReason`: 决策原因字符串
- `updatedInput`: 修改工具输入参数后的新值
- `additionalContext`: 注入到模型上下文的额外信息（上限 10,000 字符）

**当前行为**: 本项目仅对 PermissionRequest 事件返回 `decision`/`reason`（顶层字段）。PreToolUse 不返回任何 stdout 内容——纯监控模式。

**影响**: 中。`defer` 决策对于 `-p` 非交互模式集成有价值；`updatedInput` 可实现参数审查/修改。

**`defer` 说明**: 当多个 PreToolUse hook 返回不同决策时，优先级为 deny > defer > ask > allow。`defer` 仅在 `claude -p` 非交互模式下生效，交互模式会忽略并记录警告。

---

### 6. PostToolUse hookSpecificOutput — additionalContext

**官方支持**: PostToolUse hook 可返回 `hookSpecificOutput.additionalContext`，将额外信息附加到工具执行结果中。

**当前行为**: bridge 提取 `tool_response` 字段用于 UI 展示，但不向 stdout 写入任何响应。

**影响**: 低。Claude Island 定位为监控工具，不修改 AI 上下文。

---

### 7. UserPromptSubmit hookSpecificOutput — additionalContext

**官方支持**: 可注入文本或结构化 `additionalContext` 到对话中，在 Claude 处理用户提示之前生效。

**当前行为**: 仅发通知，不返回内容。

**影响**: 低。

---

### 8. SessionStart hookSpecificOutput — additionalContext

**官方支持**: 会话启动时可注入系统上下文。

**当前行为**: 仅发通知。

**影响**: 低。

---

### 9. HookResponse 格式 — 从顶层 decision/reason 迁移到 hookSpecificOutput

**官方说明**: 顶层 `decision` 和 `reason` 字段已标记为 **deprecated**。官方推荐使用嵌套的 `hookSpecificOutput` 结构：

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Tool is safe"
  }
}
```

旧值映射：`"approve"` → `"allow"`, `"block"` → `"deny"`。

**当前行为**: `HookResponse` 结构体使用顶层 `decision`/`reason`：
```swift
struct HookResponse: Codable {
    let decision: String // "allow", "deny", or "ask"
    let reason: String?
}
```

**影响**: 中。虽然 Claude Code 仍兼容旧格式，但未来可能移除。应迁移到 `hookSpecificOutput` 格式。

**实现建议**: 修改 `HookResponse` 编码为 hookSpecificOutput 嵌套格式，同时保留顶层字段作为后备。

---

### 10. HTTP Hook 类型

**官方支持**: 除 `"type": "command"` 外，Claude Code 还支持 `"type": "http"` hook，通过 HTTP POST 发送事件。

**当前行为**: 所有 hook 均使用 `"type": "command"` 通过 bridge launcher 脚本执行。

**影响**: 低。Claude Island 使用 Unix socket 通信，command 类型已满足需求。

---

### 11. Notification 细分类型展示

**官方支持**: Notification 事件包含 `notification_type`（如 `error`, `warning`, `info`）和结构化 `details`。

**当前行为**: 已提取 `notification_type` 和 `message` 字段，但 Notch UI 未区分展示不同类型。

**影响**: 中。可在 UI 中用不同图标/颜色区分通知类型，提升用户体验。

---

### 12. transcript_path / permission_mode 字段

**官方 stdin 字段**: 所有事件均包含 `transcript_path`（对话记录文件路径）和 `permission_mode`（当前权限模式）。

**当前行为**: `EventMapper` 未提取这两个字段。

**影响**: 低。`transcript_path` 可用于调试/日志回溯；`permission_mode` 可用于 UI 展示当前权限级别。

---

### 13. agent_id / agent_type 字段

**官方 stdin 字段**: 当 hook 在子代理（subagent）内触发时，输入包含 `agent_id` 和 `agent_type`。

**当前行为**: 未提取。SubagentStop 事件已支持，但缺少代理标识信息。

**影响**: 低。

---

## Claude Code vs 本项目 关键差异总结

| 维度 | Claude Code 官方 | 本项目实现 | 差距 |
|------|-----------------|-----------|------|
| **事件总数** | 13+ (含 Setup, Elicitation, ElicitationResult, PostCompact) | 10 个 | 缺 4 个新事件 |
| **Hook 类型** | command, http, prompt, agent | command only | 仅实现 command |
| **PreToolUse 决策** | allow / deny / ask / defer | 不返回决策（纯监控） | 缺 defer 支持 |
| **hookSpecificOutput** | 嵌套结构 (推荐) | 顶层 decision/reason (deprecated) | 需迁移 |
| **updatedInput** | PreToolUse 可修改工具输入 | 不支持 | 缺 |
| **additionalContext** | PreToolUse/PostToolUse/UserPromptSubmit/SessionStart 均可注入 | 不支持 | 缺（设计选择） |
| **matcher 模式** | 精确匹配、正则、通配符 `*` | 仅 `"*"` 通配符 | 可扩展 |
| **StatusLine** | `statusLine.command` | ✅ 已实现 | 无差距 |
| **transcript_path** | 所有事件提供 | 未提取 | 低优先级 |
| **permission_mode** | 所有事件提供 | 未提取 | 低优先级 |
| **agent_id/agent_type** | subagent 事件提供 | 未提取 | 低优先级 |
| **超时配置** | 默认 60s，可配置，工具 hook 最长 10min | PermissionRequest 86400s，其他默认 | 基本满足 |
| **热重载** | 会话启动时快照，/hooks 菜单审查变更 | 不涉及（外部配置管理） | N/A |

---

## 优先级排序

| 优先级 | 功能 | 原因 |
|--------|------|------|
| **高** | hookSpecificOutput 格式迁移 (#9) | 当前使用 deprecated 格式，官方可能移除 |
| **中** | Elicitation 事件 (#2) | MCP 生态扩展趋势，审批场景自然延伸 |
| **中** | Notification 细分展示 (#11) | 提升 UI 信息丰富度 |
| **中** | PreToolUse defer 决策 (#5) | 对 `-p` 模式集成有价值 |
| **低** | Setup / PostCompact / ElicitationResult (#1,3,4) | 非核心监控功能 |
| **低** | additionalContext 注入 (#6,7,8) | 与 Claude Island 监控定位不符 |
| **低** | updatedInput (#5) | 需要 UI 支持参数编辑 |
| **低** | transcript_path / permission_mode / agent_id (#12,13) | 信息性字段 |

---

## 参考文档

- 官方 Hooks 参考: https://code.claude.com/docs/en/hooks
- Claude Code GitHub: https://github.com/anthropics/claude-code
- Hook 开发技能: https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md
- v2.1.76 更新日志: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md
