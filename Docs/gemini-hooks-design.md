# Gemini CLI Hooks 集成设计方案

> 适用仓库: `claude-island`  
> 分析时间: 2026-04-05  
> 目标: 解释 Gemini CLI hooks 报错根因，并给出一套可落地的修复与演进方案。

## 1. 问题现象

当前 Gemini CLI 报错为:

```text
Invalid hook event name: "notification" from project config. Skipping.
Invalid hook event name: "postToolUse" from project config. Skipping.
Invalid hook event name: "preToolUse" from project config. Skipping.
Invalid hook event name: "sessionEnd" from project config. Skipping.
Invalid hook event name: "sessionStart" from project config. Skipping.
Invalid hook event name: "stop" from project config. Skipping.
```

这不是 hook 脚本执行失败，而是 **配置里的事件名本身不被 Gemini CLI 识别**，因此 Gemini 在加载配置阶段就直接跳过了这些 hook。

## 2. 官方文档结论

### 2.1 配置层级

Gemini CLI 有 3 层 `settings.json`:

- 用户级: `~/.gemini/settings.json`
- 项目级: `.gemini/settings.json`
- 系统级: `/Library/Application Support/GeminiCli/settings.json`（macOS）

其中 **项目级配置会覆盖用户级配置**。这意味着如果报错里明确写的是 `from project config`，即使用户级配置修好了，项目里的 `.gemini/settings.json` 仍然会继续报错。

### 2.2 Hook 配置格式

Gemini hooks 使用的结构是:

```json
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "node .gemini/hooks/example.js"
          }
        ]
      }
    ]
  }
}
```

关键点:

- `hooks` 下的 key 必须是 Gemini 官方支持的事件名
- `matcher` 对工具类事件生效
- hook 通过 `stdin` 收 JSON，通过 `stdout` 返回 JSON

### 2.3 Gemini 官方支持的事件

Gemini 官方 hooks 事件包括:

- `BeforeTool`
- `AfterTool`
- `BeforeAgent`
- `AfterAgent`
- `BeforeModel`
- `BeforeToolSelection`
- `AfterModel`
- `SessionStart`
- `SessionEnd`
- `Notification`
- `PreCompress`

Gemini **没有** 下列 Claude/Codex 风格事件:

- `preToolUse`
- `postToolUse`
- `sessionStart` / `sessionEnd`（camelCase）
- `stop`
- `notification`（lowercase）
- `PermissionRequest`

### 2.4 与 Claude Code 最大差异

这次报错的根源，本质上是把 Claude 风格事件名误写进了 Gemini 配置。

更关键的语义差异有 3 个:

1. Gemini 没有独立的 `PermissionRequest`
   `Notification` 只能观测到权限提示，不能替用户批准。
2. Gemini 没有 `Stop`
   结束一轮对话最接近的事件是 `AfterAgent`，而不是 `SessionEnd`。
3. Gemini 有更多 LLM 生命周期事件
   `BeforeModel`、`AfterModel`、`BeforeToolSelection` 是 Claude Island 目前没有直接 UI 对应物的扩展点。

## 3. 当前仓库里的差距

### 3.1 安装器把错误事件名写进了 Gemini 配置

`ClaudeIsland/Services/Hooks/HookInstaller.swift:728-729` 当前写入的是:

```swift
let events = ["sessionStart", "sessionEnd", "preToolUse", "postToolUse",
               "stop", "notification"]
```

这 6 个 key 对 Gemini 都不对:

- `sessionStart` / `sessionEnd` 应改为 `SessionStart` / `SessionEnd`
- `preToolUse` / `postToolUse` 应改为 `BeforeTool` / `AfterTool`
- `notification` 应改为 `Notification`
- `stop` 在 Gemini 中根本不存在

因此当前安装器写出来的配置会被 Gemini 直接判定为非法。

### 3.2 README 的 Gemini 映射说明已经过时

`README.md:267-272` 当前写的是:

- `sessionStart` → `SessionStart`
- `preToolUse` → `BeforeTool`
- `postToolUse` → `AfterTool`
- `stop` → `SessionEnd`
- `notification` → `Notification`

这里有两个问题:

- 它把“内部统一事件名”和“Gemini 原生配置事件名”混在了一起
- 它把 `stop` 错误地等同于 `SessionEnd`

但 Gemini 的 `SessionEnd` 是“CLI 退出 / clear / logout”，不是“一轮回答结束”。

### 3.3 Bridge 还不会识别 Gemini 的真实事件名

即使手动把 Gemini 配置改对，`ClaudeIslandBridge/EventMapper.swift:153-175` 当前也没有这些 alias:

- `BeforeTool`
- `AfterTool`
- `BeforeAgent`
- `AfterAgent`
- `PreCompress`

这意味着 Gemini 就算真的发来了合法事件，Claude Island 内部状态机仍然会拿到原始字符串，导致:

- phase 推断变成 `unknown`
- 工具事件不会进入 `PreToolUse` / `PostToolUse` 分支
- 文件同步不会被触发
- 一轮回答结束不会被识别为 `Stop`

### 3.4 当前事件内容提取也不完整

`ClaudeIslandBridge/EventMapper.swift:83-89` 目前只处理了:

- 字符串类型的 `tool_response`
- `last_assistant_message`

但 Gemini 官方字段更像是:

- `AfterTool.tool_response` 是对象
- `AfterAgent.prompt_response` 才是一轮最终回答

所以就算事件进来了，Claude Island 现在也拿不到 Gemini 最有价值的两类展示内容:

- 工具执行结果摘要
- 最终回复文本

### 3.5 当前产品只暴露了用户级 Gemini 配置路径

`HookSetupView.swift:273` 只显示 `~/.gemini/settings.json`。  
但 Gemini 官方明确支持项目级 `.gemini/settings.json`，而且项目级优先级更高。

所以从产品视角看，当前还有一个显性缺口:

- 用户以为修的是 Gemini 配置
- 实际报错来源却可能是项目级 `.gemini/settings.json`
- Claude Island 现在既不提示，也不修复

## 4. 根因判断

根因不是单点 bug，而是 **Gemini 集成边界定义错了**:

1. 安装层把 Claude Island 的“内部统一事件概念”直接写成了 Gemini 的“原生配置事件名”
2. 归一化层没有为 Gemini 原生事件建立 source-aware mapping
3. 会话完成态错误地把 `stop` 近似成 `SessionEnd`
4. 配置管理只覆盖用户级，不覆盖项目级诊断

一句话总结:

**当前实现把“Gemini 像 Claude Code 一样工作”当成前提，但官方文档表明 Gemini 只是“配置结构相近”，并不是“事件模型相同”。**

## 5. 设计目标

本次改造建议满足以下目标:

1. 消除 Gemini 启动时的 `Invalid hook event name` 警告
2. 保留 Claude Island 现有内部统一事件模型，避免大面积改 UI 和状态机
3. 正确映射 Gemini 的“每轮开始 / 工具前后 / 每轮结束 / 会话结束 / 压缩 / 通知”
4. 明确 Gemini 不支持 Notch 直接审批权限，避免误导
5. 增加对项目级 `.gemini/settings.json` 的诊断能力

## 6. 推荐方案

### 6.1 总体原则

采用两层模型:

- 安装层: 只写 **Gemini 原生事件名**
- Bridge 层: 再把 Gemini 原生事件映射到 Claude Island 内部统一事件名

也就是:

**native install, unified internal events**

### 6.2 推荐的 Gemini v1 受管事件集

| Gemini 原生事件 | Claude Island 内部事件 | 是否建议注册 | 说明 |
|---|---|---:|---|
| `SessionStart` | `SessionStart` | 是 | 建会话 |
| `BeforeAgent` | `UserPromptSubmit` | 是 | Gemini 没有独立的 `UserPromptSubmit`，这是最接近语义 |
| `BeforeTool` | `PreToolUse` | 是 | 工具开始 |
| `AfterTool` | `PostToolUse` | 是 | 工具结束 |
| `AfterAgent` | `Stop` | 是 | Gemini 没有 `Stop`，这里承担“本轮完成”语义 |
| `Notification` | `Notification` | 是 | 仅观测，不审批 |
| `PreCompress` | `PreCompact` | 是 | 语义基本对应 |
| `SessionEnd` | `SessionEnd` | 是 | CLI 退出/clear |
| `BeforeModel` | 无 | 否，先不做 | 当前 UI 无直接收益 |
| `BeforeToolSelection` | 无 | 否，先不做 | 更适合未来策略型扩展 |
| `AfterModel` | 无 | 否，先不做 | 流式 chunk 事件，现阶段噪音大于收益 |

### 6.3 事件映射规则

推荐在 `EventMapper` 中新增 Gemini 专用映射:

| Gemini 原始事件 | 统一事件 |
|---|---|
| `SessionStart` | `SessionStart` |
| `BeforeAgent` | `UserPromptSubmit` |
| `BeforeTool` | `PreToolUse` |
| `AfterTool` | `PostToolUse` |
| `AfterAgent` | `Stop` |
| `Notification` | `Notification` |
| `PreCompress` | `PreCompact` |
| `SessionEnd` | `SessionEnd` |

同时建议保留一个 `raw_event` 或等价调试字段，方便后续排查 Gemini 特有行为。

### 6.4 Installer 改造建议

#### 推荐实现

把当前 `GeminiHookSource` 改成和 `Qoder` / `CodeBuddy` 一样的“原生事件配置器”，而不是继续手写 camelCase 事件列表。

推荐的受管配置大致如下:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source gemini" }] }],
    "BeforeAgent": [{ "hooks": [{ "type": "command", "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source gemini" }] }],
    "BeforeTool": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source gemini" }] }],
    "AfterTool": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source gemini" }] }],
    "AfterAgent": [{ "hooks": [{ "type": "command", "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source gemini" }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source gemini" }] }],
    "PreCompress": [{ "hooks": [{ "type": "command", "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source gemini" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "~/.claude-island/bin/claude-island-bridge-launcher.sh --source gemini" }] }]
  }
}
```

#### 安装/卸载策略

安装时不仅要写入正确 key，还要主动删除 Claude Island 旧版本写入的遗留 key:

- `sessionStart`
- `sessionEnd`
- `preToolUse`
- `postToolUse`
- `stop`
- `notification`

否则用户升级后，旧 key 还会残留在配置里继续触发 warning。

### 6.5 Bridge 改造建议

#### 事件归一化

`EventMapper.normalizeEventName()` 需要补齐 Gemini native alias，或者更推荐改成:

- 先按 `source`
- 再按 `raw event`
- 最后映射到统一事件

这样能避免不同 CLI 同名异义时继续堆 alias。

#### 字段提取

建议追加 Gemini 专用字段提取:

1. `BeforeAgent.prompt` → `prompt`
2. `AfterAgent.prompt_response` → `last_assistant_message`
3. `AfterTool.tool_response.returnDisplay` → `tool_response`
4. `AfterTool.tool_response.error` → `error`
5. `Notification.details` → 可选序列化到 `message` 或新增调试字段

### 6.6 状态机兼容策略

因为 `SessionEvent.swift:166-175` 和 `SessionStore.swift:145-155` 当前都依赖统一事件名:

- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `Stop`
- `PreCompact`

所以最稳妥的方式不是让 UI 学习 Gemini 新事件，而是 **在 Bridge 层把 Gemini 先折叠回现有统一模型**。

这也是为什么推荐:

- `BeforeAgent` → `UserPromptSubmit`
- `AfterAgent` → `Stop`
- `PreCompress` → `PreCompact`

### 6.7 项目级配置策略

这部分和本次 warning 直接相关，建议单独做。

#### 不推荐

启动时静默改写仓库内 `.gemini/settings.json`。

原因:

- 项目配置通常在版本控制下
- 自动修改仓库文件会引入不可预期的 diff
- 不同项目可能故意自定义 hooks

#### 推荐

增加“检测 + 提示 + 用户确认修复”的策略:

1. Claude Island 检测当前 workspace 下是否存在 `.gemini/settings.json`
2. 若存在，扫描是否含有 Claude Island 旧版遗留 key
3. 若命中，提示:
   - 当前 warning 来源是项目配置
   - 项目配置优先于用户配置
   - 可一键修复为 Gemini 官方事件名

这能解决“用户修了 `~/.gemini/settings.json`，但 warning 还在”的困惑。

### 6.8 权限审批策略

Gemini 的 `Notification` 文档明确是 observability-only。

因此设计上应当:

- 不把 Gemini 标成支持 `PermissionRequest`
- 不提供 approve/deny 按钮
- 可以把 `Notification` 中的 `ToolPermission` 作为“被动提醒”展示
  文案类似: “Gemini 正在终端等待权限确认，请回到 CLI 完成批准”

这能保留体验价值，同时不违背官方能力边界。

## 7. 分阶段实施建议

### Phase 1: 修正核心集成

1. 修正 Gemini 安装器事件名
2. Bridge 增加 Gemini 原生事件映射
3. 增加 `prompt_response` / 结构化 `tool_response` 解析
4. 更新 README 中的 Gemini 说明

### Phase 2: 补齐配置诊断

1. 检测项目级 `.gemini/settings.json`
2. 提供“项目配置覆盖用户配置”的 UI 文案
3. 提供显式修复入口

### Phase 3: 扩展高级事件

按需要再考虑:

- `BeforeModel`
- `BeforeToolSelection`
- `AfterModel`

这些更适合策略增强，不是本次 warning 修复的阻塞项。

## 8. 验收标准

完成后，至少应满足:

1. Gemini 启动时不再出现 `Invalid hook event name`
2. Claude Island 能看到 Gemini 的:
   - 会话开始
   - 用户提交 prompt
   - 工具开始/结束
   - 本轮回答结束
   - 会话结束
   - 压缩前事件
3. `SessionEnd` 只在 CLI 真正退出或 clear 时触发，不再冒充 `Stop`
4. UI/README 明确说明 Gemini 不支持通过 Claude Island 直接审批权限
5. 若 warning 来自项目级 `.gemini/settings.json`，产品能给出可理解的诊断

## 9. 建议补充的测试

当前仓库没有现成的 hooks 测试目标，建议至少补下面两类测试:

### 9.1 安装器测试

- 安装 Gemini hooks 后，输出 key 只包含原生事件名
- 再次安装不会重复追加
- 升级安装会清理旧版 camelCase key

### 9.2 EventMapper 测试

- `BeforeAgent` 被映射为 `UserPromptSubmit`
- `AfterAgent` 被映射为 `Stop`
- `BeforeTool` / `AfterTool` 被映射为 `PreToolUse` / `PostToolUse`
- `PreCompress` 被映射为 `PreCompact`
- `prompt_response` 被提取为 `last_assistant_message`
- 结构化 `tool_response` 能正确抽取展示文本

## 10. 最终结论

这次 Gemini hooks 报错的直接原因是:

**Claude Island 当前写入了 Gemini 不支持的事件名。**

但真正要彻底修好，不能只改安装器，还要一并修:

- Gemini 原生事件到统一事件的 Bridge 映射
- `AfterAgent` / `BeforeAgent` 的轮次语义
- 项目级 `.gemini/settings.json` 的诊断与修复策略

推荐按“先修原生事件注册，再修 Bridge 映射，最后补项目级配置诊断”的顺序实施。

## 参考文档

- Hooks 总览: https://geminicli.com/docs/hooks/
- Hooks Reference: https://geminicli.com/docs/hooks/reference/
- Writing Hooks: https://geminicli.com/docs/hooks/writing-hooks/
- Gemini CLI Configuration: https://geminicli.com/docs/cli/configuration/
