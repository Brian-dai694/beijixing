# CODEX_BOOT — 千里马 Git-safe 公开模板短启动协议

你现在在千里马 Git-safe 公开模板仓。这里不得包含真实 token、账号、客户数据、ASIN 运营数据、成本台账、运行报告或本地路径。

启动顺序：
1. 运行 `powershell -NoProfile -ExecutionPolicy Bypass -File ".\start-qianlima.ps1"`。
2. 缓存命中且任务低风险时，先读取 `.qianlima/codex-router.json` 和 `.qianlima/response-policy.yaml`；否则读取 `.qianlima/WORKSPACE_INDEX.md`。
3. 当前仓只做模板、治理、校验、文档和公开示例；不要写入真实业务数据。

任务路由：
- README / 文档 / 翻译 → 编辑公开文档，并保持隐私边界
- 隐私剔除 / Git-safe → 跑 `.qianlima/scripts/verify-qianlima.ps1`
- 校验失败 / 红叉 → 本地复现 GitHub Actions 步骤
- 补 workflow / task-card → 只写 public-safe 模板定义
- 提交推送 → 先确认 `git status`、跑校验，再 commit/push

每次开始任务先输出状态卡：
- 工作区：Git-safe 公开模板
- 当前场景：___
- 已加载来源：___
- 将使用 workflow/脚本：___
- 隐私风险/待验证：___

体验规则：
- 先用 `scripts/new-staged-response.ps1` 判定 `L0-L4`，3 秒内交付路线、已知事实或明确排除项；不要只说“正在处理”。
- 用 `A=实时数据 / B=近期缓存 / C=历史记录或假设` 标识第一轮结论。
- 低风险任务可复用 `.qianlima/working/` 中的脱敏热状态；高风险、配置变更或来源过期时必须刷新。
- 只有任务升级为决策、报告、跨源证据或高风险执行时，才补齐完整 trace 和评估包。
- 长任务用 `scripts/new-task-contract.ps1` 创建可恢复检查点；用户要求“只给结论 / 停止深查 / 报告 / 取消”时，用 `scripts/set-task-control.ps1` 更新控制状态。
- 快照只用于初判：用 `scripts/get-snapshot-decision.ps1` 判断新鲜、SWR 或必须实时取证；高风险动作前不得使用快照代替实时来源。
- 数据源每次调用后用 `scripts/update-tool-health.ps1` 记录成功率、耗时和完整度；慢或不完整的源降为回退。
- 用 `scripts/write-experience-event.ps1` 记录首轮交付、工具耗时和最终交付；用 `scripts/get-quality-dashboard.ps1` 生成本地质量仪表盘。

硬规则：
- 不提交真实 `work.ws`、`data-sources.yaml`、usage ledger、decision log、报告、截图、token 或本地路径。
- 公开仓只能保留 `.example`、模板、治理规则、脚本和脱敏说明。
- 发布前必须运行 `verify-qianlima.ps1`。
