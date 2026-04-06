# CodexBar Backend Fetch Reference

## Goal

这份文档专门回答两个问题：

1. `CodexBar` 后端是如何拿到 provider 数据的？
2. `CodexBar` 是如何发现 CLI / script / cookie / session 来源的？

目标是把它拆成 `Claude Island` 可以直接参考或迁移的后端模块，而不是只看 UI 表层。

## 1. Overall Data Flow In CodexBar

`CodexBar` 的 provider 数据链路可以概括为：

1. `SettingsStore`
   - 保存 provider 级 source 模式、cookie source、manual header、token account、debug 开关
2. `ProviderImplementation`
   - 每个 provider 声明自己的设置项、source label、runtime、login flow
3. `ProviderSettingsSnapshot`
   - 把设置收束成 fetch 时需要的只读快照
4. `ProviderDescriptor / UsageFetcher / StatusProbe`
   - 真正执行 API / CLI / Web / local file fetch
5. `ProviderRuntime`
   - 处理 keepalive、失败恢复、强制刷新等运行时行为
6. `UsageStore`
   - 汇总 provider snapshot，驱动 UI

## 2. Key Backend Modules

### Settings and source control

关键文件：

- [SettingsStore.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/SettingsStore.swift)
- [SettingsStore+Config.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/SettingsStore+Config.swift)
- `Providers/*/*SettingsStore.swift`

职责：

- provider 级 source 模式持久化
- cookie source 持久化
- manual header / token 持久化
- token account 选择
- provider 显示/排序偏好

可直接参考给 `Claude Island` 的点：

- 每个 provider 的 source 不是直接写死在 fetcher 里，而是先经由 settings snapshot 决定
- `cookieSource` 和 `usageDataSource` 是分开的
- source label 会反馈到 UI，而不是只在内部决定

### Provider implementation layer

关键文件：

- [ProviderImplementation.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Shared/ProviderImplementation.swift)
- [ProviderImplementationRegistry.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Shared/ProviderImplementationRegistry.swift)

职责：

- provider 的设置 UI 定义
- source mode 转换
- runtime 挂载
- login flow 挂载

对 `Claude Island` 的参考意义：

- 现在 `Claude Island` 已有 provider workspace UI，但后端层还缺“实现层”和“fetch 层”之间的中介
- 如果后面继续扩 provider，最好逐步演进到：
  - `descriptor`
  - `settings snapshot`
  - `fetcher / probe`
  - `runtime`

### Fetch plan and runtime

关键文件：

- [ProviderFetchPlan.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/ProviderFetchPlan.swift)
- `Providers/*/*ProviderRuntime.swift`
- [UsageStore+Refresh.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/UsageStore+Refresh.swift)

职责：

- 根据 provider 和设置决定 runtime
- 启动/停止 runtime
- provider 失败后触发恢复或 keepalive
- 统一刷新路径

`Claude Island` 当前缺口：

- 现在只有 `QuotaStore.refresh(providerID:)`
- 没有 provider runtime 行为层
- 没有 failure-recovery / keepalive lane

## 3. How CodexBar Finds CLI And Script Paths

### Generic CLI config

关键文件：

- [ProviderCLIConfig.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/ProviderCLIConfig.swift)
- [ProviderVersionDetector.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/ProviderVersionDetector.swift)
- [PathEnvironment.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/PathEnvironment.swift)

逻辑：

1. provider descriptor 声明 CLI config
2. 通过 path/environment resolver 找到 binary
3. 再用 version detector 执行 `--version` / `version` / provider 自定义方式
4. 将检测结果带回 UI

`Claude Island` 现在已经部分补上：

- [QuotaRuntimeSupport.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/Quota/Support/QuotaRuntimeSupport.swift)
- provider 级 CLI path override
- CLI version detection

仍未补的点：

- 通用 provider CLI descriptor
- per-provider 自定义 version parse
- 更完整的 PATH / alias / shell 环境解析

### Provider-specific resolver examples

关键文件：

- `Codex`:
  - [CodexSettingsStore.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Codex/CodexSettingsStore.swift)
  - `CodexActiveSourceResolver`
- `Claude`:
  - `ClaudeCLIResolver`
  - [ClaudeSettingsStore.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Claude/ClaudeSettingsStore.swift)
- `Gemini`:
  - `GeminiLoginRunner`
  - `GeminiStatusProbe`

这些模块说明 `CodexBar` 不是单纯 `which binary`，而是会把 provider-specific 路径/登录状态/认证方式一起考虑。

## 4. How CodexBar Finds Browser Cookies And Sessions

### Browser detection and cookie read

关键文件：

- [Package.swift](/Users/yovinchen/project/CodexBar/Package.swift)
- `SweetCookieKit`
- `BrowserDetection`
- `BrowserCookieClient`
- `BrowserCookieQuery`
- `BrowserCookieImportOrder`
- `BrowserCookieAccessGate`

逻辑：

1. 先判断本机浏览器可用性
2. 按 import order 逐个浏览器尝试
3. 对指定域名查询 cookie
4. 过滤 provider 需要的 session cookie 名
5. 组装成 `Cookie:` header
6. 用真实 API 验证是否有效
7. 通过 `CookieHeaderCache` 保存来源与缓存时间

`Claude Island` 当前完全缺失这一层。

这也是为什么现在大量 web provider “理论上已实现，但实际上不可用”：

- 只有 manual cookie header
- 没有 auto import
- 没有 cached cookie metadata
- 没有 imported-cookie validation

## 5. Provider Examples Worth Copying

### Claude

关键文件：

- [ClaudeProviderImplementation.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Claude/ClaudeProviderImplementation.swift)
- [ClaudeSettingsStore.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Claude/ClaudeSettingsStore.swift)
- [ClaudeUsageFetcher.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeUsageFetcher.swift)
- [ClaudeStatusProbe.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeStatusProbe.swift)
- [ClaudeCLISession.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Claude/ClaudeCLISession.swift)

后端价值：

- OAuth source
- CLI PTY source
- Web extras source
- source planner
- delegated refresh

### Cursor

关键文件：

- [CursorProviderImplementation.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Cursor/CursorProviderImplementation.swift)
- [CursorSettingsStore.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Cursor/CursorSettingsStore.swift)
- [CursorStatusProbe.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift)
- [CursorLoginRunner.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/CursorLoginRunner.swift)

后端价值：

- browser cookie import
- cookie-domain fallback
- session validation
- login flow

### Amp

关键文件：

- [AmpProviderImplementation.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Amp/AmpProviderImplementation.swift)
- [AmpUsageFetcher.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Amp/AmpUsageFetcher.swift)

后端价值：

- manual + auto cookie path
- redirect diagnostics
- raw probe
- HTML parser / session validation

### Augment

关键文件：

- [AugmentProviderImplementation.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBar/Providers/Augment/AugmentProviderImplementation.swift)
- [AugmentStatusProbe.swift](/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Augment/AugmentStatusProbe.swift)

后端价值：

- session cookie import
- credits + subscription merge
- runtime keepalive
- debug dump

## 6. What Can Be Copied Directly Right Now

### Low-risk direct references

适合直接按思路迁移：

- `ClaudeStatusProbe` parsing logic
- `ClaudeCLISession` PTY capture logic
- generic version detection strategy
- provider source priority / fallback strategy
- provider debug probe idea

### Medium-risk ports

适合拆分后迁移：

- `CursorStatusProbe`
- `AmpUsageFetcher`
- `AugmentStatusProbe`

原因：

- 这些逻辑与 browser cookie 基础设施耦合较重
- 直接复制需要同时引入 `SweetCookieKit` 或重建等价浏览器 cookie 层

### High-risk direct copy

不建议不加拆解直接搬：

- 整套 `SettingsStore`
- 整套 `ProviderImplementation` runtime 层
- 整套 browser cookie 访问基础设施

原因：

- 与 `CodexBar` 的配置系统耦合太深
- `Claude Island` 当前没有相同的 state/store 结构

## 7. Recommended Migration Order For Claude Island

### Step 1

先补 CLI live-data 真正可用：

- `Claude` CLI PTY `/usage`
- `Claude` `/status` identity
- richer version detection

### Step 2

补 provider backend observability：

- raw debug probe
- source label clarity
- fetch failure diagnostics

### Step 3

再补 browser cookie infrastructure：

- browser detection
- cookie import order
- cookie normalization / cache
- imported-cookie validation

### Step 4

最后再补 login runners / runtime keepalive。

## 8. Current Migration Status In Claude Island

截至本轮：

- 已具备 provider workspace UI
- 已具备 provider source / CLI path config
- 已具备多窗口 usage 渲染
- 已补 `Claude` 的 CLI live-data probe 雏形
- 仍未补 browser cookie import runtime

也就是说：

- `Claude` 的 backend parity 正在变得可用
- `Cursor / Amp / Augment / OpenCode` 仍然主要停留在 manual-cookie 模式
