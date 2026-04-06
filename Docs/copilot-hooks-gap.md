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

`CopilotHookSource` 当前已注册 **10 个事件**：

| 功能 | 状态 | 说明 |
|------|:----:|------|
| `~/.copilot/config.json` 配置 | ✅ | 全局用户级配置 |
| `sessionStart` | ✅ | 会话开始 |
| `sessionEnd` | ✅ | 会话结束 |
| `preToolUse` | ✅ | 工具执行前 |
| `postToolUse` | ✅ | 工具执行后 |
| `postToolUseFailure` | ✅ | 工具失败后 |
| `errorOccurred` | ✅ | 会话级错误 |
| `userPromptSubmitted` | ✅ | 用户提交 prompt |
| `preCompact` | ✅ | 上下文压缩前 |
| `notification` | ✅ | 通知事件 |
| `stop` | ✅ | 任务完成（非官方事件名，依赖 Copilot 是否实际触发） |
| EventMapper 事件标准化 | ✅ | `sessionstart`→`SessionStart` 等 camelCase→PascalCase 映射 |

## 尚未实现

### 1. `preToolUse` 审批流（已补首版）

**官方行为**: Copilot CLI 通过 `preToolUse` 的 stdout JSON 返回 `permissionDecision`，而不是 Claude 风格的独立 `PermissionRequest` 事件。

**当前行为**: 当前代码已把危险 `preToolUse` 识别为隐式审批请求，并返回 Copilot 风格的平铺 JSON：

```json
{
  "permissionDecision": "allow|deny",
  "permissionDecisionReason": "..."
}
```

**当前限制**:
1. 仅对高风险工具触发 Notch 审批
2. 当前已补通 `modifiedArgs` 原型通路，会在 allow 且有原始 `tool_input` 时回传该字段
3. 当前 Copilot 返回值同时带 `permissionDecisionReason` 与 `reason`，提高对不同 CLI 变体的兼容性。
4. EventMapper 已继续补 `toolArgs / modifiedArgs / partialResult / result / assistant / errorMessage` 等常见嵌套字段提取，但还未做真实 CLI 端联调验证
5. 基于本机 `copilot -p --output-format json` 样本，当前桥接也已开始识别 `user.message`、`assistant.message`、`assistant.turn_end`、`result`、`session.mcp_*` 等 JSON 事件形状，为后续非 hook 观察路径预留兼容层。

---

### 2. postToolUseFailure / errorOccurred / preCompact（已接入）

**当前行为**: 当前安装器已经写入 `postToolUseFailure`、`errorOccurred`、`preCompact`、`notification`。

**剩余价值**:
1. 继续完善这些事件的字段提取
2. 联调确认 `notification` 是否确实被 Copilot CLI 触发

---

### 5. 项目级 hooks 配置 (低优先级)

**官方行为**: Copilot 支持 `.github/hooks/*.json` 项目级配置，合并到默认分支后自动生效。

**当前行为**: 仅管理全局 `~/.copilot/config.json`。

**当前补充**:
- 运行时现在会检测项目级 `.github/hooks/` 目录下的 JSON hooks 文件，并提示它们可能覆盖用户级 hooks。

**改进方案**: 后续再决定是否支持扫描和注入项目级 `.github/hooks/` 目录中的配置文件。

**本地代码补充**:
- 当前 `CopilotHookSource` 已开始为 `preToolUse` 写入 `timeoutSec = 120`，与当前隐式审批等待窗口对齐。

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
| 官方事件总数 | 12+ | 9 | 9+/9 近似覆盖 |
| preToolUse 拦截 | ✅ exitCode 控制 | ✅ JSON stdout 控制 | ❌ 无返回值 |
| postToolUseFailure | ✅ | ✅ | ✅ 已注册 |
| PermissionRequest | ✅ socket 审批 | ✅ stdout 审批 | ❌ 未注册 |
| Notification | ✅ | ❌ 无此事件 | — |
| errorOccurred | ❌（无对应） | ✅ | ✅ 已注册 |
| PreCompact | ✅ | ✅ | ✅ 已注册 |
| SubagentStop | ✅ | ❌ | — |
| Prompt Hook | ❌ | ✅ sessionStart 可注入 prompt | — |
| 超时配置 | `timeout` 字段 | `timeoutSec` 字段 | ❌ 未配置 |

## 推荐改进优先级

1. **P1**: 实测验证 `preToolUse` 的审批返回是否与 Copilot CLI 完全一致
2. **P1**: 验证 `stop` 事件是否被 Copilot CLI 实际触发
3. **P2**: 实现 `modifiedArgs`
4. **P2**: 支持项目级 `.github/hooks/` 配置注入

## 基于本地代码的实现可行性

**可行性评级**: 高

**本地代码复核结果**
- 这份文档也有部分过时。当前 `CopilotHookSource` 已注册 `postToolUseFailure`、`errorOccurred`、`preCompact`、`notification` 等更多事件。
- `EventMapper` 已能识别 `errorOccurred`、`postToolUseFailure` 等别名，事件归一化不是主要问题。
- 当前代码已经新增 `.copilot` 专用审批响应分支，并通过危险 `preToolUse` 走隐式审批。
- 剩余问题从“有没有审批通道”变成“响应字段是否完全与官方 CLI 对齐”。

**最小实现方案**
1. 以当前 `CopilotHookSource` + 隐式审批为基线，完成 CLI 联调。
2. 如有需要，再补 `modifiedArgs`。
3. 若要支持项目级 `.github/hooks/`，补 `managedConfigPaths`、安装选择逻辑和自动修复名单。

**主要阻塞**
- Copilot 的剩余工作集中在联调和项目级配置，不在 installer 骨架；骨架已经有了。
