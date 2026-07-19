# A2A 消息与协作研究笔记 (Research Note)

> 状态：research / 未进入实现。本笔记只定方向与权衡，不改动运行时代码。
> 关联：[[a2a-adoption-roadmap]]、`a2a-compatibility.yaml`、`delegation-grant-schema.yaml`、`a2a-task-state.yaml`。
> 约束：不装任何软件、不开网络监听；一切结论必须在 Phase 0/1（`internal_contract_only`）内可验证。

## 1. 目的

北极星已有完整的 A2A **治理契约与门禁**。本笔记回答的不是"要不要做 A2A"，而是：
在"禁止 Agent 直连、一切回 Broker 重新授权"的前提下，**多 Agent 通信与协作**应当如何建模，
以及先补哪些地基才能让后续实现不返工。

## 2. 现状评估（诚实版）

已具备（扎实）：
- A2A 1.0 语义映射与任务状态机；`network_dispatch_enabled: false` 硬关，default-deny。
- `preflight-a2a-client.ps1` dry-run；`test-a2a-dispatch-gate.ps1` 抛异常拦截。
- delegation-grant schema（任务级、限时、可撤销、`can_delegate` 默认 false）。
- artifact 哈希血缘、run/artifact receipt、context 隔离。
- Phase 1 本地 mock 打通"信封校验 → 产出带哈希 artifact → 回执"。

尚不存在（需明确）：
- **真正的通信**。`invoke-a2a-local-mock.ps1` 是契约校验器 + 回执生成器，
  远端 agent 不推理、不产内容。它证明的是**管道**（不可变、哈希血缘、context 不串），
  不是**对话**（多轮、流式、真委派工作）。门禁守着一扇尚未修路的门——这符合当前阶段。

结论：A2A 作为"能跑的通信能力"目前为零；价值在于把强策略与真实执行之间的缺口补齐。

## 3. 四个核心研究问题

### Q1. Broker 中介 vs 直连——中心命题

平台立场：禁止 A2A 直连，一切回 Broker 重新授权。安全上正确，但每条消息都往返
Broker 会造成瓶颈、单点上下文和成本放大。

- 权衡点：**安全/可审计** ↔ **延迟/成本/可用**。
- 候选方向：一次签发**限时、限工具、限预算、可撤销**的 delegation grant（schema 已支持），
  让子 Agent 在 grant 有效期内做有界调用而不逐条回 Broker；Broker 仍持有签发/撤销/审计三权。
- 关键不变量：grant 是"预授权信封"而非"直连许可"；消息仍写入可审计的 append-only 事件流，
  Broker 事后可回放、可随时撤销收缩。
- 判据：能否在不逐条往返的前提下，仍满足 receipt 完整性与"失败即收缩授权"。

### Q2. `can_delegate` 与 `direct_agent_to_agent: prohibited` 的语义冲突（先澄清，再实现）

`delegation-grant-schema.yaml` 有 `can_delegate`（默认 false），
`a2a-compatibility.yaml` 又写死 `direct_agent_to_agent: prohibited`。二者字面矛盾。

- 建议定义：`can_delegate = true` 仅表示"可**经 Broker**发起子委派"，
  **绝不**表示"可直接对话另一 Agent"。
- 落点：在 compatibility 或 grant schema 的 `invariants` 里补一条显式说明，
  并规定子委派必须生成**新 grant + 新 task_id + 引用父 task**，权限取父 grant 的**交集且只能更小**。
- 不澄清的后果：后续实现者会把 `can_delegate` 误解为直连开关，直接击穿核心立场。

### Q3. 不可变任务 vs 多轮协作

现模型："一个不可变 work order → 一个 artifact"，refinement 开新 task_id
（`terminal_task_immutable: true`）。真正协作需要会话线程、流式状态、部分结果。

- 建议分层：引入 **conversation/context 作为 task 的容器**；task 仍不可变，
  conversation 负责串联多个不可变 task 与其 artifact（`context_id` 已具雏形）。
- 流式：映射到现有 `working` 状态 + 周期性 status 事件，**不**改变 task 终态语义。
- 部分结果：用 `partial`（internal_only）承载，晋升为 `completed` 时冻结并生成 artifact。

### Q4. 可复现性被 mock 自己破坏（与 Phase 1 exit gate 冲突）

roadmap Phase 1 exit gate 要求 "replayable"，但 `invoke-a2a-local-mock.ps1`
在 artifact 里写 `Get-Date` 时间戳，而哈希对整个文件计算——同一信封重跑两次哈希不同，
replay 确定性验证过不了。

- 建议：把时间戳等非确定字段移出**参与哈希的规范化载荷**（canonical payload），
  哈希只覆盖语义内容；时间戳留在 receipt 元数据里、不进 artifact 哈希。
- 或：mock 支持 `-DeterministicClock` / 固定时钟注入，供 replay 用例使用。

## 4. 顺带记录的执行层缺陷（实现阶段一并修）

| 位置 | 问题 | 建议 |
|---|---|---|
| `scripts/test-a2a-dispatch-gate.ps1` | `risk_ceiling -gt` 是字符串比较，L0-L4 恰好字典序也对但脆弱，且与 `qianlima-context-fast.ps1` 的 `$contextRank` 数值 rank 不一致 | 统一用数值 rank 哈希表比较 |
| `scripts/invoke-a2a-local-mock.ps1` | 两处硬编码 `powershell.exe` 起子进程生成回执，macOS/pwsh 上无此可执行；且是纯管道进程开销 | 复用 `Get-PowerShellExecutable` 或 dot-source 同进程 |
| `a2a-compatibility.yaml` / grant schema | Q2 语义冲突 | 见 Q2 |
| `scripts/invoke-a2a-local-mock.ps1` | Q4 哈希含时间戳破坏 replay | 见 Q4 |

## 5. 建议推进顺序

1. **先补地基**：Q2 语义澄清 + Q4 可复现性。二者是后续一切的前提，改动小、风险低。
2. **正题研究/原型**：Q1 grant 驱动的低往返委派——最有研究价值，决定架构走向。
3. **协作模型**：Q3 conversation 容器，在 Q1 定型后再落。
4. Phase 2 网络传输**暂不动**：门禁已就位，路等地基稳了再修。

## 6. 不变红线（研究与实现都不得触碰）

- A2A Agent Card 是发现元数据，永不是权限。
- 外部/被委派 Agent 永不获得 L4 执行权。
- 终态任务不可变；refinement 开新 task 引用旧 artifact。
- A2A 传输不替代 MCP、risk-rules、command-safety、人工确认。
- 失败默认撤销并收缩授权，永不扩权。
