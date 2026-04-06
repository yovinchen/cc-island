# Windsurf / Cascade Hooks — 差距分析

> 官方 Hooks: https://docs.windsurf.com/windsurf/cascade/hooks
> 官方下载页: https://windsurf.com/download
> 分析日期: 2026-04-06

## 当前仓库状态

| 项目 | 状态 | 说明 |
|------|------|------|
| `SessionSource` / `HookSource` | ✅ | 当前已新增 `windsurf` source 与安装器 |
| 宿主终端识别 | ✅ | `TerminalAppRegistry` 已识别 `Windsurf` 名称和 `com.exafunction.windsurf` bundle id |
| Hook 安装与事件映射 | ✅ | 已支持用户级 `hooks.json` 安装；若当前工作目录存在 `.windsurf/hooks.json`，也会一并纳入受管安装 |

## 官方已提供的 Hook 能力

| 能力 | 官方状态 | 说明 |
|------|------|------|
| Cascade Hooks | ✅ | 支持在 Cascade workflow 的关键节点执行 shell 命令 |
| 输入协议 | ✅ | hook 通过 stdin 接收 JSON 上下文 |
| 阻塞语义 | ✅ | pre-hook 可通过 exit code `2` 阻止动作 |
| 多层配置 | ✅ | system / user / workspace 三级 `hooks.json` 合并 |
| 企业分发 | ✅ | 官方支持 dashboard 与系统级文件下发 |

## 与现有仓库的差距

1. Windsurf 已经有成熟 hooks，但 Claude Island 还没有对应的 source、配置路径与安装器。
2. 现有 `HookResponse` 模型未适配 Windsurf 的 pre-hook 阻塞语义。
3. 需要补充 Windsurf 的事件名到统一事件的映射策略。
4. 需要评估 Windsurf JetBrains 插件是否复用同一 hooks 面；当前公开 hooks 文档主要面向 Windsurf Editor / Cascade。

## 实现建议

1. 新增 `SessionSource.windsurf`、图标和安装检测。
2. 实现 `WindsurfHookSource`，写入 user/workspace `hooks.json`。
3. 在 `EventMapper` 里补齐 Cascade action 到 `SessionStart` / `PreToolUse` / `PostToolUse` / `Stop` 的归一化。
4. 审批先做只读监控，再评估是否把 pre-hook exit code `2` 接到 Notch 审批。

## 结论

Windsurf **现已完成首版接入**。当前版本先覆盖用户级 hooks 安装和基础状态追踪，审批仍保留在后续阶段。

## 基于本地代码的实现可行性

**可行性评级**: 高

**可直接复用**
- `CursorHookSource` 可作为安装器模板，因为同样是独立 `hooks.json` 风格。
- `EventMapper`、`HookSocketServer`、`PermissionHandler` 已有成熟的“自定义 source + 自定义返回格式”模式。
- UI、repair、setup 列表已经有固定扩展点，新增 source 是机械工作。

**最小实现方案**
1. 已新增 `SessionSource.windsurf` 和 `WindsurfHookSource`。
2. 当前已补更完整的 event -> 统一事件映射，包括 `post_read_code`、`pre_mcp_tool_use`、`post_mcp_tool_use`、`post_cascade_response_with_transcript`、`post_setup_worktree`。
3. 当前运行时已会检测 workspace 级 `.windsurf/hooks.json` 和 system 级 `/Library/Application Support/Windsurf/hooks.json`；workspace 层在当前工作目录存在时已纳入受管安装，system 层仍保持诊断-only。
4. 下一步再决定是否把 pre-hook 阻塞接到 Notch 审批，以及是否值得做 system 级托管。

**主要阻塞**
- 当前主要阻塞已经从“没有 source”转成“是否要支持审批返回和更多 Windsurf 事件类型”。
