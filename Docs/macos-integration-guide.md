# macOS 集成与发布说明

> 适用仓库: `claude-island`
> 目标: 记录当前已实现的 macOS 系统集成面，方便后续继续打磨 hooks 之外的 Apple/macOS 事项。

## 当前已实现

### App Bundle / Helpers

Claude Island 当前会把以下 helper 资源打进 app bundle，并在运行时复制到 `~/.claude-island/bin/`：

- `claude-island-bridge-launcher.sh`
- `claude-island-statusline`
- `claude-island-amp`
- `claude-island-amp-exec`
- `claude-island-kiro`

复制入口统一在 `HookInstaller.installLauncher()`，不走 heredoc 动态生成。

### macOS 宿主识别与聚焦

当前已经支持以下几类宿主应用识别和聚焦：

- 终端：Terminal、iTerm2、Ghostty、Kitty、Alacritty、WezTerm、Hyper、Warp
- IDE：VS Code、Cursor、Windsurf、JetBrains 家族、Zed

聚焦路径包括：

- `TERM_PROGRAM` 映射
- `__CFBundleIdentifier` 映射
- PID 向上回溯父进程
- iTerm2 AppleScript 激活

### 通知与权限体验

- 权限请求会通过 `UNUserNotificationCenter` 触发系统通知
- 任务完成也会走系统通知
- Notch 审批仍然是主交互面；系统通知只做补充提醒

### 打包与本地发布

当前 README 已覆盖：

- Debug / Release 无签名构建
- 通过 `hdiutil` 生成本地 DMG
- 从 Xcode DerivedData 运行 app

## 当前推荐调试路径

### 1. Debug 构建

```bash
xcodebuild \
  -project ClaudeIsland.xcodeproj \
  -scheme ClaudeIsland \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

### 2. 查看 helper 是否已复制

```bash
ls ~/.claude-island/bin
```

重点确认：

- `claude-island-bridge-launcher.sh`
- `claude-island-amp`
- `claude-island-amp-exec`
- `claude-island-kiro`

### 3. 手动测试 socket 链路

```bash
echo '{"type":"session_start","session_id":"test"}' | socat - UNIX-CONNECT:/tmp/claude-island.sock
```

### 4. 验证 LaunchServices 注册

构建后 app 会由 Xcode 自动执行 `lsregister`。若 Finder / `open` 行为异常，可重新运行 app 或重建后再试。

## 后续建议

### 高优先级

- 继续补齐 macOS helper 的 README 入口说明
- 校对 JetBrains / Warp / Windsurf 的 bundle id 与聚焦行为
- 保持 helper 安装逻辑和资源列表同步

### 中优先级

- 单独补一份签名 / notarization / 分发流程说明
- 把通知与审批策略整理成单独的 UX 文档

### 暂不处理

- iOS / iPadOS / visionOS 产品化
- 自动 notarization 或 CI 发布流水线
