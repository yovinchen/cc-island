# 统一支持矩阵

> 适用仓库: `claude-island`
> 更新时间: 2026-04-06
> 判定原则: 以当前代码、安装器、UI 接线、watcher / helper / plugin 实现为准，而不是只看 gap 文档标题。

## Hook 支持矩阵

说明:
- `✅` = 当前代码里有明确实现
- `⚠️` = 已有首版或共享实现，但仍有限制
- `—` = 当前没有这项能力

### App / IDE

| 对象 | 当前状态 | 集成入口 | 受管安装 | 事件接入 | 阻塞审批 | 备注 |
|------|----------|----------|:--------:|:--------:|:--------:|------|
| Warp | 宿主级支持 | 宿主识别 / 窗口聚焦 | — | — | — | 不是 hook source |
| Qoder（IDE hooks） | 正式接入 | `settings.json` hooks | ✅ | ✅ | ✅ | 通过 `permissionDecision` 走隐式审批 |
| Antigravity | 未接入 | — | — | — | — | 仅 docs / gap 分析 |
| Trae | 未接入 | unsupported marker | — | — | — | 代码里有 `SessionSource.trae`，但未进入 installer |
| Cursor | 正式接入 | `hooks.json` | ✅ | ✅ | ✅ | Cursor 专属 `{continue, permission}` 响应 |
| Windsurf | 部分支持 | `hooks.json` | ✅ | ✅ | ⚠️ | deny 已支持 `stderr + exit 2`，workspace/system 已有诊断但仍未完整托管 |
| CodeBuddy | 正式接入 | `settings.json` hooks | ✅ | ✅ | ✅ | 隐式审批已接通 |
| Kiro | 部分支持 | custom agent + wrapper | ✅ | ✅ | — | 需显式使用 `claude-island` agent；推荐走 wrapper |
| Lingma | 未接入 | — | — | — | — | 当前只有 rules / MCP 路线 |

### CLI / Desktop

| 对象 | 当前状态 | 集成入口 | 受管安装 | 事件接入 | 阻塞审批 | 备注 |
|------|----------|----------|:--------:|:--------:|:--------:|------|
| Claude Code | 正式接入 | `settings.json` hooks | ✅ | ✅ | ✅ | 当前最完整的 hook source |
| Cline / Cline CLI | 部分支持 | `~/Documents/Cline/Hooks` + `globalState.json` | ✅ | ✅ | ⚠️ | 已支持 native `cancel`，更大返回面仍未做 |
| Codex CLI | 正式接入 | `hooks.json` + `config.toml` + `notify` | ✅ | ✅ | ⚠️ | `PreToolUse/PostToolUse` 当前主要覆盖 Bash |
| Codex Desktop | 正式接入 | `session_index.jsonl` + transcript watcher | — | ✅ | — | 非 hook source，走 transcript 解析 |
| Gemini CLI | 正式接入 | `settings.json` hooks | ✅ | ✅ | — | 生命周期覆盖完整，未做独立审批模型 |
| Copilot CLI | 部分支持 | `config.json` hooks | ✅ | ✅ | ⚠️ | 隐式审批和 `modifiedArgs` 原型已接入，仍缺实机闭环 |
| OpenCode | 正式接入 | JS plugin | ✅ | ✅ | — | plugin 路线稳定，先做只读增强 |
| Droid | 正式接入 | Factory `settings.json` hooks | ✅ | ✅ | ✅ | Claude-compatible `hookSpecificOutput` |
| Kimi CLI | 部分支持 | `config.toml` hooks | ✅ | ✅ | ⚠️ | 首版事件覆盖已接近官方 13 事件 |
| Amp CLI | 部分支持 | global plugin + `amp-exec` + `amp-stream` | ✅ | ✅ | ⚠️ | 审批主要在 plugin 路线；stream-json 仍是 helper-first |
| Qoder CLI | 未接入 | — | — | — | — | 官方 CLI hooks 文档仍冲突，当前不拆 source |
| Pi Coding Agent | 部分支持 | `pi` / `pi-json` helpers | ✅ | ✅ | — | `--mode json` 解析已覆盖单工具与多工具串行样本 |
| Crush | 部分支持 | wrapper + project log watcher | ✅ | ✅ | — | 成功/失败样本已拿到，但仍无正式 tool-level log schema |

### VS 插件 / IDE 宿主

| 对象 | 当前状态 | 集成入口 | 受管安装 | 事件接入 | 阻塞审批 | 备注 |
|------|----------|----------|:--------:|:--------:|:--------:|------|
| JetBrains | 宿主级支持 | 宿主识别 / 窗口聚焦 | — | — | — | 当前不是 hooks source |
| Droid 插件 | 部分支持 | 复用 Droid hooks runtime | ⚠️ | ⚠️ | ⚠️ | 有 Droid source，但无插件专项宿主层 |
| Claudix | 未接入 | — | — | — | — | 仅 docs / gap 分析 |
| RooCode | 未接入 | — | — | — | — | 仅 docs / gap 分析 |
| Cline 插件 | 部分支持 | 复用 Cline hooks source | ✅ | ✅ | ⚠️ | 与 CLI 合并实现，无单独插件宿主层 |
| Copilot 插件 | 部分支持 | 复用 Copilot hooks config | ✅ | ✅ | ⚠️ | 当前没有 VS / JetBrains 插件专项适配 |

## 功能支持矩阵

说明:
- `设置/UI` = 是否已进入 HookSetup / Onboarding / Settings / Notch 等统一 UI 面
- `自动修复` = 是否已进入 `HookRepairManager`
- `配置监听` = 是否已进入 `HookFileWatcher` 或等价 watcher
- `宿主聚焦` = 是否有 bundle id / 终端宿主识别与窗口聚焦
- `解析增强` = 是否有 transcript / log / stream / helper 层的额外解析

### App / IDE

| 对象 | 设置/UI | 自动修复 | 配置监听 | 宿主聚焦 | 解析增强 | 备注 |
|------|:------:|:--------:|:--------:|:--------:|:--------:|------|
| Warp | — | — | — | ✅ | — | 仅宿主终端识别 |
| Qoder（IDE hooks） | ✅ | ✅ | ✅ | ✅ | — | 正式 hooks source |
| Antigravity | — | — | — | — | — | docs-only |
| Trae | — | — | — | — | — | unsupported |
| Cursor | ✅ | ✅ | ✅ | ✅ | — | 正式 hooks source |
| Windsurf | ✅ | ✅ | ✅ | ✅ | ⚠️ | 已补更多 Cascade / MCP 事件映射 |
| CodeBuddy | ✅ | ✅ | ✅ | ✅ | — | 正式 hooks source |
| Kiro | ✅ | ✅ | ✅ | — | ⚠️ | 依赖 helper / custom agent，可用性仍需文案补强 |
| Lingma | — | — | — | — | — | docs-only |

### CLI / Desktop

| 对象 | 设置/UI | 自动修复 | 配置监听 | 宿主聚焦 | 解析增强 | 备注 |
|------|:------:|:--------:|:--------:|:--------:|:--------:|------|
| Claude Code | ✅ | ✅ | ✅ | ✅ | ✅ | 含聊天记录 / StatusLine / 权限态 |
| Cline / Cline CLI | ✅ | ✅ | ✅ | — | ⚠️ | 事件归一化已做，返回面仍首版；自定义 `CLINE_DIR` 已有运行时诊断 |
| Codex CLI | ✅ | ✅ | ✅ | ✅ | ⚠️ | notify + CLI hooks，细节仍在打磨 |
| Codex Desktop | — | — | — | — | ✅ | transcript / rate-limit / reasoning 解析 |
| Gemini CLI | ✅ | ✅ | ✅ | ✅ | ✅ | Gemini 专属生命周期已接入为通知类事件 |
| Copilot CLI | ✅ | ✅ | ✅ | ✅ | ⚠️ | payload fallback / `modifiedArgs` 原型已接入 |
| OpenCode | ✅ | ✅ | ✅ | ✅ | ✅ | JS plugin + tool/result 提取 |
| Droid | ✅ | ✅ | ✅ | ✅ | — | 正式 hooks source |
| Kimi CLI | ✅ | ✅ | ✅ | — | ⚠️ | 事件面持续向官方 13 事件对齐 |
| Amp CLI | ✅ | ✅ | ✅ | — | ✅ | plugin + `amp-exec` + `amp-stream` |
| Qoder CLI | — | — | — | — | — | docs-only |
| Pi Coding Agent | ✅ | ✅ | ✅ | — | ✅ | helper 脚本现已进入 auto-repair / watcher |
| Crush | ✅ | ✅ | ✅ | — | ✅ | helper 脚本现已进入 auto-repair / watcher；日志仍是高层解析 |

### VS 插件 / IDE 宿主

| 对象 | 设置/UI | 自动修复 | 配置监听 | 宿主聚焦 | 解析增强 | 备注 |
|------|:------:|:--------:|:--------:|:--------:|:--------:|------|
| JetBrains | — | — | — | ✅ | — | 宿主识别 only |
| Droid 插件 | ⚠️ | ⚠️ | ⚠️ | ⚠️ | — | 主要复用 Droid runtime，而不是单独插件层 |
| Claudix | — | — | — | — | — | docs-only |
| RooCode | — | — | — | — | — | docs-only |
| Cline 插件 | ✅ | ✅ | ✅ | — | ⚠️ | 与 Cline CLI 共用 source |
| Copilot 插件 | ✅ | ✅ | ✅ | ⚠️ | ⚠️ | 主要复用 Copilot hooks config，插件宿主层仍未专项打磨 |

## 当前最重要的实现边界

- `Pi` 现在已经有真实的 helper-path 单工具和多工具串行样本，后续主要是继续收紧 `json` / `rpc` 解析，而不是再证明它能不能调用工具。
- `Crush` 现在已经有失败样本、成功样本和“明确要求使用工具”的成功样本；结论是项目日志仍然只暴露 HTTP/SSE 与遥测层信号，不应再假设存在稳定的本地 tool-level schema。
- `Windsurf / Kimi / Copilot / Cline / Amp` 依然属于“代码可用但功能仍在打磨”的第一梯队，后续增强应继续基于真实样本或官方文档，而不是扩大抽象层。
