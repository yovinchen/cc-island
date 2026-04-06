# Kimi Code CLI Hooks — 差距分析

> Hooks (Beta): https://moonshotai.github.io/kimi-cli/zh/customization/hooks.html
> 配置文件: https://moonshotai.github.io/kimi-cli/en/configuration/config-files.html
> IDE / ACP: https://moonshotai.github.io/kimi-cli/en/guides/ides.html
> 分析日期: 2026-04-06

## 当前仓库状态

| 项目 | 状态 | 说明 |
|------|------|------|
| `SessionSource` / `HookSource` | ✅ | 当前已新增 `kimi_cli` source 与安装器 |
| 安装检测 | ✅ | 已检测 `~/.kimi` 与常见 `kimi` 可执行路径 |
| Hook / ACP 适配 | ⚠️ | hooks 已接入；ACP 仍未实现 |

## 官方已提供的 Hook 能力

| 能力 | 状态 | 说明 |
|------|------|------|
| 生命周期 hooks | ✅ Beta | 官方文档列出 13 个事件 |
| 配置文件 | ✅ | `~/.kimi/config.toml` 中用 `[[hooks]]` 定义 |
| stdin JSON / exit code | ✅ | stdin 传上下文，exit `2` 可阻止操作 |
| 结构化输出 | ✅ | 支持 `hookSpecificOutput.permissionDecision` |
| ACP | ✅ | `kimi acp` 可供 JetBrains / Zed 等 IDE 接入 |

## 与现有仓库的差距

1. Kimi CLI 的 hook 模型和现有 `GenericSettingsHookSource` 很接近，但配置是 TOML 数组，不是 JSON `hooks` 对象。
2. 仓库目前既没做 hooks，也没做 ACP，因此在 Kimi 上是完全空白。
3. Kimi 还提供 `kimi acp`，后续存在“hooks 路线”和“ACP 路线”两种实现分支。

## 实现建议

1. 先做 hooks：因为 `PreToolUse` / `PostToolUse` / `Stop` / `SessionStart` 等事件已经足够覆盖 Claude Island 的核心 UI。
2. 再评估 ACP：更适合未来做 IDE 端嵌入或多会话管理。
3. README 中标记为“官方 hooks 已存在，当前未接入”。

## 结论

Kimi CLI **现已完成 hooks 首版接入**。当前通过 `config.toml` 的受管 block 安装 hooks，并已接入基础审批返回；ACP 仍待后续阶段实现。

## 基于本地代码的实现可行性

**可行性评级**: 高（hooks） / 中（ACP）

**可直接复用**
- `CodexHookSource` 已经证明本仓库能处理“CLI hooks + TOML/额外配置文件”路线。
- `HookSocketServer` 里现成有多套返回协议分支，可以继续扩展 Kimi 的 stdout 响应格式。

**最小实现方案**
1. 已复用 Codex 的 TOML 管理思路，实现 `KimiHookSource`。
2. 当前 hooks block 已继续补到更接近官方 13 事件，包含 `PostToolUseFailure`、`StopFailure`、`SubagentStart` 等补点。
3. 已把 Kimi 事件接到 `EventMapper` / `PermissionHandler` / `HookSocketServer` 的隐式审批链路。
4. 当前 `EventMapper` 已继续补 `error_message / error_type / agent_name / response / title / body / sink / trigger / reason` 等字段提取，让 `StopFailure`、`Subagent*`、`Notification`、`PostCompact` 这类事件在 UI 中更可读。
5. ACP 继续单独作为第二阶段，不和 hooks 首版耦合。

**主要阻塞**
- 当前主要阻塞只剩 ACP 路线，以及更完整的事件覆盖和真实联调验证。
