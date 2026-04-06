# Amp CLI — 差距分析

> 官方手册: https://ampcode.com/manual
> Plugin API: https://ampcode.com/manual/plugin-api
> Workspace Settings: https://ampcode.com/news/cli-workspace-settings
> 分析日期: 2026-04-06

## 当前仓库状态

| 项目 | 状态 | 说明 |
|------|------|------|
| `SessionSource` / `HookSource` | ⚠️ | 当前已新增 `amp_cli` source，并生成全局 plugin 文件 |
| 安装检测 | ✅ | 已检测 `~/.config/amp` 与常见 `amp` 可执行路径 |
| Hook / Plugin 适配 | ⚠️ | 已支持 plugin API 首版桥接；`stream-json` watcher 仍未实现 |

## 官方可用扩展面

| 能力 | 官方状态 | 说明 |
|------|------|------|
| Claude/Cursor 风格 hooks 配置 | 未见公开文档 | 官方没有独立 `hooks.json` / `hooks` 字段规范 |
| TypeScript Plugin API | ✅ | 插件可监听 `tool.call`、`tool.result`、`agent.start`、`agent.end` 等事件 |
| 插件目录 | ✅ | 项目级 `.amp/plugins/`，全局 `~/.config/amp/plugins/` |
| 启用方式 | ✅ | 需显式使用 `PLUGINS=all amp`，默认关闭 |
| 权限代理 | ✅ | `amp.permissions` 支持 delegate 到外部程序，通过 exit code 控制 allow / ask / deny |
| Workspace settings | ✅ | 支持 `.amp/settings.json` 与 `~/.config/amp/settings.json` 合并 |
| Streaming JSON | ✅ | `amp --execute --stream-json` 可用于程序化会话监控 |

## 与 Claude Island 的主要差距

1. Amp 公开的是 `plugin API`，不是当前 `HookInstaller` 复用的声明式 hooks 配置。
2. Plugin API 目前仍是实验性能力，官方明确提示可能有 breaking changes。
3. 插件仅在 Amp CLI 中可用，不适用于 Amp editor extension。
4. 插件默认关闭，用户需要显式设置 `PLUGINS=all`，这比当前仓库的“安装即生效”模型更复杂。

## 可替代实现方式

1. **Plugin 路线**: 在 `.amp/plugins/` 生成 Claude Island 插件，监听 `tool.call` / `tool.result` / `agent.start` / `agent.end`，再把事件转发到现有 Unix socket。
2. **Permissions delegate 路线**: 用 `amp.permissions` 的 `delegate` 机制，把 Bash 等工具审批交给外部 helper，再由 Claude Island 接管 UI。
3. **Streaming JSON 路线**: 用 `amp --execute --stream-json` 做只读会话追踪，适合先实现监控、后实现审批。

## 接入建议

1. 第一阶段优先做只读监控，基于 Plugin API 或 `--stream-json` 建立 `amp_cli` source。
2. 第二阶段再评估是否通过 permissions delegate 对接 Notch 审批。
3. 若决定实现插件方式，需要新增插件文件生成、`PLUGINS=all` 检测与启用提示。

## 结论

Amp CLI **当前处于部分支持状态**。本仓库已能安装全局 plugin，并把 `session.start / agent.start / tool.call / tool.result / agent.end` 桥接到 Claude Island；但仍依赖用户以 `PLUGINS=all amp` 方式运行。

## 基于本地代码的实现可行性

**可行性评级**: 中高（plugin/stream） / 中（审批代理）

**可直接复用**
- `HookSocketServer`、`SessionStore`、UI 端都可以直接复用，只要 Amp 能输出统一 JSON 事件。
- 如果走 `--stream-json`，甚至不一定要先做插件安装器。

**最小实现方案**
1. 已实现全局 `.config/amp/plugins/claude-island.ts` 生成。
2. 当前 plugin 已接入基础事件与危险工具审批。
3. 当前会同步安装 `~/.claude-island/bin/claude-island-amp` wrapper，用于自动附带 `PLUGINS=all`。
4. 当前还会同步安装 `~/.claude-island/bin/claude-island-amp-exec`，把一次 `amp --execute` 包成最小会话事件。
5. 当前运行时已能在事件环境里检测 `AMP_SETTINGS_FILE`，并提示“自定义 settings 可能绕过默认 plugin 路径”。
6. 当前还会同步安装 `~/.claude-island/bin/claude-island-amp-stream`，作为 `amp --execute --stream-json` 的最小 helper 原型。
7. 当前 `amp-stream` 已能 best-effort 提炼 `tool_use` / `tool_result`，回放为 `PreToolUse` / `PostToolUse`。
8. 下一步仍建议补更深的 `--stream-json` watcher/事件细化，用于无 plugin 模式或更稳定的会话分组。

**主要阻塞**
- 当前主要阻塞是 Amp plugin API 对线程/session 标识暴露有限，因此首版会话分组更偏“每个 CLI 进程一个 session”。
