# Beijixing Enterprise Edition

The Enterprise Edition is a Beijixing product profile over the shared Qianlima core.
It does not copy or fork the main Harness. It reads the shared contracts from
the parent workspace and adds enterprise identity, approval, audit, Runner,
and deployment settings here.

## Start

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\editions/enterprise\start-enterprise.ps1'
```

Administrator deployment on a new Windows machine:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\editions/enterprise\install-enterprise-environment.ps1' -Install -AcceptDockerDesktopLicense
```

macOS/Linux:

```bash
bash 'editions/enterprise/start-enterprise.sh'
```

Administrator deployment on a new macOS machine:

```bash
bash 'editions/enterprise/install-enterprise-environment.sh' --install --accept-docker-license
```

Every Enterprise start runs the mandatory environment gate before loading the
shared core. Missing Docker, daemon health, the approved local image, Runner
registration, or platform virtualization blocks startup with remediation
details. Installation is a separate administrator action and never happens
through an ordinary user start.

## Profiles

- `edition.yaml`: Enterprise capability and deployment profile.
- `config.example.yaml`: Git-safe tenant, identity, audit, and credential references.
- `trust-policy.yaml`: Per-action continuous trust evaluation and shrink/freeze responses.
- `governance-adapter.yaml`: One adapter contract for runtime, A2A, MCP, files, network, memory, and audit interception.
- `event-contract.json`: Append-only task, Grant, Artifact, verification, revocation, and freeze events.
- `deployment-policy.yaml`: Required managed runtime and fail-closed startup policy.
- `task-level-policy.json`: Enterprise-specific L0-L4 meanings and escalation rules.
- `invoke-enterprise-task-gate.ps1`: Mechanical enterprise task classification and authorization gate.
- `test-enterprise-task-levels.ps1`: Enterprise L0-L4 risk regression suite.
- `organization-role-templates.json`: Governance roles plus scoped operations, supply-chain, finance, and product business roles.
- `user-management-policy.json`: Identity, employment, role, Agent assignment, task Grant, lifecycle, batch, and cost-attribution rules.
- `role-assignment-contract.json`: Scoped and expiring role assignment with self-approval and privileged-role controls.
- `invoke-identity-access-gate.ps1`: Offline user and role eligibility gate; it grants no runtime authority.
- `角色与用户管理指南.md`: Beginner guide for owners, managers, administrators, auditors, and employees.
- `new-enterprise-organization.ps1`: Guided company, department, and initial administrator setup.
- `组织与人员设置指南.md`: Plain-language onboarding guide for owners and employees.
- `onboarding-text.zh-CN.json`: Chinese wizard text kept outside PowerShell source for Windows 5.1 compatibility.
- `connection-policy.json`: Unified NAS, cloud drive, API, database, event, and download connection policy.
- `data-connections.example.json`: Disabled-by-default connection registry examples.
- `invoke-enterprise-connection-gate.ps1`: Mechanical connection, data class, network zone, and L4 gate.
- `test-enterprise-connections.ps1`: Connection policy regression suite without network access.
- `approval-routing-policy.json`: Responsibility, threshold, and batch approval routing.
- `five-view-task-contract.json`: Business, outcome, failure, core-issue, and handling views over one task.
- `new-five-view-task.ps1`: Creates a five-view task brief without executing anything.
- `goal-work-graph-contract.json`: Links human-owned goals to immutable work nodes, verified evidence, decision projections, and governed improvement candidates.
- `test-goal-work-graph-contract.ps1`: Offline regression for goal ownership, verified-only manager projections, and non-expanding improvement rules.
- `../.qianlima/specifications/work-node-contract.json`: P0 R&D Work Node contract: one milestone, one task-bound Grant, one runtime-independent verification result.
- `../.qianlima/specifications/action-receipt-contract.json`: Immutable, per-tool-call Action Receipt chain, including denied and frozen calls.
- `../.qianlima/specifications/manager-projection-contract.json`: Owner-facing projection derived from Broker state, verified events, receipts, and budget snapshots only.
- `../.qianlima/scripts/bind-work-node-grant.ps1`: Broker-only dispatch gate. A Work Node cannot execute before an issued, unexpired Grant is bound to it.
- `../.qianlima/scripts/verify-work-node.ps1`: Independent P0 verification gate for test results, scoped diffs, Grant validity, and receipt continuity.
- `../.qianlima/scripts/new-manager-projection.ps1`: Generates the verified-only owner report; it never exposes Agent conversation or self-reported completion.
- `../.qianlima/scripts/test-rd-p0-governance.ps1`: Read-only P0 contract regression.
- `../.qianlima/specifications/runtime-adapter-contract.json`: Runtime-neutral lifecycle boundary for Pi, oh-my-pi, Claude, Codex, and future executors.
- `../.qianlima/specifications/typed-subagent-result-contract.json`: Schema-validated subagent result boundary; child output is never verification by itself.
- `../.qianlima/specifications/artifact-precondition-contract.json`: Hash/LSP/AST/patch preconditions that reject stale or out-of-scope writes.
- `../.qianlima/specifications/nested-capability-receipt-contract.json`: Grant and trace continuity for Python, Bun, subagents, reviewer models, RPC, and ACP callbacks.
- `../.qianlima/scripts/test-pi-shadow-admission.ps1`: Read-only Pi/oh-my-pi admission preflight; it never starts a vendor process or Docker.
- `../.qianlima/specifications/sandbox-attestation-contract.json`: Separates pending metadata candidates from verified, task-bound isolation evidence.
- `../.qianlima/scripts/new-pi-omp-attestation-candidate.ps1`: Creates only a `pending` candidate; it never probes or starts Pi, oh-my-pi, Docker, or MCP.
- `../.qianlima/scripts/verify-sandbox-attestation.ps1`: Pure Runner/Work Order/Grant/expiry/isolation validator; pending candidates are rejected.
- `../.qianlima/scripts/test-sandbox-attestation-contract.ps1`: Read-only rejection regression for unknown Runner, pending, expired, and mismatched Attestations.
- `commerce-deliverable-contract.json`: Profitability, title, main image, five bullets, and long-description outcome contract.
- `new-commerce-deliverable-pack.ps1`: Creates a pending product deliverable pack without uploading or changing price.
- `commerce-operating-model.json`: Reports, plans, profit settlement, sourcing, logistics, inventory, traffic, ads, promotions, after-sales, and review lifecycle.
- `compliance-mcp-policy.json`: Tax, customs, and product-compliance MCP read/write separation.
- `invoke-compliance-mcp-gate.ps1`: Mechanical compliance MCP gate; it never calls MCP itself.
- `lingxing-business-architecture.json`: Official-document-backed Lingxing business-domain map.
- `lingxing-mcp-adapter-contract.json`: Reserved read-first MCP interface and normalized receipt contract.
- `lingxing-mcp-registry.example.json`: Disabled-by-default Lingxing MCP registration example.
- `invoke-lingxing-mcp-gate.ps1`: Mechanical future Lingxing MCP gate; it opens no network connection.
- `enterprise-mcp-platform-contract.json`: Vendor-neutral MCP governance for all enterprise tool and data servers.
- `obsidian-connector-contract.json`: Reserved Obsidian knowledge connector; selected Markdown reads only by default, with Vault references instead of raw host paths.
- `obsidian-connector-registry.example.json`: Disabled-by-default Vault registration example.
- `invoke-obsidian-connector-gate.ps1`: Offline admission gate for note scope, file type, task Grant, and L4 write separation.
- `../../.qianlima/enterprise-data-admission-contract.json`: Policy-first evidence admission; identity and Grant checks precede ranking and Top-K.
- `../../.qianlima/scripts/invoke-enterprise-data-admission.ps1`: Produces minimum sanitized Evidence Packs; external Agents receive no knowledge-search capability.
- `../../.qianlima/evidence-pack-layering-contract.json`: L0 policy context, L1 metadata, L2 sanitized chunks, and L3 just-in-time original references. Ranking occurs only after hard admission and records both selection and rejection reasons.

HiLS is used only as a governance design analogy. Enterprise Beijixing does not install or require its model checkpoints, Python/PyTorch/CUDA stack, SGLang HSA backend, or GPU training environment.
- `../../.qianlima/skill-intake-contract.json`: On-demand Skill/MCP installation intake with immutable provenance, offline static evidence, capability diff, and rescan triggers.
- `../../.qianlima/scripts/invoke-skill-intake-gate.ps1`: Returns `approved`, `conditional`, or `denied`; approval still requires human confirmation, isolated trial, and a task Grant.
- `oneskills-adapter-contract.json`: Enterprise-only OneSkills candidate overlay. Resource and expert Skills are limited to Brokered proposals; FastMCP HTTP and Streamable HTTP stay disabled.
- `invoke-oneskills-admission-gate.ps1`: Offline gate for scanned proposal input and L4 executor candidates. It never installs a Skill, starts a process, opens a listener, or dispatches a Work Order.
- `test-oneskills-admission.ps1`: Ten static/offline checks for FastMCP transport denial, evidence-pack minimization, proposal-only operation, and L4 executor preconditions.
- `open-interpreter-runner-contract.json`: Discover-only Open Interpreter Runner candidate. It defines Plan/Execute separation, task authority intersection, structured step results, command audit, and revocation without granting host access.
- `invoke-open-interpreter-gate.ps1`: Offline Plan/Execute gate. The initial release accepts only L1/L2 local read-only planning and always rejects real execution.
- `test-open-interpreter-gate.ps1`: Ten offline checks proving no process, listener, network, write, secret access, browser/ERP authority, or business verification authority is granted.
- declarative-change-plan-contract.json: Enterprise contract for current state, desired state, evidence-backed diff, plan preview, reproducible verification, and immutable revisions.
- invoke-declarative-change-plan-gate.ps1: Offline declaration gate. It validates plans without executing them; L4 plans remain human-review candidates and external writes are disabled in this release.
- `test-declarative-change-plan.ps1`: Ten offline checks for missing evidence, self-verification, replayability, L4 review, execution claims, and external-write denial.
- `enterprise-service-boundary-contract.json` and `invoke-enterprise-service-gate.ps1`: Shared UI/MCP/scheduler business-service boundary with project ownership, short-lived Grants, Secret References, and cost receipts.
- `runtime-self-check-contract.json` and `invoke-runtime-self-check-gate.ps1`: Startup, zero-priority background, and L4 preflight checks with non-destructive restore, alarms, recovery, freeze, and revocation.
- `test-source-verified-patterns.ps1`: Source-corrected offline regression for OAuth-vs-Grant separation, scheduler identity, scoped retrieval, and Apollo-style self-check recovery.

Skill Intake never runs during ordinary conversation or startup. Static scanning is defense in depth, not a sandbox. Dependency-network checks and source-code LLM review remain disabled unless separately approved for the data classification.

- `../../.qianlima/improvement-evaluation-card-schema.json`: Required evaluation card for every improvement candidate, including baseline, frozen replay, independent verification, canary scope, rollback conditions, approver, and effective version.
- `../../.qianlima/scripts/invoke-improvement-governance-pipeline.ps1`: Enterprise improvement entrypoint. It can recommend canary or rollback states but cannot release or edit production.
- `../../.qianlima/capability-execution-classification.yaml`: Classifies every current Skill and workflow as deterministic tool, on-demand knowledge, or independent delegation. Ordinary chat and same-goal follow-ups do not load runtime.
- `../../.qianlima/evaluation-templates/`: Minimum fixture, evidence, isolation, revocation, latency, and cost evaluations for the three execution classes.
- `../../.qianlima/visible-execution-event-contract.json`: Structured UI/audit events for coordinator and child state, tool confirmation, receipts, disagreements, revocation, completion, and freeze. Prompts, hidden reasoning, credentials, and raw private content are prohibited.
- `../../.qianlima/enterprise-collaboration-scale-contract.json`: Enterprise-only task, employee, department, and organization capacity gate. Capacity admission never grants execution; quota or verifier/approval backlog pauses without expanding permissions.
- `../../.qianlima/enterprise-collaboration-outcome-contract.json`: Structured decision, Claim, Evidence Receipt, uncertainty, scope, Grant, budget, approval, reversibility, and terminal status. `blocked` means evidence or prerequisites are unavailable; `failed` requires observed failure evidence.
- `../../.qianlima/scripts/validate-enterprise-collaboration-revocation.ps1`: Confirms every child Grant and direct MCP session in a collaboration has been revoked; partial confirmation keeps the whole collaboration frozen.
- `mcp-server-registry.example.json`: Disabled-by-default generic MCP Server Passport example.
- `invoke-enterprise-mcp-gate.ps1`: Generic MCP admission, version, data, budget, and write gate.
- `direct-mcp-session-contract.json`: Business-approved low-latency Agent-to-MCP session contract.
- `invoke-direct-mcp-session-gate.ps1`: Validates the short-lived session while keeping the local Connector inline.
- `employee-lifecycle-policy.json`: Joiner, Mover, Leaver, suspension, and emergency isolation policy.
- `file-organization-policy.json`: Organizes new artifacts by business, department, L0-L4, month, task, and artifact type.
- `new-enterprise-artifact-location.ps1`: Generates a governed location without moving or creating files.
- `review-compounding-policy.json`: Turns verified reviews into candidates; production promotion remains replayed, verified, and human-approved.
- `new-enterprise-review.ps1`: Creates a five-view review and lesson candidate with no production authority.
- `踩坑日志模板.md`: Plain-language pitfall and prevention log for teams.
- `test-file-review-compounding.ps1`: Offline regression for organization, review, and non-mutation boundaries.
- `deployment-mode-policy.json`: E1-E4 matrix for enterprise/BYOK API and fixed/employee-selected Agents.
- `select-enterprise-deployment-mode.ps1`: Two-question beginner selector; it grants no runtime permissions.
- `test-deployment-modes.ps1`: Offline regression for all four mappings and their hard boundaries.
- `../../.qianlima/model-portfolio.yaml`: Model Passport fields, routing tiers, evidence metrics, and trust boundaries.
- `../../.qianlima/fusion-plan-schema.yaml`: Evidence-first multi-model Fusion Plan contract.
- `../../.qianlima/scripts/validate-fusion-plan.ps1`: Validates risk, independence, data, verifier, and human-approval requirements.
- `../../.qianlima/scripts/test-model-fusion.ps1`: Offline regression for L0-L4 fusion admission.
- `new-employee-lifecycle-request.ps1`: Creates a lifecycle request without changing identity or access.
- `invoke-employee-lifecycle-gate.ps1`: Produces the mandatory revoke, handover, and recovery action plan.
- `员工增减与调岗指南.md`: Beginner guide for managers, HR, and employees.
- `test-enterprise-environment.ps1`: Read-only machine deployment preflight.
- `install-enterprise-environment.ps1`: Explicit Windows administrator deployment entrypoint.
- `install-enterprise-environment.sh`: Explicit macOS administrator deployment entrypoint.
- `start-enterprise.ps1`: Windows and PowerShell entrypoint.
- `start-enterprise.sh`: macOS/Linux launcher.
- `test-enterprise-profile.ps1`: profile contract regression test.

Real execution remains disabled until a registered Runner has a verified,
task-bound Sandbox Attestation and a separate human enablement decision.
Passing the environment gate proves deployment readiness only; it does not
grant Agent, network, MCP, file, or business-system permissions.

Enterprise L0-L4 includes organizational scope, employee and device identity,
project and cost-center ownership, Agent trust, independent verification, and
separation of duties.

For first-time setup, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File '.\editions/enterprise\new-enterprise-organization.ps1'
```

The wizard writes private organization configuration under
`.qianlima/local-data/enterprise/` and refuses to overwrite an existing file.

## Role manuals

- `企业版分层使用说明书.md`: Start here and choose a role.
- `说明书-老板.md`: Results, major risk, thresholds, and governance decisions.
- `说明书-业务负责人.md`: Projects, employee scope, MCP approval, and handling ownership.
- `说明书-员工.md`: Natural-language tasks, Agent/MCP use, outcomes, and assigned actions.

Qianlima Enterprise uses a hybrid placement model: the Broker and audit plane
run centrally in an enterprise-controlled environment; employee computers run
only the managed Connector, sandbox Runner, and local Agent. Data systems stay
in their existing zones and are reached only through configured Broker
connections. The central Broker is not exposed as a public general Agent.
