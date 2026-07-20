# 问题记录：Pi / oh-my-pi Sandbox Attestation 未完成

## 基本信息

- 记录日期：2026-07-21
- 计划处理日期：2026-07-22
- 风险等级：L2
- 状态：待处理
- 负责人：北极星 Harness / Runner 治理负责人
- 关联适配器：`pi_worker`、`oh_my_pi_worker`
- 关联 Runner：`pi_omp_local_mock`

## 现象

Pi 和 oh-my-pi 已登记为 `discover_only`、`dry_run` 的 Runtime Adapter，且已登记禁用型 Runner，但影子准入结果仍为：

```text
status: pending_attestation
blocked_reason: runner_registration_requires_attestation
eligible_for_shadow_execution: true
```

系统没有真实的、任务绑定的、由隔离 Runner 产生的 `verified` Sandbox Attestation，因此不能启动 Pi/oh-my-pi，也不能进入真实影子执行。

## 影响

- Pi/oh-my-pi 目前只能完成合同准入检查，不能执行合成影子任务。
- 不能把 `pending` 候选当成 `verified` 证明。
- 不影响 Claude、Codex 或现有 dry-run 合同测试。

## 根因

`pi_omp_local_mock` 是合同型 Runner，明确设置为：

- `enabled: false`
- `execution_enabled: false`
- `network_policy: none`
- `host_workspace_mounted: false`
- `requires_attestation: true`

当前没有真实隔离提供方为具体 Work Node 和 Grant 签发可核验 Attestation。候选生成器只能写入 `status=pending`，不能自行升级为 `verified`。

## 明日处理计划（2026-07-22）

1. 选择一个合成 Work Node，确认 Work Order、Grant、Runner、Agent 和隔离目录全部严格绑定。
2. 确定可验证的隔离提供方，输出 Runner 证据：任务目录、无宿主机挂载、无网络、只读 MCP、无文件导出、策略哈希和过期时间。
3. 让 `verify-sandbox-attestation.ps1` 校验真实 Attestation；不得手工改写 `status=verified`。
4. 先运行不调用模型、不访问外部系统的合成影子任务。
5. 核对 Action Receipt、Runner Receipt、Verification Event 和 Manager Projection 的完整链路。
6. 任一边界失败时保持 `pending_attestation` 或 `blocked`，不启用 Runtime。

## 验证证据

- `.qianlima/scripts/test-pi-shadow-admission.ps1`
- `.qianlima/scripts/test-sandbox-attestation-contract.ps1`
- `.qianlima/scripts/verify-sandbox-attestation.ps1`
- `.qianlima/specifications/sandbox-attestation-contract.json`

## 当前安全结论

拒绝回归通过，说明未知 Runner、pending、过期、错任务、错 Grant 和不安全隔离条件会被拒绝。当前没有启动 Pi、oh-my-pi、Docker、MCP、模型供应商或外部写入。

## 处理完成标准

- 真实 Attestation 的 `status=verified` 可被校验器独立验证。
- Attestation 不晚于 Grant 过期，且严格绑定 Work Node。
- 合成影子任务产生完整收据和验证事件。
- Runner 仍保持无网络、无宿主机挂载、无外部写入。
