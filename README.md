# 北极星 Agent 治理框架

[中文](README.md) · [English](README.en.md)

[![CI](https://github.com/Brian-dai694/beijixing/actions/workflows/qianlima-verify.yml/badge.svg)](https://github.com/Brian-dai694/beijixing/actions/workflows/qianlima-verify.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v2.9.0-blue.svg)](CHANGELOG.md)

北极星是企业版 Agent 分级信任治理框架。它不是通用 Agent，也不替代 Codex、Claude Code、CodeWhale、MCP 或专业 Skill；它决定谁能做什么、能看到什么数据、预算多少、结果如何核验，以及何时撤销、冻结或回滚。

> 任何接入的 Agent，都必须经过准入、最小授权、证据核验、预算约束、审计与可撤销控制。

## 仓库结构

```text
北极星/
├─ .qianlima/              企业治理核心与合同
├─ editions/
│  └─ enterprise/          企业版清单、配置、文档和测试
├─ start-qianlima.ps1      Windows 核心启动入口
├─ start-qianlima.sh       macOS/Linux 核心启动入口
└─ repository-layout.json  企业版仓库合同
```

适合员工、部门和多 Agent 协作。增加组织身份、设备、任务 Grant、企业数据准入、MCP 治理、职责分离、审批路由、审计、灰度和回滚。

查看 [企业版说明](editions/enterprise/README.md)、[分层使用说明书](editions/enterprise/企业版分层使用说明书.md) 和 [角色与用户管理指南](editions/enterprise/角色与用户管理指南.md)。

## 启动企业治理核心

Windows：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\start-qianlima.ps1"
```

macOS/Linux：

```bash
bash ./start-qianlima.sh
```

企业版环境检查与启动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\editions\enterprise\test-enterprise-environment.ps1" -PassThru
powershell -NoProfile -ExecutionPolicy Bypass -File ".\editions\enterprise\start-enterprise.ps1"
```

环境就绪不等于获得执行权限。真实网络、MCP、外部 A2A 和业务写入仍需任务级 Grant 与相应审批。

## 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\editions\enterprise\test-enterprise-profile.ps1" -PassThru
powershell -NoProfile -ExecutionPolicy Bypass -File ".\editions\enterprise\test-identity-access-governance.ps1" -PassThru
```

## 安全默认

- Agent Card 和 Skill 声明不是授权。
- 默认无网络、无写入、无全局 MCP、无 Agent-to-Agent 直连。
- 外部 Agent 只能接收任务选择后的脱敏最小证据包。
- Skill/MCP 安装或更新必须经过 Intake Gate。
- 改进只能生成候选；回放、独立验证、人工批准和灰度通过后仍只形成发布候选。
- 私有数据、凭据、运行轨迹、账本和本地偏好由 `.gitignore` 排除。

许可证见 [LICENSE](LICENSE)。

