# Claude Island vs CodexBar Live-Data Gap Analysis

## Purpose

这份文档用于分析 `Claude Island` 当前 provider live-data 能力与 `CodexBar` 的差距，重点关注：

- 活跃数据抓取链路
- CLI / OAuth / Web source planner
- browser cookie 自动导入
- provider runtime probe / debug / login flow
- 可直接迁移的能力
- 当前受限点

目标不是直接复制 `CodexBar`，而是给 `Claude Island` 一个现实可执行的补齐路线。

## Current Claude Island Baseline

当前仓库已经具备的能力：

- 账号级 quota store 与 provider registry
  - [QuotaStore.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Core/QuotaStore.swift)
  - [QuotaProviders.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Providers/QuotaProviders.swift)
- Wave 1 / Wave 2 provider fetchers
  - [OAuthCLIQuotaProviders.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Providers/OAuthCLIQuotaProviders.swift)
  - [APIQuotaProviders.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Providers/APIQuotaProviders.swift)
  - [Wave2QuotaProviders.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Providers/Wave2QuotaProviders.swift)
  - [Wave2WebQuotaProviders.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Providers/Wave2WebQuotaProviders.swift)
- Settings 内 provider 工作台
  - [SettingsView.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/UI/Views/SettingsView.swift)
  - [QuotaViews.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/UI/Views/QuotaViews.swift)
- provider source / CLI path 偏好
  - [QuotaModels.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Domain/QuotaModels.swift)
  - [QuotaPreferences.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Support/QuotaPreferences.swift)
  - [QuotaRuntimeSupport.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Support/QuotaRuntimeSupport.swift)

已支持但仍偏基础的点：

- `Codex` 有 `OAuth / CLI / Auto`
- `Codex / Gemini / Kiro` 有 CLI 路径覆盖
- `Cursor / OpenCode / Amp / Augment` 支持手动 cookie header
- UI 已能显示多窗口 usage

## What CodexBar Has Beyond Claude Island

### 1. Source planner and runtime routing

`CodexBar` 的 provider 获取链路不是“直接 fetch”，而是先做 source planning，再执行 runtime path。

关键参考：

- [UsageFetcher.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/UsageFetcher.swift)
- [ClaudeUsageFetcher.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift)
- [ClaudeUsageDataSource.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeUsageDataSource.swift)
- [ProviderCLIConfig.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/ProviderCLIConfig.swift)

CodexBar 具备：

- `auto` source planner
- source failure fallback
- provider-specific runtime selection
- version detector integration
- richer debug context

Claude Island 当前缺失：

- 没有统一 source planner
- 大多数 provider 仍是“单一路径直连 fetch”
- 没有 source-failure 重试链

### 2. Claude live-data stack

CodexBar 的 Claude provider 是一整套能力，不只是 OAuth API：

- OAuth usage API
- Claude CLI PTY `/usage`
- Claude CLI `/status`
- delegated refresh / auth touch path
- Web API extras
- cookie source 管理

关键参考：

- [ClaudeUsageFetcher.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift)
- [ClaudeStatusProbe.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift)
- [ClaudeCLISession.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeCLISession.swift)
- [ClaudeProviderImplementation.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Claude/ClaudeProviderImplementation.swift)
- [ClaudeSettingsStore.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Claude/ClaudeSettingsStore.swift)

Claude Island 当前缺失：

- `Claude CLI` usage probe
- `/status` identity probe
- Claude `web` source
- Claude cookie source / source planner

### 3. Cursor live-data stack

CodexBar 的 Cursor 能力不仅是手动 cookie：

- browser cookie 自动导入
- multi-browser source order
- domain-cookie fallback
- Cursor login runner
- API validation with imported cookies

关键参考：

- [CursorStatusProbe.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift)
- [CursorLoginRunner.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/CursorLoginRunner.swift)
- [UsageStore.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/UsageStore.swift)

Claude Island 当前缺失：

- browser cookie import
- cookie-source selection (`auto / manual / off`)
- login flow
- API validation before persisting imported cookies

### 4. Amp live-data stack

CodexBar 的 Amp 抓取链完整覆盖：

- browser cookie import
- manual cookie override
- redirect diagnostics
- raw debug probe
- parser + fetch separation

关键参考：

- [AmpUsageFetcher.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Amp/AmpUsageFetcher.swift)
- [AmpProviderImplementation.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Amp/AmpProviderImplementation.swift)

Claude Island 当前缺失：

- browser cookie import
- debug raw probe
- redirect diagnostics
- provider settings 中的 cookie-source 模式

### 5. Augment live-data stack

CodexBar 的 Augment provider 具备：

- browser cookie 自动导入
- richer cookie-name detection
- credits + subscription join
- debug dump capability

关键参考：

- [AugmentStatusProbe.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Augment/AugmentStatusProbe.swift)
- [AugmentProviderImplementation.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Augment/AugmentProviderImplementation.swift)

Claude Island 当前缺失：

- browser cookie import
- richer auth/session diagnostics
- debug dump entry

### 6. Cookie infrastructure

CodexBar 对 web providers 的基础设施明显更完整：

- browser detection
- browser cookie query
- cookie import order
- cookie access gate
- cookie cache
- cookie header normalization
- source-aware cached cookie metadata

关键参考：

- [OpenAIDashboardBrowserCookieImporter.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardBrowserCookieImporter.swift)
- `SweetCookieKit` 相关调用分布在 `CodexBarCore/Providers/*`
- [SettingsStore+Config.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/SettingsStore+Config.swift)

Claude Island 当前状态：

- 只有手动 secret 存储
- 没有 browser cookie client
- 没有 cookie-source state machine
- 没有 cookie cache / source attribution

## Why Most Live-Data Scripts Still Feel Unusable

根因不是单个 parser，而是能力链不完整：

1. 没有 browser cookie import，导致 web providers 基本只能靠手动 header。
2. 没有 source planner，导致 provider 无法在多个来源之间平滑回退。
3. 没有 dedicated debug/probe surface，出错时只能看到最终错误文案。
4. `Claude` 缺少 CLI PTY 路径，损失了最关键的一条 live-data fallback。
5. provider detail 里虽然有 UI，但背后还没有 CodexBar 那种“自动发现 + 自动验证 + 自动缓存”的 runtime。

## Constraints In Claude Island

### 1. No browser-cookie stack today

`Claude Island` 当前仓库没有：

- `SweetCookieKit`
- browser cookie reader
- browser detection abstraction

这意味着：

- 不能直接把 `CodexBar` 的 browser-cookie import 原样搬过来
- 如果要补这块，要么：
  - 引入新依赖
  - 要么自行实现 macOS browser cookie 读取层

### 2. Keep the current app architecture

按当前要求，仍应保持：

- 现有 SwiftUI settings workspace
- 现有 quota store / registry
- 不直接迁入 CodexBar 的整套 store/runtime 框架

## Recommended Porting Order

### Wave A: High-value, low-risk parity

建议优先补这些：

1. CLI version detection
2. richer provider detection text
3. more usage windows
4. `Claude` CLI source support

说明：

- 这些能力不依赖 browser cookie stack。
- 能明显提升 live-data 可用性和调试效率。

### Wave B: Web provider usability

建议第二波补：

1. cookie-source mode (`auto / manual / off`)
2. cookie normalization + cache metadata
3. raw debug probe entry for `Cursor / Amp / Augment / OpenCode`

说明：

- 先不做 browser 自动导入，也可以先把 provider runtime 的调试面搭起来。

### Wave C: Full browser-cookie parity

最终再补：

1. browser detection
2. browser cookie import
3. imported-cookie validation
4. cached-cookie source attribution
5. login flows where needed

## Immediate Follow-up Work For Claude Island

基于当前项目，最值得下一步直接实现的是：

1. `Claude` CLI PTY `/usage` probe
   - 参考：
     - [ClaudeStatusProbe.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift)
     - [ClaudeCLISession.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeCLISession.swift)
2. provider version / runtime detection统一化
   - 参考：
     - [ProviderCLIConfig.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/ProviderCLIConfig.swift)
3. web provider debug dumps
   - 参考：
     - [UsageStore.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/UsageStore.swift)
     - [AmpUsageFetcher.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Amp/AmpUsageFetcher.swift)
     - [AugmentStatusProbe.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Augment/AugmentStatusProbe.swift)

## Status After This Round

本轮 `Claude Island` 已补到：

- 顶部导航 + Providers workspace
- provider source / CLI path config
- richer multi-window usage UI
- 部分 CLI version detection

但距离 `CodexBar` live-data parity 还有明显缺口，尤其是：

- `Claude CLI`
- browser cookie auto import
- provider runtime debug/probe surface
- login flows
