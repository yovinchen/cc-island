# Copilot CLI Hooks — 差距分析

> 官方文档: https://docs.github.com/en/copilot/reference/hooks-configuration
> 参考教程: https://docs.github.com/en/copilot/tutorials/copilot-cli-hooks
> 最后更新: 2026-04-05

## 官方支持的事件类型

GitHub Copilot CLI（2026-02 GA）官方支持以下 Hook 事件：

| 事件 | 说明 | 可控制执行 |
|------|------|:----------:|
| `sessionStart` | 会话开始 / 恢复 | ❌ |
| `sessionEnd` | 会话结束 / 终止 | ❌ |
| `userPromptSubmitted` | 用户提交 prompt | ❌ |
| `preToolUse` | 工具执行前（可拦截） | ✅ allow/deny/ask |
| `postToolUse` | 工具成功执行后 | ❌ |
| `postToolUseFailure` | 工具执行失败后 | ❌ |
| `PermissionRequest` | 脚本审批工具权限请求 | ✅ allow/deny |
| `errorOccurred` | 会话错误 | ❌ |
| `preCompact` | 上下文压缩前 | ❌ |

> **preToolUse** 是最强大的 Hook，可返回 `permissionDecision: "allow" | "deny" | "ask"` 或 `modifiedArgs` 修改工具参数。
> **PermissionRequest** 允许脚本代替用户自动审批或拒绝权限弹窗。

## 当前已支持

`CopilotHookSource` 注册了 **6 个事件**（见 `HookInstaller.swift:1289`）：

| 功能 | 状态 | 说明 |
|------|:----:|------|
| `~/.copilot/config.json` 配置 | ✅ | 全局用户级配置 |
| `sessionStart` | ✅ | 会话开始 |
| `sessionEnd` | ✅ | 会话结束 |
| `preToolUse` | ✅ | 工具执行前 |
| `postToolUse` | ✅ | 工具执行后 |
| `userPromptSubmitted` | ✅ | 用户提交 prompt |
| `stop` | ✅ | 任务完成（非官方事件名，依赖 Copilot 是否实际触发） |
| EventMapper 事件标准化 | ✅ | `sessionstart`→`SessionStart` 等 camelCase→PascalCase 映射 |

## 尚未实现

### 1. PermissionRequest 事件 (高优先级)

**官方行为**: Copilot CLI 已支持 `PermissionRequest` Hook，脚本可通过 stdout 返回 JSON 来程序化审批或拒绝工具权限请求。

**当前行为**: 未注册该事件。Copilot 会话不支持 Notch 审批流。

**影响**: 无法通过 ClaudeIsland UI 审批 Copilot 的权限请求，用户仍需在终端手动操作。

**改进方案**:
1. 在 `CopilotHookSource.install()` 的事件列表中添加 `"PermissionRequest"`
2. EventMapper 已有 `permissionrequest` → `PermissionRequest` 映射，无需额外修改
3. 需要实现 socket 通道以支持双向审批通信

---

### 2. postToolUseFailure 事件 (中优先级)

**官方行为**: `postToolUseFailure` 在工具执行失败后触发，与 `postToolUse`（仅成功时触发）分离。

**当前行为**: 未注册。工具失败信息无法被监控。

**改进方案**: 在事件列表中添加 `"postToolUseFailure"`。EventMapper 已有 `posttoolusefailure` → `PostToolUseFailure` 映射。

---

### 3. errorOccurred 事件 (中优先级)

**官方行为**: 会话级错误（非单个工具失败）会触发 `errorOccurred`。

**当前行为**: 未注册。EventMapper 已有 `erroroccurred` → `Notification` 映射。

**改进方案**: 在事件列表中添加 `"errorOccurred"`，映射为 `Notification` 事件。

---

### 4. preCompact 事件 (低优先级)

**官方行为**: 上下文压缩前触发，可在压缩前执行自定义逻辑。

**当前行为**: 未注册。EventMapper 已有 `precompact` → `PreCompact` 映射。

**改进方案**: 在事件列表中添加 `"preCompact"`。

---

### 5. 项目级 hooks 配置 (低优先级)

**官方行为**: Copilot 支持 `.github/hooks/*.json` 项目级配置，合并到默认分支后自动生效。

**当前行为**: 仅管理全局 `~/.copilot/config.json`。

**改进方案**: 支持扫描和注入项目级 `.github/hooks/` 目录中的配置文件。

---

### 6. preToolUse 返回值处理 (低优先级)

**官方行为**: `preToolUse` Hook 可返回结构化 JSON 到 stdout：
```json
{"permissionDecision": "deny", "reason": "Blocked by policy"}
```
或修改工具参数：
```json
{"modifiedArgs": {"command": "echo 'sanitized'"}}
```

**当前行为**: Bridge 仅单向转发事件到 ClaudeIsland UI，不向 Copilot CLI 返回控制指令。

**影响**: 无法通过 ClaudeIsland 实现工具拦截或参数修改。

**改进方案**: 实现 Bridge 的 stdout 返回通道，使 Notch UI 的审批结果能通过 Bridge→stdout→Copilot CLI 传递。

---

### 7. `stop` 事件名称适配 (确认项)

**当前行为**: 注册了 `stop` 事件，但官方文档未列出 `stop` 作为标准事件名。

**风险**: 如果 Copilot CLI 不触发 `stop` 事件，则任务完成信号会丢失。

**确认方案**: 需实际测试 Copilot CLI 是否触发 `stop` 事件，或是否应使用 `sessionEnd` 替代。

## Copilot vs Claude Code 关键差异总结

| 维度 | Claude Code | Copilot CLI | ClaudeIsland 适配状态 |
|------|------------|-------------|:--------------------:|
| 配置文件 | `~/.claude/settings.json` | `~/.copilot/config.json` | ✅ |
| 项目级配置 | `~/.claude/` | `.github/hooks/*.json` | ❌ 仅全局 |
| 配置格式 | 嵌套 `{matcher, hooks}` | 扁平 `{hooks: {event: [{type, command}]}}` | ✅ |
| 事件名风格 | PascalCase | camelCase | ✅ EventMapper 转换 |
| 官方事件总数 | 12+ | 9 | 6/9 已注册 |
| preToolUse 拦截 | ✅ exitCode 控制 | ✅ JSON stdout 控制 | ❌ 无返回值 |
| postToolUseFailure | ✅ | ✅ | ❌ 未注册 |
| PermissionRequest | ✅ socket 审批 | ✅ stdout 审批 | ❌ 未注册 |
| Notification | ✅ | ❌ 无此事件 | — |
| errorOccurred | ❌（无对应） | ✅ | ❌ 未注册 |
| PreCompact | ✅ | ✅ | ❌ 未注册 |
| SubagentStop | ✅ | ❌ | — |
| Prompt Hook | ❌ | ✅ sessionStart 可注入 prompt | — |
| 超时配置 | `timeout` 字段 | `timeoutSec` 字段 | ❌ 未配置 |

## 推荐改进优先级

1. **P0**: 注册 `PermissionRequest` 事件 + 实现 socket 审批通道 → 解锁 Notch 审批能力
2. **P1**: 注册 `postToolUseFailure` + `errorOccurred` → 完善错误监控
3. **P1**: 验证 `stop` 事件是否被 Copilot CLI 实际触发
4. **P2**: 注册 `preCompact` → 追踪上下文压缩
5. **P2**: 实现 preToolUse stdout 返回通道 → 支持工具拦截
6. **P3**: 支持项目级 `.github/hooks/` 配置注入
