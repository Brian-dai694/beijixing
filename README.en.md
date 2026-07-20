# Beijixing Agent Governance Framework

[中文](README.md) · [English](README.en.md)

Beijixing is a local-first governance core for Codex, Claude Code, CodeWhale, MCP servers, Skills, and specialist Agents. It governs admission, minimum task grants, evidence, budgets, audit, revocation, and rollback without replacing the execution runtime.

## Repository layout

```text
.qianlima/              shared governance core
editions/personal/      Personal Edition manifest, configuration, docs, tests
editions/enterprise/    Enterprise Edition manifest, configuration, docs, tests
```

The editions are separate overlays. They do not copy or fork the core Harness.

- [Personal Edition](editions/personal/README.md)
- [Enterprise Edition](editions/enterprise/README.md)

Start the shared core on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\start-qianlima.ps1"
```

Validate edition separation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\.qianlima\scripts\test-edition-separation.ps1" -PassThru
```

Environment readiness never grants execution authority. Network, MCP, A2A, and business writes remain task-scoped and deny-by-default.
