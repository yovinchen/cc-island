# Cline / Cline CLI Hooks — 差距分析

> 官方文档: https://docs.cline.bot/features/hooks/hook-reference
> 分析日期: 2026-04-06

## 当前仓库状态

| 项目 | 状态 | 说明 |
|------|------|------|
| `SessionSource` / `HookSource` | ✅ | 已新增 `SessionSource.cline` 与 `ClineHookSource` |
| 安装路径 | ✅ | 当前会管理 `~/Documents/Cline/Hooks` 与默认 `~/.cline/data/globalState.json` |
| EventMapper | ✅ | 已补 Cline 事件名归一化与基础字段提取 |
| IDE 宿主识别 | 间接 | 若运行在 VS Code / Cursor / JetBrains，可借助现有宿主窗口聚焦逻辑，但不是 Cline 专项宿主集成 |

## 官方可用扩展面

| 能力 | 状态 | 说明 |
|------|------|------|
| Hooks | ✅ | 官方文档列出 hook 参考与事件类型 |
| 规则系统 | ✅ | 官方文档强调 hooks 与 rules 配合使用 |
| Checkpoints | ✅ | 官方提供 checkpoint / rollback 配套能力 |
| Auto-Approve | ✅ | hooks 可与 Auto-Approve 共同工作 |

## 对 Claude Island 的主要 gap

1. 当前首版已开始接 `cancel: true` 阻塞返回，但仍未验证更多 Cline 输出字段。
2. 当前只管理默认全局路径；若用户通过 `CLINE_DIR` / `--config` 改了目录，Claude Island 只会给出诊断，不会自动迁移。
3. 仍需要继续确认 Cline CLI 与扩展在更多配置场景下是否完全同构，但当前已按单一 `cline` source 落地。

## 实现建议

1. 保持当前首版，先覆盖 `TaskStart / TaskResume / UserPromptSubmit / PreToolUse / PostToolUse / PreCompact / TaskComplete / TaskCancel`。
2. 下一步再评估 `cancel: true` / `Auto-Approve` 是否能安全接到 Notch 审批。
3. 若 Cline CLI 和扩展最终证实 schema 不同，再拆成 `cline` / `cline_cli` 两个 source。

## 结论

Cline / Cline CLI **当前已部分接入**。Claude Island 现在已经具备首版 hooks source、事件归一化、基础 UI 接线，并已开始支持 `cancel` 风格阻塞返回。

## 基于本地代码的实现可行性

**可行性评级**: 中高

**可直接复用**
- 若 Cline 采用 shell-command + stdin/stdout 协议，可直接复用 `CursorHookSource` / `CopilotHookSource` 这类自定义 source 模式。
- `PermissionHandler` 的隐式审批思路也能复用到 `PreToolUse.permissionDecision` 风格。

**本地代码复核结果**
- 当前仓库已新增 `ClineHookSource`，会写入 `~/Documents/Cline/Hooks/<HookName>` 脚本，并在默认 `~/.cline/data/globalState.json` 中开启 `hooks-enabled`。
- 当前安装器会记录并在卸载时恢复原来的 `hooks-enabled` 值，避免把用户全局开关永久改写。
- `HookInstaller`、`HookFileWatcher`、`HookRepairManager`、setup/settings/notch 列表都已纳入 `cline`。
- `EventMapper` 已补 `TaskStart / TaskResume / TaskComplete / TaskCancel` 归一化，以及 `preToolUse` / `postToolUse` 的基础字段提取。
- `PermissionHandler` 与 `HookSocketServer` 当前已开始把危险 `PreToolUse` 映射成 Cline 的 `{"cancel":true|false,"errorMessage":"..."}` 返回。
- 当前 `HookSocketServer` 也已补 `contextModification` 字段透传，因此允许类响应现在可同时向 Cline 注入额外上下文。
- 当前运行时也会在检测到 `CLINE_DIR` 时给出明确提示，并带出实际自定义目录路径，减少“安装到了默认目录但实际运行在自定义目录”的误判。

**最小实现方案**
1. 维持当前单一 `cline` source，不再等待 CLI/扩展完全拆分后才开始。
2. 第一阶段只做监控与基础启用，第二阶段再决定是否接审批。
3. 后续若确认 `CLINE_DIR` 自定义目录的稳定管理方式，再补自定义路径支持。

**主要阻塞**
- 当前阻塞已经从“有没有 source”转成“Cline 的 `cancel` / Auto-Approve 语义值不值得接入统一审批”和“自定义 config 目录如何安全托管”。
