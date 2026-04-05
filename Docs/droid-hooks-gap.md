# Droid (Factory) Hooks — 差距分析

> 官方文档: https://docs.factory.ai/cli/configuration/hooks-guide

## 当前已支持

| 功能 | 状态 | 说明 |
|------|------|------|
| settings.json 配置 | ✅ | `~/.factory/settings.json`，与 Claude Code 格式兼容 |
| SessionStart | ✅ | 会话开始 |
| SessionEnd | ✅ | 会话结束 |
| PreToolUse | ✅ | 工具执行前（matcher: *） |
| PostToolUse | ✅ | 工具执行后（matcher: *） |
| UserPromptSubmit | ✅ | 用户提交消息 |
| Stop | ✅ | 任务完成 |
| SubagentStop | ✅ | 子代理完成 |
| Notification | ✅ | 通知事件（matcher: *） |
| PreCompact | ✅ | 上下文压缩 |
| hookSpecificOutput 响应 | ✅ | 在 HookSocketServer 的 hookSpecificOutputSources 中 |

## 尚未实现

### 1. PermissionRequest 事件 (高优先级)

**说明**: Droid 与 Claude Code 格式兼容，且已在 `hookSpecificOutputSources` 中。但当前未注册 `PermissionRequest` 事件。

**当前行为**: Droid 注册了 9 个事件，缺少 PermissionRequest。即使 Droid CLI 发送权限请求，也不会被 hook 捕获。

**改进方案**: 添加 `PermissionRequest` 事件，设置 86400s 超时（与 Claude Code 一致）。

**影响**: 可实现通过 Notch 审批 Droid 的权限请求，大幅提升用户体验。

---

### 2. Exit Code 2 阻塞模式

**说明**: Droid 支持 `exit code 2` 阻塞工具执行。

**当前行为**: bridge 始终 exit 0。

**改进方案**: 当用户在 Notch 中 Deny 时，bridge 返回 exit code 2。

**优先级**: 中。需要 bridge 端改造。

---

### 3. PreToolUse 的 updatedInput

**说明**: Droid 可能支持通过 PreToolUse hook 修改工具输入。

**当前行为**: 未实现。

**优先级**: 低。

---

### 4. PostToolUse 的 feedback

**说明**: Droid 可能支持 PostToolUse hook 返回 feedback。

**当前行为**: 未实现。

**优先级**: 低。

## Droid vs Claude Code 关键差异总结

| 维度 | Claude Code | Droid |
|------|------------|-------|
| 格式兼容性 | 参考实现 | ✅ 完全兼容 |
| 事件数 | 10 | 9（缺 PermissionRequest） |
| 权限响应 | hookSpecificOutput | hookSpecificOutput（已配置但未注册事件） |
| 权限超时 | 86400s | 未设置 |
| StatusLine | ✅ | ❌ |
| exit code 2 | 不使用 | 支持阻塞模式 |
| 配置目录 | `~/.claude` | `~/.factory` |
