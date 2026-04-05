# CodeBuddy Hooks 集成差距分析

> 官方文档: https://www.codebuddy.ai/docs/ide/Features/hooks#configuration-guide

## 当前已支持

| 功能 | 状态 | 说明 |
|------|------|------|
| 配置文件格式 | ✅ | PascalCase 事件名、嵌套 `{matcher, hooks}` 结构，与 Claude Code 格式一致 |
| 7 个事件注册 | ✅ | SessionStart, SessionEnd, PreToolUse, PostToolUse, UserPromptSubmit, Stop, PreCompact |
| matcher 正则匹配 | ✅ | PreToolUse/PostToolUse 使用 `"*"` 通配符 |
| timeout 可配置 | ✅ | 默认 60s，可按 hook 自定义 |
| stdin JSON 输入解析 | ✅ | bridge 正确解析 session_id, cwd, tool_name 等字段 |
| 基础状态追踪 | ✅ | session 创建/结束/工具执行状态同步到 Notch UI |

## 尚未实现

### 1. PreToolUse 权限决策 (`permissionDecision`)

**CodeBuddy 差异**: 没有独立的 `PermissionRequest` 事件。权限审批通过 PreToolUse hook 的 stdout 返回 `permissionDecision` 字段实现。

**CodeBuddy 期望的 PreToolUse 响应格式**:
```json
{
  "continue": true,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "reason text"
  }
}
```

**当前行为**: bridge 收到 PreToolUse 时仅通知 app 更新状态，立即返回空响应。不支持阻塞等待用户审批。

**实现思路**:
- bridge 收到 CodeBuddy 的 PreToolUse 时，检查是否需要审批（如 Bash 工具）
- 如需审批，发送到 socket server 并阻塞等待用户决策
- socket server 返回 `permissionDecision` 格式（而非 Claude Code 的 `decision.behavior` 格式）
- 需在 `HookSocketServer.buildResponseData` 中添加 CodeBuddy 专用响应构造器

**影响文件**: `claude-island-bridge-launcher.sh`、`HookSocketServer.swift`

---

### 2. Exit Code 2 阻塞模式

**说明**: CodeBuddy 支持 hook 脚本通过 exit code 2 阻止工具执行。

| Exit Code | 含义 | 行为 |
|-----------|------|------|
| 0 | 成功 | 继续执行，处理 stdout |
| 1 | 非阻塞错误 | 显示 stderr 为警告，继续 |
| 2 | 阻塞错误 | PreToolUse: 阻止执行；Stop: 注入反馈 |

**当前行为**: bridge 始终 exit 0。

**实现思路**: 当用户在 Notch 中点击 Deny 时，bridge 返回 exit code 2 + stderr 信息。

---

### 3. `continue` / `suppressOutput` 输出字段

**说明**: CodeBuddy hook stdout 支持以下控制字段。

```json
{
  "continue": false,        // false = 停止后续 hook 执行
  "suppressOutput": true,   // true = 不显示 hook 输出给用户
  "systemMessage": "...",   // 注入系统消息
  "stopReason": "..."       // 停止原因
}
```

**当前行为**: 未返回这些字段。

**优先级**: 低。当前场景下无实际需求。

---

### 4. `modifiedInput` — 修改工具输入

**说明**: PreToolUse hook 可通过 `modifiedInput` 字段修改即将执行的工具参数。

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "modifiedInput": {
      "command": "modified command here"
    }
  }
}
```

**当前行为**: 未实现。Notch UI 仅展示/审批，不修改工具输入。

**优先级**: 低。属于高级 hook 功能。

---

### 5. `additionalContext` — 上下文注入

**说明**: SessionStart、UserPromptSubmit、PostToolUse、PreCompact 事件的 hook 可返回 `additionalContext` 字符串，注入到 AI 的上下文中。

**当前行为**: 未实现。bridge 对这些事件仅做通知，不返回内容。

**优先级**: 低。Claude Island 定位为监控/审批工具，非上下文注入工具。

---

## CodeBuddy vs Claude Code 关键差异总结

| 维度 | Claude Code | CodeBuddy |
|------|------------|-----------|
| 权限事件 | 独立 `PermissionRequest` 事件 | 通过 `PreToolUse` 的 `permissionDecision` |
| 权限持久化 | `updatedPermissions` (setMode/addRules) | ❌ 不支持，每次 PreToolUse 独立决策 |
| 权限响应格式 | `decision.behavior: "allow"` | `permissionDecision: "allow"` |
| 权限超时 | 86400s (24h) | 默认 60s |
| 事件数 | 10 (含 PermissionRequest, Notification, SubagentStop) | 7 |
| StatusLine | ✅ 支持 | ❌ 不支持 |
| exit code 语义 | 0/非0 | 0/1/2 (2=阻塞) |
| 环境变量 | — | `CODEBUDDY_PROJECT_DIR`, `CLAUDE_PROJECT_DIR` |
| 工具名别名 | CLI 名 (Bash, Write) | CLI 名 + IDE 名 (execute_command, write_to_file) |
