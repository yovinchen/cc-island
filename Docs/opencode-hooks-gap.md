# OpenCode Hooks — 差距分析

> 官方文档: https://opencode.ai/docs/plugins/

## 当前已支持

| 功能 | 状态 | 说明 |
|------|------|------|
| JS 插件格式 | ✅ | `~/.config/opencode/plugins/claude-island.js` |
| onSessionStart | ✅ | 会话开始通知 |
| onSessionEnd | ✅ | 会话结束通知 |
| onToolStart (PreToolUse) | ✅ | 工具执行前通知 |
| onToolEnd (PostToolUse) | ✅ | 工具执行后通知 |
| onStop | ✅ | 任务完成通知 |
| 基础 payload 构造 | ✅ | session_id, cwd, tool_name, tool_input, pid |

## 尚未实现

### 1. JSON 注入漏洞修复 (高优先级)

**问题**: 当前使用 shell echo 传递 JSON，如果 payload 含单引号会导致命令注入：
```javascript
execSync(`echo '${JSON.stringify(payload)}' | ${bridgePath} --source opencode`)
```

**修复方案**: 使用 `input` 选项通过 stdin 管道传递：
```javascript
execSync('bridge_path --source opencode', {
  input: JSON.stringify(payload),
  timeout: 5000,
  stdio: ['pipe', 'pipe', 'pipe']
});
```

---

### 2. tool_response 提取

**说明**: `onToolEnd` 回调的 `tool` 对象可能包含 `result` 或 `output` 属性。

**当前行为**: 未提取工具执行结果。

**优先级**: 中。可丰富 Notch UI 展示。

---

### 3. PermissionRequest 支持

**说明**: OpenCode 插件 API 不提供独立的权限请求回调。

**当前行为**: 不支持通过 Notch 审批。

**状态**: 受限于 OpenCode 插件 API。5s 超时也使权限等待不现实。

---

### 4. 更多插件事件

**说明**: OpenCode 插件 API 可能支持 `chat.message`、`event` 等更多事件钩子。

**当前行为**: 仅使用 5 个核心回调。

**优先级**: 低。当前 5 个事件已覆盖核心状态追踪。

---

### 5. 错误处理改进

**说明**: 当前 `catch {}` 静默吞掉所有错误，不利于调试。

**修复方案**: 可添加简单的错误日志：
```javascript
catch (e) {
  if (process.env.CLAUDE_ISLAND_DEBUG) {
    console.error('[claude-island]', e.message);
  }
}
```

**优先级**: 低。

## OpenCode vs Claude Code 关键差异总结

| 维度 | Claude Code | OpenCode |
|------|------------|----------|
| 配置格式 | settings.json (JSON) | JS 插件模块 |
| 事件数 | 10 | 5 |
| 通信方式 | stdin JSON → bridge → socket | JS → execSync → bridge → socket |
| 权限审批 | PermissionRequest (socket) | ❌ 不支持 |
| 超时 | 86400s (权限) | 5s (所有事件) |
| 热重载 | ✅ | 需重启 OpenCode |
| StatusLine | ✅ | ❌ |
| 工具结果 | PostToolUse 含 tool_response | ❌ 未提取 |
