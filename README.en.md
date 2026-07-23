# Beijixing Agent Governance Framework

[中文](README.md) · [English](README.en.md)

[![Version](https://img.shields.io/badge/version-v2.14.0-blue.svg)](CHANGELOG.md)

Beijixing is an enterprise Agent tiered-trust governance framework for Codex, Claude Code, CodeWhale, MCP servers, Skills, and specialist Agents. It governs admission, minimum task grants, evidence, budgets, audit, revocation, and rollback without replacing the execution runtime.

## Current release and iterations

Current stable release: **v2.14.0 (2026-07-23)**

| Version | Date | Main changes | Authority impact |
|---|---|---|---|
| `v2.13.0` | 2026-07-23 | Makes ETCLOVG a seven-layer acceptance matrix and adds readable-workflow plus machine-policy Task Runtime Specs with a bounded Meta-Harness candidate gate | No authority expansion; a spec is not a Grant, L4 remains a human candidate, and candidates cannot auto-edit governance core controls |
| `v2.12.0` | 2026-07-23 | Adds unified Tool Risk Levels and professional-tool Profiles for read, analysis, modification, and debug/memory-write capabilities, with resource binding, approval previews, evidence receipts, and revocation | No authority expansion; `reverse-debug` is denied in the current release and `reverse-edit` produces confirmation-bound plans only |
| `v2.11.1` | 2026-07-23 | Adds API least-privilege gates: local Secret References, request/body field allowlists, response projections, sanitized cross-validation, and unknown-cost blocking | No authority expansion; Agents never receive secret values, full back-office access, or raw request bodies, and Broker control remains mandatory |
| `v2.11.0` | 2026-07-22 | Corrects all three repository mappings from source; adds Service/Repository/MCP boundaries, independent scheduler identity, three non-destructive self-check tiers, and authorization-first hot-metadata/cold-evidence retrieval | No authority expansion; OAuth never replaces a Grant, self-checks never write production, and SPDK/NVMe are not adopted |
| `v2.10.0` | 2026-07-22 | Adds Beijixing internal declarative change plans with current state, desired state, diffs, Plan Preview, evidence packs, and reproducible verification; the prior external-source attribution is corrected in v2.11.0 | No authority expansion; L4 is human-review candidate only and external writes remain disabled |
| `v2.9.2` | 2026-07-22 | Adds the Windows/macOS/Linux scripting standard and the governed Open Interpreter Runner contract, Plan/Execute gate, and offline regression | No authority expansion; the Runner is not installed and real Execute remains disabled |
| `v2.9.1` | 2026-07-21 | Fixes macOS command-safety regression and Usage Ledger serialization | No authority expansion; Pi / oh-my-pi remain discover-only |
| `v2.9.0` | 2026-07-21 | Adds governed sub-delegation, Work Nodes, Action Receipts, Manager Projection, and shadow Runtime admission | No production execution authority; high-risk actions still require a Grant, verification, and approval |

See [CHANGELOG.md](CHANGELOG.md) for the complete release history and upgrade boundaries.
## Repository layout

```text
.qianlima/              enterprise governance core
editions/enterprise/    Enterprise Edition manifest, configuration, docs, tests
```

This repository publishes the [Enterprise Edition](editions/enterprise/README.md) only. The Enterprise overlay does not copy or fork the core Harness.

Start the shared core on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\start-qianlima.ps1"
```

Validate the enterprise profile and identity governance:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\editions\enterprise\test-enterprise-profile.ps1" -PassThru
powershell -NoProfile -ExecutionPolicy Bypass -File ".\editions\enterprise\test-identity-access-governance.ps1" -PassThru
```

Environment readiness never grants execution authority. Network, MCP, A2A, and business writes remain task-scoped and deny-by-default.

## API and Privacy Boundary

Enterprise Beijixing never exposes an entire API to an Agent. Each provider has explicit readable fields, writable body fields, response projections, and data scopes; anything not listed is denied.

Private configuration stays in `.qianlima/local-data/enterprise/api-access.local.yaml` or an approved Secret Manager. The public repository contains only references such as `secretref:env/...` and `secretref:os/...`. Secret values are hidden from Agents, prompts, audit logs, and verifier models, so employees do not paste credentials into chat.

Multi-model cross-validation is not an authorization mechanism. Before verification, Beijixing scans for secrets, personal data, scope violations, and field violations, then sends only a sanitized Claim Pack and Evidence References to the verifier. Raw API bodies, credentials, and full back-office data are never sent to a model. Verification can produce `approved`, `needs_human`, or `frozen`, but cannot expand API access.

Writes require field allowlists, an L4 Grant, responsible approval, second confirmation, a preflight snapshot, an idempotency key, rollback reference, and post-change verification. Read-only and plan modes remain the default.

## Professional Tool Governance

All professional tools use four shared risk levels: `R0` read-only query, `R1` analysis, `R2` modification, and `R3` debugging or process-memory write. Tools are exposed through bounded Profiles such as `reverse-readonly`, `reverse-triage`, `reverse-edit`, and `reverse-debug`, not through free-form Agent tool access. Every call binds tenant, project, artifact, session, task, Grant, device, tool version, and manifest hash.

R0/R1 are limited to selected-resource reads and analysis. R2 produces patch/rename/type-change plans only and requires human approval, preflight, rollback, and post-change verification before execution. R3 debugger attach, arbitrary code, process-memory writes, and `py_eval` are denied in this release.

Every call produces an evidence receipt containing the sample hash, tool version, parameter digest, observations, model claims, source locations, diff, verification status, approval reference, and revocation time. Process, workspace, call-count, runtime, and output limits are enforced independently; expiry, drift, timeout, budget exhaustion, or overreach revokes the session and denies the next call.

## ETCLOVG and Task Runtime Specs

Execution, Tooling, Context, Lifecycle, Observability, Verification, and Governance are mandatory production acceptance dimensions. A missing dimension blocks release; Agent self-report, prompt promises, and invented metrics are not mechanical evidence.

A Task Runtime Spec has two layers. The readable layer explains the goal, capability profile, data scope, budget, state machine, confirmation points, evidence, and failure handling. The machine layer enforces identity, Grants, tool allowlists, sandbox attestation, data classification, budget, approval, audit, and revocation. A readable spec may narrow but never widen machine policy.

Harness improvements remain candidates through static checks, frozen replay, quality/latency/cost/risk scoring, independent verification, human review, canary, and monitoring. Risk, approval, audit, secret, Grant, data-classification, and production configuration controls cannot be automatic modification targets.

## Enterprise Intelligence Maturity

Enterprise tasks continue to use `L0-L4` for action risk. Capability maturity is separate and uses `C/R/A/I/O`; neither scale can be inferred from the other:

```text
C Conversation: understand and respond to a person
R Reasoning: produce checkable, evidence-backed analysis
A Agent: complete a bounded task with tools
I Innovation: propose hypotheses, test them, seek counterexamples, revise, and produce replayable work
O Organization: sustain coordination among people, Agents, data, rules, and responsibility
```

`I` is not a stack of multimodality, multi-Agent systems, reinforcement learning, chain-of-thought, or simulation; its minimum proof is an experiment and counterexample loop. `O` is not a synonym for super-alignment; its minimum proof is a shared business world model, authority and responsibility, human-Agent handoffs, budget governance, versioned cross-task memory, audit review, and policy updates. An ontology is an object and constraint layer, not proof of truth or completed governance.

Maturity claims must declare `publicly_verified`, `enterprise_verified`, `hypothesis`, or `unverified_claim`. Verification and governance are cross-cutting gates; no technology combination may expand a Grant or self-declare a higher maturity. Contract: `editions/enterprise/enterprise-intelligence-maturity.json`.
