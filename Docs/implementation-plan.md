# 支持矩阵实现计划

> 依据: [support-matrix.md](./support-matrix.md)
> 更新时间: 2026-04-06

## 目标

把当前仍处于 `部分支持 / 宿主级支持 / 未接入` 的对象，分批推进为更稳定、可验证、可维护的实现。

## 批次划分

### Batch 1: 低风险闭环增强

- `Pi Coding Agent`
  - 继续收敛 `json` / `rpc` 样本解析
  - 维持 helper-first，不搬到 Swift runtime
- `Crush`
  - 继续打磨高层 watcher
  - 不再假设存在正式 tool-level log schema
- `Windsurf`
  - 已完成 workspace/system 诊断增强
  - 下一步才考虑更深托管
- `Pi / Crush`
  - helper 已进入 auto-repair / watcher 链路
- `Amp CLI`
  - 当前已补项目级 `.amp/settings.json` / `.amp/plugins/` 的运行时诊断

### Batch 2: 部分支持对象补强

- `Copilot CLI`
  - 继续补 payload 兼容性
  - 收敛 `modifiedArgs` 的真实样本
- `Kimi CLI`
  - 补齐剩余官方 hooks 事件覆盖
  - 做最小联调样本
- `Kiro CLI`
  - 提升 custom agent / wrapper 可用性
  - 继续保持不自动改默认 agent
- `Cline / Cline CLI`
  - 在 native `cancel` 基础上继续补返回面
  - 当前已补项目级 `.clinerules/hooks` 的存在时托管
- `Qoder`
  - 保持单一 source，不拆 `qoder_cli`
  - 当前已补项目级 `.qoder/settings.json` / `.qoder/settings.local.json` 的存在时托管

### Batch 3: 高不确定性对象

- `Qoder CLI`
  - 仅在官方 CLI hooks 文档稳定后重启实现
- `Warp / JetBrains`
  - 保持宿主识别方向
  - 不轻易升格为 hook source
- `Antigravity / Lingma / Claudix / RooCode / Trae`
  - 继续维持 docs-only
  - 直到存在可验证的官方入口

## 实施顺序

1. `Copilot CLI` payload / approval 细节
2. `Kimi CLI` 事件覆盖与联调样本
3. `Kiro CLI` 可用性增强
4. `Cline` 返回面增强
5. `Windsurf` 更深托管是否值得做
6. `Qoder CLI` 仅在文档稳定后再评估

## 当前明确不做

- 不把 `Crush` 伪装成正式 tool-level source
- 不在没有稳定官方入口前强拆 `Qoder CLI`
- 不自动修改 `Kiro` 默认 agent
- 不把 `Warp / JetBrains` 直接做成 hooks source
