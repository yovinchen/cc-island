# Qoder Hooks 集成差距分析

> 官方文档: https://docs.qoder.com/zh/extensions/hooks

## 当前已支持

| 功能 | 状态 | 说明 |
|------|------|------|
| 配置文件格式 | ✅ | PascalCase 事件名、嵌套 `{matcher, hooks}` 结构 |
| 5 个事件注册 | ✅ | UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Stop |
| 多层配置托管 | ✅ | 当前会始终管理 `~/.qoder/settings.json`，并在存在时同步管理 `.qoder/settings.json` / `.qoder/settings.local.json` |
| matcher 正则匹配 | ✅ | PreToolUse/PostToolUse/PostToolUseFailure 使用 `"*"` 通配符 |
| stdin JSON 输入解析 | ✅ | bridge 正确解析 session_id, cwd, tool_name 等字段 |
| 基础状态追踪 | ✅ | 工具执行状态同步到 Notch UI |

## 尚未实现

### 1. PreToolUse 权限决策 (`permissionDecision`)

**Qoder 差异**: 没有独立的 `PermissionRequest` 事件。权限通过 PreToolUse hook 的 stdout 返回。

**Qoder 期望的 PreToolUse 响应格式**:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "reason text",
    "updatedInput": { "command": "modified command" },
    "additionalContext": "additional info for agent"
  }
}
```

**当前行为**: bridge 收到 PreToolUse 时仅通知 app 更新状态，立即返回空响应。

**实现思路**: 与 CodeBuddy 相同 — bridge 需要对 Qoder 来源的 PreToolUse 阻塞等待用户决策。

---

### 2. Exit Code 2 阻塞模式

**说明**: Qoder 支持 hook 脚本通过 exit code 阻止操作。

| Exit Code | 含义 | 行为 |
|-----------|------|------|
| 0 | 成功 | 继续执行，解析 stdout JSON |
| 2 | 阻塞 | PreToolUse/UserPromptSubmit: 阻止执行，stderr 作为错误信息 |
| 其他 | 非阻塞错误 | 显示 stderr 为警告，继续执行 |

**当前行为**: bridge 始终 exit 0。

**可阻塞的事件**: 仅 `PreToolUse` 和 `UserPromptSubmit`。PostToolUse/PostToolUseFailure/Stop 即使返回 exit 2 也视为 exit 0。

---

### 3. PostToolUseFailure 事件处理

**说明**: Qoder 独有事件，当工具执行失败时触发。

**输入字段**:
```json
{
  "session_id": "...",
  "cwd": "...",
  "hook_event_name": "PostToolUseFailure",
  "transcript_path": "...",
  "tool_name": "Bash",
  "tool_input": { "command": "..." },
  "error": "error message"
}
```

**当前行为**: 已注册该事件，bridge 会将其发送到 socket server。但 app 端可能将其视为未知事件类型。

**优化方向**: 在 UI 中显示工具执行失败状态，记录错误信息。

---

### 4. `updatedInput` — 修改工具输入

**说明**: PreToolUse hook 可通过 `updatedInput` 字段修改即将执行的工具参数。

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "updatedInput": {
      "command": "safer version of the command"
    }
  }
}
```

**当前行为**: 未实现。Notch UI 仅展示/审批，不修改工具输入。

**优先级**: 低。

---

### 5. `additionalContext` — 上下文注入

**说明**: UserPromptSubmit 和 PreToolUse 的 hook 可返回 `additionalContext`，注入到 Agent 上下文。

**当前行为**: 未实现。

**优先级**: 低。Claude Island 定位为监控/审批工具。

---

### 6. PostToolUse `feedback` 字段

**说明**: PostToolUse hook 可返回 `feedback` 字符串，Agent 会在后续推理中参考。

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "feedback": "lint check passed with 2 warnings"
  }
}
```

**当前行为**: 未实现。

**优先级**: 低。

---

### 7. 无 SessionStart/SessionEnd 事件

**影响**: Claude Island 依赖 SessionStart 创建会话、SessionEnd 标记会话结束。Qoder 不发送这些事件。

**当前行为**: 会话可能无法被正确创建/关闭。需要依赖 PreToolUse 首次到达时隐式创建会话，Stop 事件时推断结束。

**已有 workaround**: bridge 的 socket 通信在收到任何事件时都会创建/更新 session state，所以实际上通过 PreToolUse/PostToolUse 等事件已能追踪会话。但缺少明确的 start/end 生命周期信号。

---

## Qoder vs Claude Code 关键差异总结

| 维度 | Claude Code | Qoder |
|------|------------|-------|
| 事件数 | 10 | 5 |
| 权限事件 | 独立 `PermissionRequest` | 通过 `PreToolUse` 的 `permissionDecision` |
| 权限持久化 | `updatedPermissions` (setMode/addRules) | ❌ 不支持 |
| 会话生命周期 | SessionStart + SessionEnd | ❌ 无（靠 PreToolUse/Stop 推断） |
| 通知事件 | Notification | ❌ 无（Stop 的 `last_assistant_message` 可替代） |
| 上下文压缩 | PreCompact (auto/manual) | ❌ 无 |
| 独有事件 | SubagentStop | PostToolUseFailure |
| 超时 | 86400s (PermissionRequest) | 30s（所有事件统一） |
| 工具名 | Bash, Write, Edit... | 双重映射: run_in_terminal↔Bash, create_file↔Write |
| StatusLine | ✅ | ❌ |
| 热重载 | ✅ | ❌ 需重启 IDE |

## Qoder 工具名映射表

| Qoder 原生名 | Claude Code 兼容名 |
|-------------|-------------------|
| run_in_terminal | Bash |
| create_file | Write |
| search_replace | Edit |
| read_file | Read |
| grep_code | Grep |
| search_file | Glob |
| list_dir | LS |
| task | Task |
| search_web | WebSearch |
| fetch_content | WebFetch |

## 基于本地代码的实现可行性

**可行性评级**: 高（审批） / 中（工具失败展示）

**本地代码复核结果**
- 文档中“PreToolUse 权限决策未实现”的结论已过时。`PermissionHandler.isImplicitPermissionRequest()` 已把 `qoder` 的危险工具调用视为隐式审批请求。
- `HookSocketServer.buildResponseData()` 也已为 `.qoder` 返回 `hookSpecificOutput.permissionDecision`。
- `EventMapper` 和 `SessionStore` 已识别 `PostToolUseFailure`，因此剩余问题主要是 UI 表达和 exit code 语义，而不是基础协议缺失。
- 当前运行时也会在检测到项目级 `.qoder/settings.json` / `.qoder/settings.local.json` 时给出提示，并在这些文件已存在时同步纳入受管安装，减少“只改了用户级配置但项目级覆盖仍在”的误判。

**最小实现方案**
1. 同步本文旧结论，标明隐式审批链路已经存在。
2. 在 bridge 侧补 `deny -> exit code 2`，让 Qoder 真正阻止动作。
3. 在 UI 中强化 `PostToolUseFailure` 的错误展示，而不是只当普通 processing 事件。
4. 保持单一 `qoder` source，不额外拆 `qoder_cli`，但继续复用同一套多层配置托管。

**主要阻塞**
- `exit code 2` 需要改 bridge 进程退出行为，这会影响所有隐式审批源，不能只改文档层。
