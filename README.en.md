# Beijixing Agent Governance Framework

[中文](README.md) · [English](README.en.md)

[![Version](https://img.shields.io/badge/version-v2.8.1-blue.svg)](CHANGELOG.md)

Beijixing is an enterprise Agent tiered-trust governance framework for Codex, Claude Code, CodeWhale, MCP servers, Skills, and specialist Agents. It governs admission, minimum task grants, evidence, budgets, audit, revocation, and rollback without replacing the execution runtime.

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
