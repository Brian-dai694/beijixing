# 变更历史 · Changelog

本项目遵循语义化版本。日期为公开模板仓的发布日。

## [v2.12.0] - 2026-07-23
- 新增统一企业 Tool Risk Policy：R0 只读查询、R1 分析推理、R2 修改、R3 调试/进程内存写入。
- 新增 `reverse-readonly`、`reverse-triage`、`reverse-edit`、`reverse-debug` Profile 能力包；R3 当前版本机械拒绝，R2 只输出待人工确认计划。
- 强制租户、项目、产物、会话、任务、Grant、设备、工具版本和 Manifest Hash 显式绑定，拒绝 `current_project`、`all_projects` 等隐式上下文。
- 新增专业工具证据回执与会话控制：参数摘要、来源位置、差异、验证、审批、超时、预算、版本漂移和撤销均可追溯。
- 新增 9 项离线 Tool Profile 回归；不启动专业工具、调试器、网络或内存写入。

## [v2.11.1] - 2026-07-23
- 新增企业 API 最小权限合同与离线 Gate：API 默认拒绝，按 Provider、请求字段、写入 Body 字段、响应投影和任务数据范围放行。
- 私密配置只允许保存在本机企业配置或批准的 Secret Manager；Agent、Prompt、审计和核验模型只接触 Secret Reference，不接触密钥值。
- 多模型交叉核验改为脱敏 Claim Pack/Evidence Reference 输入，增加密钥、个人信息、作用域和字段白名单边界；交叉核验不产生权限。
- 未知成本、未列字段、全量后台/全库请求、未确认 L4 写入和原始凭据输入均阻断；新增 9 项离线回归。

## [v2.11.0] - 2026-07-22
- 源码级纠正：Helmsman 是磁盘 ANNS PoC，OpenSEO 是开源 SEO 数据分析平台，Apollo-11 是 AGC 原始源码数字化档案。
- 新增企业 Service/Repository/MCP 边界：UI、MCP 与定时 Agent 共享业务服务层，强制组织/项目/店铺作用域、成本回执、Secret Reference 与任务 Grant。
- 新增启动、后台、L4 前置三档自检及 Restart Table；后台检查为零优先级、可抢占、非破坏性，失败记录位置、来源、累计次数与恢复动作。
- 分层证据检索升级为授权过滤后热元数据召回、冷证据按需读取；当前不引入 Helmsman、SPDK、NVMe 或 C++ 运行依赖。
- 新增 13 项离线回归；MCP OAuth 不构成任务权限，定时任务使用独立身份/预算/Grant，业务写入仍禁用。

## [v2.10.0] - 2026-07-22
- 新增声明式变更计划合同：统一描述当前状态、期望状态、证据支持的差异、Plan Preview、可复算核验和不可覆盖的历史版本。
- 声明式变更计划是北极星内部治理合同；上一版对 Helmsman、OpenSEO 与 Apollo-11 的来源归因不准确，已在 v2.11.0 依据源码核验纠正。
- 新增离线 Plan Gate 与 10 项回归：缺证据、自核验、不可回放、L4 外部写入、伪造执行权和 Execute 阶段均默认阻断。
- 不扩大业务、网络、MCP、Agent 或执行权限；L4 只产生候选并进入人工审核，外部写入在本版本继续禁用。

## [v2.9.2] - 2026-07-22
- 建立共享自动化的跨平台脚本标准：统一使用 PowerShell 7 (`pwsh`) 承载治理逻辑，并要求 Windows/macOS CI 同时通过。
- 新增企业 Open Interpreter Runner 治理 Overlay，提供结构化 Runner Contract 与 Plan/Execute 双阶段离线门禁。
- Open Interpreter 保持 `discover_only`、未安装且无生产执行权；初始 Plan 仅允许 L1/L2 本地只读数据处理，真实 Execute 始终机械拒绝。
- 新增 10 项离线回归并纳入企业 Profile，确认不启动进程或监听器、不联网、不写文件、不读取密钥、不授予权限，且命令成功不等于业务核验通过。

## [v2.9.1] - 2026-07-21
- 修复使用账本的 YAML 枚举序列化，成本保护状态保持可机器匹配的无引号值；JSONL 账本仍使用版本化数值记录。
- 修复 macOS 命令安全回归：无法证明 Windows 风格路径位于工作区时允许拒绝，绝不把破坏性操作降级为放行。
- 不扩大 Agent、工具、网络、数据或执行权限；Pi / oh-my-pi 仍为仅发现模式。

## [v2.9.0] - 2026-07-21
- 吸收学习分支的安全门修复：补齐破坏性别名、覆盖写入与递归参数识别，并修复含空格绝对路径解析。
- A2A 增加 Broker 中介的子委派语义、父子 Grant 严格子集校验和可重复 Artifact 哈希回放。
- 新增 Work Node、Action Receipt、Manager Projection 与 Goal Work Graph，经理视图只采纳独立核验后的证据。
- 新增 Pi/oh-my-pi Runtime 影子准入与任务级 Sandbox Attestation；默认保持 discover-only、无网络、无写入。
- 统一 Usage Ledger 标量转义和模型有效成本计算，缺失价格字段改为失败关闭，并补齐 Pester/CI 回归。
- 显式升级 Harness：仅扩展 discover-only Runtime 注册与审计 accept/reject 决策，并更新规范化边界哈希。

## [v2.8.1] - 2026-07-20
- 修复 Windows GitHub Actions 在 Windows PowerShell 5.1 下读取无 BOM 中文 Obsidian fixture 时产生的解析失败；测试路径改为等价 ASCII fixture，不改变连接器策略。
- 保留 v2.8.0 的企业单版本、角色管理与用户管理能力，重新执行企业离线回归和跨平台 CI。

## [v2.8.0] - 2026-07-20
- 仓库收敛为单一企业版，移除旧的非企业 Edition、偏好/Skill 策略、跨版本规格和相应 CI 入口；主 Harness 保持冻结。
- 新增企业用户管理策略，明确身份、任职关系、角色分配、Agent 分配和任务 Grant 是五类独立对象。
- 角色管理升级为治理角色与业务角色两层，内置运营管理、供应链管理、财务管理和产品管理；角色仅允许申请，不授予常驻执行权。
- 新增角色分配合同、离线门禁和回归测试，覆盖自批拒绝、特权角色双人审批、临时角色到期、停用用户拒绝及职责分离。
- README、能力目录、MCP 映射、CI 和仓库合同统一定位为“企业版 Agent 分级信任治理框架”。

## [v2.7.8] - 2026-07-20
- 修复 Harness Boundary 在 Windows 本机与 GitHub Actions 之间因 CRLF/LF 差异产生的误报；受保护文件仍逐项校验，统一按 UTF-8、LF、无 BOM 的规范文本计算 SHA256。
- README 首页聚焦企业版 Agent 分级信任治理框架，不改变共享 Harness。
- 发布前校验覆盖 Windows、macOS、严格公开安全扫描、企业 Profile、协作规模门、Outcome、整组撤销和边界回归。

## [v2.7.7] - 2026-07-20
- 建立企业 Edition Overlay：只读引用同一冻结 Harness，企业配置、记忆、后台任务和协作策略独立治理。
- 企业协作增加任务、员工、部门和组织四级容量门，以及核验、审批、审计和预算背压；容量准入不签发 Grant，也不授予执行权。
- 每个子 Agent 强制使用独立 Work Order、任务级 Grant 和最小 Evidence Pack；Grant 精确绑定任务、员工、Agent、部门、工具范围与有效期，禁止父子权限继承和 Agent 直连。
- L3/L4 使用结构化审批证据，校验批准人角色、组织/部门/项目/任务范围、批准状态和有效期；外发数据与治理关键动作禁止批量审批。
- 新增企业协作 Outcome 合同，Claim 必须引用现存 Evidence Receipt，`blocked` 与 `failed` 分离，L4 只能完成候选结果。
- 新增整组撤销确认：取消、调岗、离职、Grant 过期或策略失败时撤销全部子 Grant 与直接 MCP 会话；任一目标未确认撤销，整个协作保持冻结。
- 新增三类能力执行目录与最小评测模板：确定性工具、按需知识、独立委派；普通聊天和同目标续问继续绕过运行时。
- 增加政策优先的数据准入、L0-L3 Evidence Pack 分层、Skill Intake Gate、Obsidian 受控接口、影子融合、证据市场、改进候选回放与可见执行事件合同。
- CI 覆盖 Windows/macOS、企业 Profile、模型融合、数据准入、协作 fan-in、规模门、Outcome、撤销和 Harness 边界；外部 A2A、生产 Runner、业务写入和自动策略提升仍默认关闭。

## [v2.7.6] - 2026-07-18
- Memory Broker 成为记忆读取的统一入口，支持任务、Grant、状态视图、作用域和撤销校验。
- Complexity Gate 接入 Agent admission 分析，新增 Agent、Pipeline stage 和复杂度提案必须先通过准入。
- 新增 Agent pipeline、Trace、改进候选、记忆状态和企业治理规格合同及回归测试。
- 企业版 overlay 补齐 Runner、组织、连接、MCP、审批、业务交付和文件治理合同；主 Harness 保持冻结。

## [v2.7.5] - 2026-07-18
- 建立企业亚马逊运营能力目录，覆盖报告、计划、利润、合规、选品、Listing、供应链、库存、广告、售后与根因复盘。
- 新增日/周/月/季/年度报告与利润口径规格，明确时间窗口、数据来源、假设和验证要求。
- 新增共享 MCP 能力与端口规划：业务域独立端口、默认不监听、仅回环绑定、任务结束撤销，不授予业务写入权限。
- 增加 MCP 端口规划回归测试，验证端口唯一性、能力覆盖、Grant 检查和零外部调用。

## [v2.7.4] - 2026-07-17
- Agent Runtime adapters: Codex supervisor, CodeWhale, Claude Code, Raven, plus discover-only Mimo, Kimi, Gemini, Aider, OpenCode, and Goose entries.
- Added grant, revocation, expiry, risk ceiling, Plan/Execute, sandbox, timeout, path, and secret guards with adapter regression coverage.
- Added local CLI discovery and safe startup contracts; unknown vendor CLIs remain discover-only until their command and sandbox contracts are verified.

## [v2.7.3] - 2026-07-15
- Codex 体感提速：普通对话、L0/L1 快答和同主题续问不再触发启动脚本或重复读取上下文。
- 新增单调用上下文装配器、显式会话租约、缓存版本校验、路由歧义失效和 L4 强制启动门禁。
- 增加上下文装配回归测试，覆盖首次路由、租约复用、歧义路由和高风险任务。
- macOS/Linux 增加显式 PowerShell 安装器，默认只预览，不静默安装系统依赖。

## [v2.7.2] - 2026-07-14
- 跨平台启动：新增 `start-qianlima.sh`（macOS/Linux 入口，检测 `pwsh`、缺失即明确报错，不谎报成功；透传 `-SkipValidation`/`-Force`/`-Quiet`）
- 文档补 macOS/Linux 命令（README/AGENTS/CLAUDE/AI_START_HERE）
- CI 新增 `verify-macos` job：`pwsh -File` + `.sh` wrapper + 严格公开校验
- `.gitattributes` 固定 `*.sh`/`*.command` 为 LF，防 CRLF 破坏 shebang
- 说明：`start-qianlima.ps1` 已用 `Invoke-QianlimaScript`（`& $Path` 同进程调用），本身即 pwsh 兼容，无需改动

## [v2.7.1] - 2026-07-13
- 公开 harness 版本号对齐 v2.7.1；补齐分层启动、运行时策略、命令安全、评估、观测、记忆卡、子代理分工与状态化 Loop 的安全模板
- 新增安全 agent harness 运行时（runtime-protocol / task-runtime）

## [v2.7.0] - 2026-07-12
- 轻量任务运行时（task runtime）：可执行运行时骨架、任务执行器、跨文件协作协议

## [v2.6.9] - 2026-07-11
- 分级响应体验（staged response）

## [v2.6.8] - 2026-07-11
- 成本控制与快速启动；浏览器任务空间治理（browser task space）

## [v2.6.7] - 2026-07-10
- QianlimaEval 评估层（来源命中率、人本审阅、首字延迟的分层评估）

## [v2.6.6] - 2026-07-09
- Obsidian vault 导出

## [v2.6.5 ~ v2.6.1] - 2026-07
- v2.6.5 LinkAI 入口 · v2.6.4 Lingma / Qoder 入口 · v2.6.3 标准成本卡
- v2.6.2 实时成本节省 · v2.6.1 压缩攻击防御

## [v2.2 ~ v2.5.1] - 2026-06 ~ 2026-07
- v2.5.x 版本迭代
- v2.4 治理框架快照（隐私已剔除）
- v2.3 Raven 风格 Agent 模板 + 主动性模块
- v2.2 Harness Engineering + 多个 SOTA 方法落地（loop-engineering、KV-cache 优化等）

## [foundation] - 2026-06-30
- 千里马 harness 基础：数据上下文层 + 广告运营日报 Agent

[v2.7.1]: https://github.com/Brian-dai694/qianlima/releases
