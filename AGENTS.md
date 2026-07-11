# 千里马计划 Agent 启动规则

任何 Agent、代码助手、大模型工作流或自动化工具在本目录工作时，必须先完成启动索引。

## 必做步骤

1. 先运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\start-qianlima.ps1"
```

2. 查看启动结果：

- 如果显示 `Startup mode: cached`，说明规则和目录未变。低风险、高频任务只读取 `.qianlima/CODEX_BOOT.md` 和 `.qianlima/codex-router.json`，按命中的任务卡继续；普通聊天直接回答，不加载运营配置。
- 如果显示 `mode: refreshed`，或任务模糊、跨领域、高风险、配置刚修改，则读取完整工作区索引。

3. 完整启动索引：

```text
.qianlima/WORKSPACE_INDEX.md
.qianlima/CODEX_BOOT.md
.qianlima/risk-rules.yaml
```

## 工作规则

- 不要一次性读取整个工作区。
- 配置或目录变更后使用 `start-qianlima.ps1 -Force` 重建索引和校验；缓存损坏会自动回退到完整启动。
- `codex-router.json` 只用于低风险快速路由。高风险、歧义或跨系统任务必须回读 `natural-language-router.yaml`、`risk-rules.yaml` 和对应任务卡。
- 先用 `.qianlima/scripts/new-staged-response.ps1` 进行 `L0-L4` 快速判级；3 秒内必须交付路线、已知事实或排除项，并标注 `A/B/C` 证据等级。
- 会话内优先读取脱敏热状态；只有来源过期、规则改动或高风险执行前才刷新。阶段 0-2 使用最小 trace，任务升级后再补全审计。
- 长任务先创建 `.qianlima/scripts/new-task-contract.ps1` 合同；每次外部读取前运行 `check-task-contract.ps1`，尊重“只给结论、停止深查、报告、取消”等中断控制。
- 快照和 SWR 只能提供初判，实时取证可推翻初判；高风险决策前必须重新读取原始来源并走现有确认门禁。
- 原始 CSV 先经 `summarize-csv.ps1` 聚合，模型只接收汇总、缺字段和异常分组；聚合结果必须保留重跑入口。
- 用体验事件和工具健康记录归因性能问题，优化以首次有用输出、最终交付、证据完整率和采纳率为准。
- 先根据用户任务选择 `.qianlima/task-cards/` 中的任务卡，再读取对应 workflow 和 template。
- 只有长文件、多文件任务才读取 `context-policy.yaml`；只有需要模型选择时才读取 `model-adapters.yaml`。
- 只有需要业务状态或真实数据时才读取私有 `work.ws`、`data-sources.yaml` 和 `file-registry.yaml`。
- 需要数据时再读取 `.qianlima/data-sources.yaml` 和 `.qianlima/file-registry.yaml`。
- 长文件、多文件任务必须按 `.qianlima/context-policy.yaml` 处理。
- 高风险动作必须按 `.qianlima/risk-rules.yaml` 处理。
- 输出结果要说明数据来源、待验证项和使用情况。

如果启动索引失败，先修复索引或缺失文件，不要直接开始业务任务。
