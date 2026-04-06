# Crush — 差距分析

> 官方仓库: https://github.com/charmbracelet/crush
> 分析日期: 2026-04-06

## 当前仓库状态

| 项目 | 状态 | 说明 |
|------|------|------|
| `SessionSource` / `HookSource` | ❌ | 当前无 Crush 接入 |
| README / docs | ❌ | 仓库暂无 Crush 兼容性记录 |

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

Crush **当前不支持接入**。公开资料显示它有 MCP、权限和命令扩展，但没有现成的本地 hooks 配置面可复用。

## 基于本地代码的实现可行性

**可行性评级**: 低（hooks） / 中（CLI 包装/MCP）

**可直接复用**
- 若改走 CLI 包装或 session watcher，可以复用统一 `HookEvent` 消费端；`HookInstaller` 不适合直接接 Crush。

**可实施方案**
1. 优先调查 Crush 是否有可读的 session/state 文件。
2. 如果没有，再考虑命令包装器，把 MCP/permission 事件转成 Claude Island 统一协议。

**当前推荐路线**
1. 在 `Pi` 和 `Crush` 之间，优先做 `Crush` 的最小 runtime 原型。
2. 第一阶段只做 CLI 包装器，先产出 `SessionStart / UserPromptSubmit / Stop`。
3. 在确认稳定 session/state 文件之前，不碰 MCP / 权限集成。

**主要阻塞**
- 当前没有官方本地 hooks 配置面，意味着任何接入都不是“低成本新增 source”。
