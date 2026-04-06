# Crush — 差距分析

> 官方仓库: https://github.com/charmbracelet/crush
> 分析日期: 2026-04-06

## 当前仓库状态

| 项目 | 状态 | 说明 |
|------|------|------|
| `SessionSource` / helper | ⚠️ | 已新增 `SessionSource.crush` 与 `claude-island-crush` helper |
| README / docs | ⚠️ | 当前已开始记录为部分支持 |

## 官方可用扩展面

| 能力 | 状态 | 说明 |
|------|------|------|
| 独立 hooks 文档 | 未发现 | 官方仓库 README 未暴露 lifecycle hooks |
| MCP | ✅ | README 明确支持 `stdio` / `http` / `sse` 三类 MCP transport |
| 权限控制 | ✅ | README 有权限与 tool access 说明 |
| 指令 / slash commands | ✅ | README 展示 commands、agents、skills 等可扩展面 |

## 可替代实现方式

1. 通过 MCP / slash command / skills 接近规则注入，而不是 hooks。
2. 若后续要做 Claude Island 兼容，更可能需要读取 Crush session/state 文件或包裹其 CLI。

## 结论

Crush **当前已部分支持**。Claude Island 现在已提供最小 CLI 包装器，可观测 Crush 会话的开始与结束；但仍没有正式 hooks / MCP / 权限集成。

## 基于本地代码的实现可行性

**可行性评级**: 低（hooks） / 中高（CLI 包装） / 中（MCP）

**可直接复用**
- 若改走 CLI 包装或 session watcher，可以复用统一 `HookEvent` 消费端；`HookInstaller` 不适合直接接 Crush。

**本地代码复核结果**
- 当前会同步安装 `~/.claude-island/bin/claude-island-crush`。
- 这个 helper 会桥接：
  - `SessionStart`
  - 可选的 `UserPromptSubmit`（仅在传参启动时）
  - `Stop`
- 当前没有把 Crush 纳入 hooks setup 列表，因为它还不是正式 hook source。
- 运行时现在也会检测项目内 `./.crush/logs/crush.log`，并把它作为后续 watcher 的首选线索提示出来。
- 当前已新增最小 `CrushLogWatcher`，会优先尝试把 JSON 日志行识别成 `PreToolUse` / `PostToolUse` / `PostToolUseFailure`，识别不了时再回退成 `Notification`。
- 基于本机真实日志样本，当前 watcher 也会优先锁定 non-interactive run 的 `session_id`，并压缩 `buffer(...)` / shutdown / skill bootstrap 这类高噪音日志，只保留更有用的 prompt / request failure 观察信号。
- 对于真实样本里重复出现的 title-generation 降级错误，当前 watcher 也会当作噪音压掉，避免和更关键的 `HTTP request failed` 重复刷屏。
- 当前还已经拿到一份 provider 正常成功返回的真实日志样本：它证明 `HTTP Response 200 OK` 与 PostHog/shutdown 收尾日志会大量刷屏，因此这类成功/遥测噪音现在也会被优先压掉。
- 基于 provider 正常成功路径的真实日志样本，当前 watcher 也已经开始从 `HTTP Response` 的 SSE body 里提炼第一段模型文本，避免成功场景下只剩抽象的 `prompt responded`。
- 对于同一成功样本里较短、明显属于标题生成阶段的 `HTTP Response`，当前 watcher 也会优先压掉，尽量只保留主回答对应的成功信号。
- 现在还已经拿到一份“明确要求使用 bash 工具”的成功样本；结论是日志里依然只暴露 HTTP/SSE 与埋点层信号，没有稳定的本地 tool-level schema，因此当前路线仍应停留在高层 watcher，而不是伪造工具级协议。

**可实施方案**
1. 优先调查 Crush 是否有可读的 session/state 文件。
2. 如果没有，再继续沿命令包装器演进，把更多上下文事件转成 Claude Island 统一协议。

**当前推荐路线**
1. 当前已完成第一阶段 CLI 包装器原型。
2. 官方已明确项目日志位于 `./.crush/logs/crush.log`，下一步优先沿这条日志面评估 watcher，而不是先碰 MCP / 权限。
3. 在确认稳定 session/state 文件之前，不碰 MCP / 权限集成。

**主要阻塞**
- 当前没有官方本地 hooks 配置面，意味着任何接入都不是“低成本新增 source”。
