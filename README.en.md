# Beijixing Agent Governance Framework

[中文](README.md) · [English](README.en.md)

[![Version](https://img.shields.io/badge/version-v2.11.1-blue.svg)](CHANGELOG.md)

Beijixing is an enterprise Agent tiered-trust governance framework for Codex, Claude Code, CodeWhale, MCP servers, Skills, and specialist Agents. It governs admission, minimum task grants, evidence, budgets, audit, revocation, and rollback without replacing the execution runtime.

## Current release and iterations

Current stable release: **v2.11.1 (2026-07-23)**

| Version | Date | Main changes | Authority impact |
|---|---|---|---|
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
