# CLI 集成总路线图

> 适用仓库: `claude-island`
> 更新时间: 2026-04-06
> 目标: 统一梳理所有 CLI 类集成的当前状态、剩余缺口、推荐实现路线与自动推进顺序。

## 当前结论总览

按当前仓库状态，CLI 类对象可以分成 4 组：

## 当前代码完成度快照

以下快照以当前代码为准，判断标准是：
- `正式接入`: runtime 已稳定存在，当前路线图把它视为正式支持
- `部分支持`: 已有 source 或 wrapper/plugin 路线，但仍依赖特定入口、事件覆盖不足或联调不足
- `仅文档`: 仓库里只有 gap/roadmap，没有 runtime 代码

| CLI | 当前代码状态 | 依据 |
|-----|--------------|------|
| Claude Code | 正式接入 | `SessionSource.claude` + `ClaudeHookSource` |
| Codex CLI | 正式接入 | `SessionSource.codexCLI` + `CodexHookSource` |
| Codex Desktop | 正式接入 | `SessionSource.codexDesktop` + `CodexSessionWatcher` |
| Gemini CLI | 正式接入 | `SessionSource.gemini` + `GeminiHookSource` |
| Cursor | 正式接入 | `SessionSource.cursor` + `CursorHookSource` |
| OpenCode | 正式接入 | `SessionSource.opencode` + `OpenCodeHookSource` |
| Copilot CLI | 部分支持 | `SessionSource.copilot` + `CopilotHookSource`，但 payload/联调仍在继续 |
| Qoder IDE hooks | 正式接入 | `SessionSource.qoder` + `QoderHookSource` |
| Droid | 正式接入 | `SessionSource.droid` + `DroidHookSource` |
| CodeBuddy | 正式接入 | `SessionSource.codebuddy` + `CodeBuddyHookSource` |
| Windsurf | 部分支持 | `SessionSource.windsurf` + `WindsurfHookSource`，但 hooks 覆盖仍在补齐 |
| Kimi CLI | 部分支持 | `SessionSource.kimiCLI` + `KimiHookSource`，但 hooks/联调仍偏首版 |
| Kiro CLI | 部分支持 | `SessionSource.kiroCLI` + custom agent/wrapper 路线 |
| Amp CLI | 部分支持 | `SessionSource.ampCLI` + plugin + `amp-exec` fallback + `amp-stream` helper |
| Cline / Cline CLI | 部分支持 | `SessionSource.cline` + `ClineHookSource`，当前先做 hooks 监控与启用诊断 |
| Qoder CLI | 仅文档 | `Docs/qoder-cli-hooks-gap.md`，当前明确不拆 source |
| Pi Coding Agent | 部分支持 | `SessionSource.pi` + `claude-island-pi` / `pi-json` helpers |
| Crush | 部分支持 | `SessionSource.crush` + wrapper + `CrushLogWatcher` 最小日志解析 |

### A. 已接入，可持续打磨

| CLI | 当前状态 | 后续重点 |
|-----|----------|----------|
| Claude Code | 已接入 | `Setup / PostCompact / Elicitation*` 可观测性继续增强 |
| Codex CLI | 已接入 | stdout 协议细节与 CLI/Desktop 对齐 |
| Codex Desktop | 已接入 | transcript 继续补 `response_item` / `event_msg` 细节 |
| Gemini CLI | 已接入 | Gemini 独有生命周期与项目级配置诊断 |
| OpenCode | 已接入 | 保持 plugin 路线，继续做只读增强 |
| Droid | 已接入 | 继续打磨审批与错误态 |
| CodeBuddy | 已接入 | 继续打磨隐式审批与阻塞语义 |
| Qoder (IDE hooks) | 已接入 | 继续保留 IDE/extension 路线，不和 CLI 混淆 |

### B. 已部分接入，可继续增强

| CLI | 当前状态 | 后续重点 |
|-----|----------|----------|
| Kimi CLI | 已部分接入 | 更完整事件覆盖、联调、ACP 暂缓 |
| Kiro CLI | 已部分接入 | 继续提升 wrapper/agent 可用性，不自动改默认 agent |
| Amp CLI | 已部分接入 | plugin 路线 + `amp-exec` fallback，继续探索第二入口稳定性 |
| Copilot CLI | 已部分接入 | 继续补 payload 兼容性与 tool result/args 提取 |
| Windsurf | 已部分接入 | 继续补 hooks 事件覆盖与审批细节 |
| Cline / Cline CLI | 已部分接入 | 首版 hooks source 已落地，后续补 cancel/审批返回 |

### C. 还没做，但有明确 hooks / 可执行路线

| CLI | 当前状态 | 推荐路线 |
|-----|----------|----------|
| Qoder CLI | 未接入 | 官方文档对 CLI hooks 能力仍有分叉，当前继续不拆 source |

### D. 暂不接入为正式 CLI source 或保持 wrapper-first

| CLI | 当前状态 | 原因 |
|-----|----------|------|
| Pi Coding Agent | 已部分接入 | 已有 wrapper + json helper 原型，后续补 rpc / session-file 评估 |
| Crush | 已部分接入 | 已有 wrapper + 日志 watcher 原型，后续补结构化解析 |

## 逐项分析

### 1. Claude Code

**当前已完成**
- 完整 hooks 注入
- 审批响应
- `Setup` / `PostCompact`
- `Elicitation` / `ElicitationResult` 首版通知观测

**剩余缺口**
- `Elicitation` 仍没有真正的表单式交互 UI
- 仍有少量字段可继续提取

**建议**
- 继续保持“先观测、后交互”路线
- 不在近期引入新的 UI 状态模型

### 2. Codex CLI / Desktop

**当前已完成**
- CLI hooks 路线已打通
- Desktop transcript 已覆盖：
  - `function_call`
  - `function_call_output`
  - `custom_tool_call`
  - `custom_tool_call_output`
  - `reasoning`
  - `token_count`
  - `agent_message`
  - `item_completed`
  - `turn_aborted`
  - `compaction`
  - `context_compacted`

**剩余缺口**
- 仍有更多 `response_item` / `event_msg` 类型未系统梳理
- Desktop assistant 文本与 turn 级结束仍可继续精炼

**建议**
- 持续做 transcript parser 的低风险增量补齐
- 不新增 `codex_desktop_v2` 之类分支模型

### 3. Gemini CLI

**当前已完成**
- 原生 Gemini hooks 名称已正确写入
- `BeforeModel` / `BeforeToolSelection` / `AfterModel` 已接入
- 项目级 `.gemini/settings.json` 覆盖诊断已加入

**剩余缺口**
- 项目级配置只是诊断，不是受管路径
- 仍无 Gemini 独立审批模型

**建议**
- 继续保持 source-aware 映射
- 不把 Gemini 强行拉齐成 Claude 的 `PermissionRequest`

### 4. OpenCode

**当前已完成**
- JS plugin 路线稳定
- 已提取基础 tool result

**剩余缺口**
- 没有正式权限前置事件
- 只适合继续做只读增强

**建议**
- 继续沿 plugin 路线做工具结果丰富化
- 不把 OpenCode 设成审批主战场

### 5. Copilot CLI

**当前已完成**
- `preToolUse` 隐式审批
- 更宽松的 `toolArgs / toolResult / structured text` 提取

**剩余缺口**
- 还没有真实联调闭环证明所有 payload 变体都覆盖到了
- `modifiedArgs` 未实现

**建议**
- 继续补 payload 容错，不急着扩新协议
- 在真实样本足够前，不新增 Copilot-only schema

### 6. Droid / CodeBuddy / Qoder (IDE hooks)

**当前已完成**
- 都有稳定 installer
- 隐式审批 / hookSpecificOutput 路线已存在

**剩余缺口**
- 阻塞语义、错误展示、tool failure 细节仍可继续打磨

**建议**
- 继续在共享桥接层做增量
- 不再大改 source 结构

### 7. Windsurf

**当前已完成**
- source / installer / UI / watcher / repair 已接通
- deny 走 `stderr + exit 2`

**剩余缺口**
- 仍是首版事件覆盖
- 更完整的 hooks 矩阵还没做完

**建议**
- 继续补事件种类
- 保持 Windsurf-specific 语义，不复用 Claude/Copilot 响应模型

### 8. Kimi CLI

**当前已完成**
- `config.toml` hooks 管理
- 基础审批返回

**剩余缺口**
- 还未联调 ACP
- hooks 首版仍偏最小能力

**建议**
- 继续优先 hooks
- ACP 保持后续路线，不抢当前主线

### 9. Kiro CLI

**当前已完成**
- 自定义 agent 文件
- wrapper 已能避免覆盖显式 `--agent`

**剩余缺口**
- 依然不是“开箱即用”
- 还没有更清晰的使用入口文案

**建议**
- 继续保持“不自动改默认 agent”
- 通过 wrapper 和文档提升使用性

### 10. Amp CLI

**当前已完成**
- plugin 路线
- `amp-exec` fallback 路线
- plugin session id 更稳定
- `AMP_SETTINGS_FILE` 自定义 settings 路径诊断
- `amp-stream` 最小 `--stream-json` helper 原型
- `amp-stream` 的 best-effort `tool_use / tool_result` 提取

**剩余缺口**
- `stream-json` 仍未形成稳定 watcher 级第二入口
- plugin API 仍有线程/session 暴露限制

**建议**
- 继续做第二入口增强，但不强上高风险解析器
- 先把 wrapper、诊断和会话映射打磨到更稳定

### 11. Cline / Cline CLI

**当前已完成**
- `SessionSource.cline`
- `ClineHookSource`
- `~/Documents/Cline/Hooks` 首版脚本安装
- `~/.cline/data/globalState.json` 的 `hooks-enabled` 启用
- EventMapper 已新增 Cline 事件归一化与基础字段提取
- setup/settings/notch/watcher/repair 名单已接通

**建议路线**
- 保持当前“先监控、后阻塞”策略
- 下一步再评估 `cancel: true` / 审批返回
- 暂不拆 `cline` / `cline_cli`

### 12. Qoder CLI

**当前状态**
- 文档单列，但当前明确不拆 source

**当前决定**
- 继续视为“未接入”
- 不新增 `qoder_cli` 代码占位

**重新评估触发条件**
- 只有发现 CLI 和 IDE 存在稳定且不同的配置入口，才重启拆分

### 13. Pi / Crush

**当前状态**
- `Crush` 已有最小 wrapper 原型 + 日志 watcher 原型
- `Pi` 已有最小 wrapper 原型 + json helper 原型

**建议**
- `Crush` 继续从当前 `./.crush/logs/crush.log` watcher 原型往结构化解析推进
- 继续避免先碰 MCP/权限
- `Pi` 继续从当前 `--mode json` helper 往更稳定的 json/rpc 解析推进

## 自动推进顺序

后续自动执行顺序固定为：

1. `Amp CLI` 继续从 `amp-stream` helper 往结构化事件提取推进
2. `Pi` 继续从 `--mode json` helper 往更稳定的 JSON/RPC 解析推进
3. `Crush` 继续从日志 watcher 原型往结构化日志识别推进
4. `Cline CLI` 继续从首版监控推进到可选阻塞语义
5. `Copilot CLI` 真实 payload 兼容性继续增强
6. `Windsurf / Kimi / Kiro` 做使用性和事件覆盖打磨
7. 仅在官方 CLI hooks 文档不再冲突时，再重新评估 `Qoder CLI`

## 不自动做的事情

- 不自动拆 `Qoder CLI`
- 不自动把 `Kiro` 设成默认 agent
- 不自动把 `Amp permissions delegate` 拉进主线
- 不把 `Pi / Crush` 这种还缺稳定 hooks 入口的对象硬塞进 runtime
