# Beijixing Agent Governance Framework

[中文](README.md) · [English](README.en.md)

[![Version](https://img.shields.io/badge/version-v2.11.0-blue.svg)](CHANGELOG.md)

Beijixing is an enterprise Agent tiered-trust governance framework for Codex, Claude Code, CodeWhale, MCP servers, Skills, and specialist Agents. It governs admission, minimum task grants, evidence, budgets, audit, revocation, and rollback without replacing the execution runtime.

## Current release and iterations

Current stable release: **v2.11.0 (2026-07-22)**

| Version | Date | Main changes | Authority impact |
|---|---|---|---|
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
