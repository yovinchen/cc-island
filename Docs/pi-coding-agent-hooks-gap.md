# Pi Coding Agent — 差距分析

> 官方仓库: https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent
> 作者示例扩展: https://gist.github.com/badlogic/8d47e8dbfa9876427670cf207cb330c1
> 分析日期: 2026-04-06

## 当前仓库状态

| 项目 | 状态 | 说明 |
|------|------|------|
| `SessionSource` / helper | ⚠️ | 已新增 `SessionSource.pi` 与 `claude-island-pi` helper |
| README / docs | ⚠️ | 当前已开始记录为部分支持 |

## 官方可用扩展面

| 能力 | 状态 | 说明 |
|------|------|------|
| 独立 hooks 文档 | 未发现 | 当前公开资料更偏向 agent toolkit / 扩展 API |
| 扩展命令 API | ✅ | 作者公开示例展示了 `registerCommand` 扩展方式 |
| 内建工具 / 会话系统 | ✅ | 公开资料强调内建 coding tools 与 session persistence |

## 可替代实现方式

1. 若要接 Pi，更像是接其 extension API 或 session store，而不是接 hooks。
2. 也可以考虑把 Pi 当成“底层 agent runtime”，通过命令包装器注入 stdout bridge。

## 结论

Pi Coding Agent **当前已部分支持**。Claude Island 现在已提供最小 CLI 包装器，可观测 Pi 会话的开始与结束；但仍没有正式 hooks / tool-level / session-file 解析。

## 基于本地代码的实现可行性

**可行性评级**: 低（直连） / 中高（命令包装）

**可直接复用**
- 如果未来选择“包裹 CLI / agent runtime 输出”的方案，可复用 `EventMapper` 下游与统一 session/UI。

**本地代码复核结果**
- 当前会同步安装 `~/.claude-island/bin/claude-island-pi`。
- 当前会同步安装 `~/.claude-island/bin/claude-island-pi-json`。
- 这个 helper 会桥接：
  - `SessionStart`
  - 可选的 `UserPromptSubmit`（仅在传参启动时）
  - `Stop`
- 当前运行时也会检测 `PI_CODING_AGENT_DIR`，并提示 Claude Island 现在仍是 wrapper-based 集成。
- `claude-island-pi-json` 会运行 `pi --mode json -p`，保留原始 JSON 输出并提炼最终 assistant 文本。
- 当前 `pi-json` 已开始 best-effort 提炼 `tool_use / tool_result` 等常见结构，用于回放基础工具事件。
- 基于本机真实样本，当前 parser 也已经开始兼容 `message_update / message_end / turn_end / agent_end` 这类真实 JSON 流形状，并会同时扫描 `stdout + stderr` 里的 JSON 行。

**可实施方案**
1. 当前已完成第一阶段 wrapper 原型。
2. 当前已完成第一阶段 `--mode json` helper 原型。
3. 下一步再评估 `--mode rpc` 或 session 文件解析是否值得继续深入。
4. 在确认稳定 JSON 或 session 文件格式之前，不碰审批。

**主要阻塞**
- 当前没有官方 hooks 规范，所有实现都会偏旁路，维护成本高。
