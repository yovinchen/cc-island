# Claude Island Top Navigation And Providers Redesign

## Context

`ClaudeIsland` 目前的设置窗口仍然使用左侧 sidebar 作为一级导航，而 `Usage & Quota` 页虽然已经具备 provider 配置与额度展示能力，但整体信息密度、视觉层级、列表结构和操作路径都还没有对齐目标参考图。

这次改造的目标不是照搬 `CodexBar`，而是在保持 `ClaudeIsland` 现有 SwiftUI + 深色半透明风格的前提下，把设置窗口升级为：

1. 一级导航迁移到窗口正上方，形成明确的 top navigation。
2. `Usage & Quota` 页升级为真正的 `Providers` 工作台。
3. 每个 provider 的用量、状态、配置和刷新动作都在同一屏内完成。

## Current State

### Settings window

- 一级导航位于左侧 sidebar。
- 视觉结构偏工具面板，不像一个“主设置页”。
- 窗口尺寸偏小，难以承载 provider list + detail 的双栏布局。

### Usage & Quota page

- 已有 provider 列表、详情区、刷新、凭据保存、source/CLI 配置。
- 详情信息以多个 card 垂直堆叠，信息层级偏“设置项列表”，不像“provider 工作台”。
- 左侧 provider 列表信息不足，无法快速感知：
  - provider 是否启用
  - 最近刷新结果
  - 当前来源
  - 最近错误
- 右侧 usage 展示不够接近参考图的“标签 + 进度条 + reset 时间”结构。

## Design Goals

### Navigation goals

- 顶部导航居中，替代左侧 sidebar。
- 每个 tab 使用“图标 + 文本”的纵向按钮。
- 选中态需要明显，但不刺眼，保留现有深色语言。
- 当前 tab 标题在顶部中间单独显示，形成清晰页面语义。

### Providers page goals

- 左侧为 provider list，右侧为 detail workspace。
- 左侧 list 支持快速浏览全部 provider 当前状态。
- 右侧 detail 一屏完成：
  - 状态信息
  - usage bars
  - credits / notes / error
  - source 和 CLI 配置
  - credentials / workspace / region 等 provider-specific settings
  - refresh / open dashboard / open status

### Interaction goals

- 选择 provider 后，不跳页，只更新右侧 detail。
- 启用/禁用和刷新都应在当前上下文完成。
- source/CLI/credential 的操作都应具备“修改后立即可刷新验证”的闭环。

## Visual Direction

### Window shell

- 背景维持现有深色，但顶部导航区使用更浅一层的 panel 背景。
- 内容区分成两层：
  - top navigation shell
  - main content canvas

### Top navigation

- 顶部中央使用一组等距 tab。
- 每个 tab 为：
  - 上方 icon
  - 下方 label
- 选中态：
  - 边框淡亮
  - 背景轻微提亮
  - label 使用品牌蓝高亮

### Providers workspace

- 左栏 provider list 放入一个完整 rounded panel。
- 右栏 detail 使用更宽的单列工作区。
- detail 内部分成几个 section：
  - header
  - facts
  - usage
  - credits / notes / errors
  - settings
  - actions

## Information Architecture

### Top-level tabs

保留现有功能分区，但改变呈现方式：

- `General`
- `Hooks`
- `Sound`
- `Providers`
- `Diagnostics`

说明：

- 当前 `Usage & Quota` 在视觉和功能上都升级为 `Providers`。
- 国际化文案也同步调整成 provider-first 语义。

### Providers page structure

#### Left column

每个 provider row 显示：

- 品牌图标
- provider 名称
- 状态点
- 第一行摘要：当前 source 或状态
- 第二行摘要：最近刷新结果 / 最近更新时间 / 错误摘要
- 启用开关

#### Right column

右侧 detail 结构：

1. `Header`
   - 大图标
   - provider 名称
   - `source • updated`
   - 刷新按钮
   - enable toggle
2. `Facts`
   - State
   - Source
   - Version / detection
   - Updated
   - Status
   - Account
   - Organization
   - Plan
3. `Usage`
   - primary / secondary / tertiary usage rows
   - 每条用量统一结构：
     - label
     - progress bar
     - used text
     - reset text
4. `Credits / Notes / Errors`
   - credits summary
   - notes
   - latest error
5. `Settings`
   - source picker
   - CLI path override
   - manual credential
   - OpenCode workspace
   - z.ai region
6. `Actions`
   - Refresh
   - Open Dashboard
   - Open Status

## Component Plan

### New / updated shell components

- `SettingsTopNavigation`
  - 顶部 tab bar
- `SettingsTopTabButton`
  - 单个 tab 按钮
- `SettingsContentSurface`
  - 设置页主体承载层

### New / updated provider components

- `ProviderListPanel`
- `ProviderListRow`
- `ProviderDetailHeader`
- `ProviderFactsGrid`
- `ProviderUsageSection`
- `ProviderUsageRow`
- `ProviderSettingsSection`

说明：

- 不会一次性拆太多文件。
- 第一轮优先在现有 [SettingsView.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/UI/Views/SettingsView.swift) 和 [QuotaViews.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/UI/Views/QuotaViews.swift) 内完成结构迁移。
- 等样式稳定后，再决定是否拆分成更小的 view 文件。

## Implementation Phases

### Phase 1: Window shell and top navigation

目标：

- 设置窗口去掉左侧 sidebar。
- 顶部改成 centered top navigation。
- `Usage & Quota` 文案改成 `Providers`。
- 扩大设置窗口默认尺寸和最小尺寸，支撑新布局。

产出：

- 更新 [SettingsView.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/UI/Views/SettingsView.swift)
- 更新 [SettingsWindowController.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/UI/Window/SettingsWindowController.swift)
- 更新本地化文案

### Phase 2: Providers page layout rewrite

目标：

- 左侧 provider list 改成完整卡片列表。
- 右侧 detail 改成 header + facts + usage + settings 的工作台结构。
- usage bars 的样式对齐参考图。

产出：

- 重写 [QuotaViews.swift](/Users/yovinchen/project/claude-island/ClaudeIsland/UI/Views/QuotaViews.swift) 主体布局
- 保留现有 quota store / provider registry / refresh pipeline

### Phase 3: Provider-specific polish

目标：

- 优化不同 provider 的摘要文案
- 强化错误态、未配置态、最近刷新态
- 让 `OpenCode workspace`、`z.ai region`、`CLI override` 更自然地归位到 settings section

产出：

- provider row 摘要逻辑优化
- detail section copy 和 spacing 打磨

## Behavioral Rules

### Provider row summary priority

provider list 的副标题优先级：

1. 最近错误
2. 已配置但最近抓取失败
3. source + 最近更新时间
4. 未配置提示

### Usage row rules

- progress bar 始终展示 used ratio。
- 左下角文本显示 `x% used` 或 credits summary。
- 右下角文本显示 reset 时间。
- 没有 reset 时间时显示 `No reset detected` 或隐藏该行的 reset 文本。

### Detail settings rules

- source picker 紧贴 settings section 顶部。
- CLI path override 仅在 provider 声明 `cliBinaryName` 时显示。
- manual credential 仅在 `supportsManualSecret` 为 `true` 时显示。
- OpenCode workspace 和 z.ai region 继续保持 provider-specific。

## Non-Goals

- 这轮不引入浏览器 cookie 自动导入。
- 这轮不做 provider 拖拽排序持久化。
- 这轮不重写 Notch quota panel。
- 这轮不新增新的 provider 接入。

## Verification Plan

- 构建验证：
  - `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Debug CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`
- 测试验证：
  - `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Debug CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -enableCodeCoverage NO test`
- 手动检查：
  - 设置窗口顶部导航是否居中
  - Providers 页左右栏比例是否合理
  - provider 选中切换是否平滑
  - refresh / enable / save credential 是否仍然工作

## Execution Order

按以下顺序实施：

1. 先改设置窗口外壳和顶部导航。
2. 再改 Providers 页的 list/detail 结构。
3. 最后补 provider-specific 样式和 copy 打磨。
