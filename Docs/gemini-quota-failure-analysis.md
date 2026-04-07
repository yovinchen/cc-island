# Gemini Quota Failure Analysis

## What Failed

本机 `Gemini` 已登录，且这两个文件存在：

- `~/.gemini/settings.json`
- `~/.gemini/oauth_creds.json`

`settings.json` 里的认证模式是：

- `oauth-personal`

所以问题不是“没有登录”，而是刷新链路本身不够稳。

## Live Verification

使用当前本机 OAuth token 直接请求后，两个接口都能返回正常数据：

### `loadCodeAssist`

- `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist`
- 返回：
  - `currentTier.id = "standard-tier"`
  - `cloudaicompanionProject = "mineral-lodge-bx31f"`
  - `gcpManaged = false`

### `retrieveUserQuota`

- `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`
- 返回 buckets：
  - `gemini-2.5-pro`
  - `gemini-2.5-flash`
  - `gemini-2.5-flash-lite`

这说明：

- Gemini 私有 quota API 还可用
- 当前账号有完整的 `Pro / Flash / Flash Lite` 窗口

## Root Cause

`Claude Island` 原来的 `Gemini` 失败点主要有两个：

### 1. Refresh 逻辑过早触发

当前 `oauth_creds.json` 中的 `expiry_date` 已经过期，但现有 `access_token` 仍然能打通 quota API。  
原实现会在进入 fetch 前就基于 `expiry_date` 强制 refresh。

这会导致：

- 只要 refresh 路径出问题，即使旧 token 还能用，额度查询也会失败

### 2. Gemini CLI 安装结构已变化

之前的实现只会去旧路径里找 OAuth client 配置，例如：

- `.../dist/src/code_assist/oauth2.js`

但本机安装的 Gemini CLI 已改成 bundle 结构，实际凭据出现在：

- `bundle/chunk-*.js`

其中包含：

- `OAUTH_CLIENT_ID`
- `OAUTH_CLIENT_SECRET`

所以原实现在 refresh 分支里很可能会报：

- `Could not find Gemini CLI OAuth configuration`

## Differences vs CodexBar

参考：

- `/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Gemini/GeminiStatusProbe.swift`
- `/Users/yovinchen/project/CodexBar/Sources/CodexBarCore/Providers/Gemini/GeminiProviderDescriptor.swift`
- `/Users/yovinchen/project/CodexBar/docs/gemini.md`

`CodexBar` 的正确思路是：

- 读取 `settings.json` 判断 auth 类型
- 读取 `oauth_creds.json`
- 调 `loadCodeAssist` 拿 tier + project
- 必要时发现 project
- 调 `retrieveUserQuota`
- 把模型 buckets 映射成：
  - `Pro`
  - `Flash`
  - `Flash Lite`

`Claude Island` 原先和它相比的缺口：

- refresh 过于依赖本地 expiry 时间
- OAuth client 提取路径未覆盖 bundle 版 Gemini CLI
- `cloudaicompanionProject` 只按字符串解析，不够稳
- 没把 `Code Assist` 细节完整挂到详情页

## What Was Fixed

### Backend

- Gemini 先尝试当前 `access_token`
- 只有在 quota API 返回 `401` 时才 refresh 再重试
- OAuth client 提取新增 bundle `chunk-*.js` / `oauth2-provider-*.js` 扫描
- `loadCodeAssist` 现在支持：
  - `cloudaicompanionProject` 为字符串
  - `cloudaicompanionProject` 为对象
- 新增 project discovery fallback：
  - `GET https://cloudresourcemanager.googleapis.com/v1/projects`

### Data surfaced

- 仍显示三条窗口：
  - `Pro`
  - `Flash`
  - `Flash Lite`
- 详情页现在还会带出：
  - `Code Assist` tier name
  - project id
  - paid tier name
  - 是否 Google-managed / user-managed project

### UI

- `Usage` 行布局调整为更接近参考图：
  - 左侧 label
  - 中间进度条
  - 下方 percent
  - 右侧 reset 时间

## Verification

已通过：

- `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Debug CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project ClaudeIsland.xcodeproj -scheme ClaudeIsland -configuration Debug CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -enableCodeCoverage NO test`

新增测试：

- `GeminiQuotaProviderTests.testGeminiOAuthClientCredentialsParseBundledChunkContent`
- `GeminiQuotaProviderTests.testGeminiProjectIdParsesNestedCloudCompanionProject`

## Remaining Risk

- 还没有在 UI 中做真实截图级人工验收
- 尚未加入 `Gemini` CLI `/stats` 文本解析作为 runtime fallback
- `Quota` 详情里虽然已经挂出更多 Code Assist 信息，但还没有单独显示订阅管理链接
