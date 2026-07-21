# 贡献指南 · Contributing

千里马是一个 **Git-safe 公开模板仓**。它只包含公开模板、治理配置、示例数据、脚本和脱敏文档。

## 铁律：不要提交隐私数据

以下内容**永远不要**进入本仓库(已在 `.gitignore` 中,提交前请再确认):

- 真实 `work.ws` / `data-sources.yaml` / `work-hub.ws` / `user-preferences.yaml`
- token、账号、API key、客户信息、供应商联系方式
- 真实 ASIN 运营数据、成本台账、利润数据
- 运行报告、运行日志、usage-ledger、截图、本地绝对路径

提交前必须运行公开安全校验:

```powershell
pwsh -NoProfile -File "./.qianlima/scripts/verify-qianlima.ps1"
```

`Issues: 0` 才可提交;`WARN: Private local file exists` 是提醒你确认这些文件已被忽略,不是错误。

## 开发流程

1. `start-qianlima.ps1` 生成工作区索引
2. 按 `AI_START_HERE.md` 读取启动包,不要一次性读整个工作区
3. 改动只针对公开模板层;高危动作(改价/预算/删除/外发)默认被运行时策略拦截
4. commit 前跑 `verify-qianlima.ps1`;CI(`.github/workflows/qianlima-verify.yml`)会复跑校验 + 高危动作负测试

## 跨平台脚本标准

北极星的共享自动化统一以 PowerShell 7 (`pwsh`) 为主执行层，并同时支持 Windows、macOS 和 Linux。

- 共享逻辑使用 `.ps1`；`.sh` 只作为 macOS/Linux 薄启动包装，不复制治理逻辑。
- 不硬编码 `powershell.exe`、盘符、反斜杠路径或固定安装目录。子进程优先复用当前 PowerShell Host。
- 文件路径使用 `Join-Path`、`Resolve-Path` 和仓库相对路径；命令参数使用 `-LiteralPath` 处理空格与特殊字符。
- 必须依赖操作系统能力的行为放入平台适配器，并保持相同输入、输出、失败状态和审计字段。
- 不通过关闭 TLS 校验、写入明文 Token 或放宽权限来解决平台差异。
- Windows 与 macOS GitHub Actions 必须同时通过；任一平台失败都不得视为可发布。

## 文档导航

| 用途 | 文件 |
|---|---|
| AI/Agent 通用入口 | `AI_START_HERE.md` |
| 项目总览 | `README.md` |
| 各 Agent 专用入口 | `CLAUDE.md` · `AGENTS.md` · `MANUS.md` · `QODER.md` · `LINGMA.md` · `LINKAI.md` · `OBSIDIAN.md` · `DESKTOP_AGENT_BRIEF.md` |
| 标准/规范 | `Work Scenario Governance Spec 工作场景治理标准.md` · `Data Connector Spec 数据连接器标准.md` |
| 设计/融合说明 | `AHE 借鉴清单与千里马适配方案.md` · `AMZ-EVO 简单版融合说明.md` · `NotebookLM 融合说明.md` · `PWE-v2.0个人使用版-治理方案.md` |
| 合并到大模型 | `如何把千里马计划合并到大模型.md` |

## 提交信息约定

沿用现有风格:`feat:` / `fix:` / `docs:` / `chore:` / `Release vX.Y.Z ...`。

## License

贡献即表示同意以 [MIT License](LICENSE) 授权。
