# Kiro IDE / CLI Hooks — 差距分析

> IDE Hooks: https://kiro.dev/docs/hooks/types/
> CLI Hooks: https://kiro.dev/docs/cli/hooks/
> CLI 配置: https://kiro.dev/docs/cli/chat/configuration/
> 分析日期: 2026-04-06

## 当前仓库状态

| 项目 | 状态 | 说明 |
|------|------|------|
| `SessionSource` / `HookSource` | ⚠️ | 当前已新增 `kiro_cli` source，并通过自定义 agent 文件提供 hooks |
| 安装检测 / UI | ✅ | README、Onboarding、Settings、Notch 已加入 Kiro |
| Hook/审批链路 | ⚠️ | 已生成 `claude-island` agent hooks 文件并接入基础事件映射；尚未自动切换为默认 agent |

## 官方可用扩展面

| 能力 | IDE | CLI | 说明 |
|------|-----|-----|------|
| Hooks | ✅ | ✅ | 两端都有官方 hooks 文档 |
| Tool hooks | ✅ | ✅ | IDE 有 Pre/Post Tool；CLI 有 Pre/Post Tool |
| Prompt hook | ✅ | ✅ | IDE `Prompt Submit`；CLI `UserPromptSubmit` |
| Stop/turn-end | ✅ | ✅ | IDE `Agent Stop`；CLI `Stop` |
| 文件事件 | ✅ | ❌ | IDE 额外支持 File Create / Save / Delete |
| ACP / 自定义 agents | — | ✅ | CLI 文档公开了 agent 配置目录 |

## 与现有仓库的差距

1. Kiro 是少数同时拥有 IDE hooks 和 CLI hooks 的目标，但仓库当前完全未接入。
2. 需要决定优先支持 IDE 还是 CLI，因为二者事件模型不完全相同。
3. IDE hooks 还支持 shell command 与 agent prompt 两种 action，需要明确只支持 shell-command 子集还是完整能力。

## 实现建议

1. 先做 `kiro-cli` 路线，原因是 JSON + stdin/stdout + exit code 更贴近现有架构。
2. 后续再评估 Kiro IDE hooks 是否值得单独建 `kiro_ide` source，还是合并成统一 `kiro`。
3. README 中把 Kiro 标为“官方有 hooks，当前未接入”。

## 结论

Kiro **当前处于部分支持状态**。Claude Island 已能生成 `claude-island` 自定义 agent 配置并接入基础 hooks，但用户仍需显式使用该 agent。

## 基于本地代码的实现可行性

**可行性评级**: 中高

**可直接复用**
- CLI 路线可复用 `CodexHookSource` / `CursorHookSource` 的“独立安装器 + 自定义事件表”模式。
- 统一消费端可直接复用 `EventMapper`、`HookSocketServer`、UI source 列表。

**最小实现方案**
1. 已按 Kiro CLI 路线新增自定义 `KiroHookSource`。
2. 当前实现通过 `~/.kiro/agents/claude-island.json` 提供 hooks，而不是修改用户现有 agent。
3. 当前会同步安装 `~/.claude-island/bin/claude-island-kiro` wrapper，简化 `--agent claude-island` 的使用方式。
4. 当前 wrapper 已尊重 `--agent foo`、`--agent=foo`、`-a foo`、`-a=foo` 以及 `--help/--version`，避免覆盖用户显式意图。
5. 后续若要补强，再决定是否支持自动设置默认 agent。

**主要阻塞**
- 当前最大阻塞不是 hooks 骨架，而是产品策略：是否允许 Claude Island 自动改写 Kiro 的默认 agent 选择。
