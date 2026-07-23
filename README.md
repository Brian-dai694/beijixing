# 北极星 Agent 治理框架

[中文](README.md) · [English](README.en.md)

[![CI](https://github.com/Brian-dai694/beijixing/actions/workflows/qianlima-verify.yml/badge.svg)](https://github.com/Brian-dai694/beijixing/actions/workflows/qianlima-verify.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v2.12.0-blue.svg)](CHANGELOG.md)

北极星是企业版 Agent 分级信任治理框架。它不是通用 Agent，也不替代 Codex、Claude Code、CodeWhale、MCP 或专业 Skill；它决定谁能做什么、能看到什么数据、预算多少、结果如何核验，以及何时撤销、冻结或回滚。

> 任何接入的 Agent，都必须经过准入、最小授权、证据核验、预算约束、审计与可撤销控制。

## 当前版本与迭代

当前稳定版本：**v2.12.0（2026-07-23）**

| 版本 | 日期 | 核心变化 | 权限影响 |
|---|---|---|---|
| `v2.12.0` | 2026-07-23 | 新增统一 Tool Risk Level 和专业工具 Profile：只读、分析、修改、调试/内存写入分级，强制资源绑定、审批预览、证据回执和会话撤销 | 不扩权；`reverse-debug` 当前版本默认拒绝，`reverse-edit` 只生成待确认计划 |
| `v2.11.1` | 2026-07-23 | 新增 API 最小权限门禁：本地 Secret Reference、请求字段/写入 Body 白名单、响应投影、脱敏交叉核验和成本未知阻断 | 不扩权；Agent 不接触密钥值、全量后台或原始请求体，真实 API 调用仍由 Broker 控制 |
| `v2.11.0` | 2026-07-22 | 源码级纠正三仓定位；新增 Service/Repository/MCP 边界、定时任务独立身份、三档非破坏性自检，以及授权前热元数据/冷证据检索 | 不扩权；OAuth 不替代 Grant，自检不写生产，SPDK/NVMe 不接入 |
| `v2.10.0` | 2026-07-22 | 新增北极星内部声明式变更计划：当前态、目标态、差异、Plan Preview、证据包和可复算核验；原三仓来源归因已在 v2.11.0 纠正 | 不扩权；L4 仅候选待人工审核，外部写入仍禁用 |
| `v2.9.2` | 2026-07-22 | 建立 Windows/macOS/Linux 跨平台脚本标准；新增 Open Interpreter 企业 Runner Contract、Plan/Execute 门禁和离线回归 | 不扩权；Runner 未安装，真实 Execute 继续禁用 |
| `v2.9.1` | 2026-07-21 | 修复 macOS 命令安全回归和 Usage Ledger 序列化 | 不扩权；Pi / oh-my-pi 保持仅发现模式 |
| `v2.9.0` | 2026-07-21 | 增加子委派、Work Node、Action Receipt、Manager Projection，以及受治理的 Runtime 影子准入 | 不授予生产执行权；高风险动作仍需 Grant、核验与审批 |

完整发布记录、升级边界与历史版本见 [CHANGELOG.md](CHANGELOG.md)。
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

## API 与隐私边界

企业版不把 API 整体开放给 Agent。业务负责人只为每个 Provider 配置允许读取的字段、允许写入的 Body 字段、响应投影和数据范围；未列出的字段默认拒绝。

私密配置只放在本机 `.qianlima/local-data/enterprise/api-access.local.yaml` 或批准的 Secret Manager 中，公开仓库只保存 `secretref:env/...`、`secretref:os/...` 等引用。Agent、Prompt、审计日志和核验模型都不能看到密钥值；员工也不需要把密钥粘贴到对话框。

多 AI 交叉验证不是权限控制。需要核验时，北极星先做密钥/个人信息/作用域/字段扫描，再只给核验模型脱敏 Claim Pack 和 Evidence Reference；原始 API Body、凭据、全量后台数据不会发送给任何模型。验证结果只能影响 `approved / needs_human / frozen` 结论，不能增加 API 权限。

写入请求必须经过字段白名单、L4 Grant、负责人批准、二次确认、预检快照、幂等键、回滚引用和事后核验；默认仍是只读和计划模式。

## 专业工具治理

所有专业工具统一使用 `R0` 只读查询、`R1` 分析推理、`R2` 修改、`R3` 调试/内存写入四级风险。工具不是按单个 Agent 自由开放，而是通过 `reverse-readonly`、`reverse-triage`、`reverse-edit`、`reverse-debug` 等 Profile 能力包授予，并且每次调用必须绑定租户、项目、产物、会话、任务、Grant、设备、工具版本和清单哈希。

当前版本中，R0/R1 只允许选定资源的有限读取和分析；R2 只能生成补丁/重命名/类型变更计划，执行前必须有人工审批、预检快照、回滚引用和事后验证；R3 的调试器、进程附加、任意代码、内存写入和 `py_eval` 默认拒绝。

每次调用都要形成证据回执，记录样本哈希、工具版本、参数摘要、观察、模型主张、地址/函数/字符串引用、差异、验证状态、审批引用和撤销时间。进程、工作目录、调用次数、运行时间和输出大小独立受限，Grant 过期、版本漂移、超时、预算耗尽或越界后立即撤销并拒绝后续调用。

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
