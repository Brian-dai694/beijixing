# 千里马 × AHE 中间件适配设计

> 讨论日期: 2026-06-25 | AHE 参考版本: NexAU v0.3.9
> 千里马当前基础设施: CodeWhale (DeepSeek V4 Pro) + Claude Code + MCP

---

## 1. 现状诊断：千里马已经有了什么？

### 1.1 已有资产（相当于 AHE 的"规格文档"）

| 千里马文件 | AHE 对应 | 内容 | 状态 |
|-----------|---------|------|:---:|
| `risk-rules.yaml` | RalphLoop 验证门控 | 高危操作确认规则、敏感数据脱敏 | ✅ 规格完整 |
| `context-policy.yaml` | ContextCompaction | L0-L4 压缩级别、触发条件、摘要 schema | ✅ 规格完整 |
| `workflow-index.yaml` | 实验配置 overlay | 7 个 workflow 定义、禁止操作、数据源 | ✅ 规格完整 |
| `work.ws` | 实验状态 | 当前场景、产品矩阵、指标、待办 | ✅ 实时数据 |
| `SOP-领星每日巡检框架.md` | Harbor 评测 | 11 模块日报流程、执行步骤 | ✅ 流程完整 |

### 1.2 核心差距：规格 vs 执行

```
千里马现状:
  规格文档 (YAML/MD)  →  LLM Agent 自觉遵守  →  可能忽略/遗忘

AHE 方式:
  规格文档 (YAML)     →  Middleware 强制执行  →  不可绕过
```

**关键发现**：千里马的 `context-policy.yaml` 已经定义了一套完整的压缩体系（L0-L4、触发条件、安全规则），但它**依赖 agent 在对话中自觉遵守**。而 AHE 的 `ContextCompactionMiddleware` 是在执行管线中**自动触发**的，agent 根本感知不到。

---

## 2. 适配架构总览

### 2.1 三层适配策略

```
┌──────────────────────────────────────────────────────────────┐
│ Layer 3: 框架层 (NexAU/CodeWhale 原生)                        │
│   └── 需等待 CodeWhale 支持 middleware hook 机制              │
│   └── 长期目标：将千里马迁移为 NexAU agent                     │
├──────────────────────────────────────────────────────────────┤
│ Layer 2: Hook 层 (Claude Code settings.json hooks)            │
│   └── PostToolUse hook → LongToolOutput 截断                  │
│   └── Notification hook → 飞书推送                            │
│   └── 可立即实施                                              │
├──────────────────────────────────────────────────────────────┤
│ Layer 1: Prompt 层 (CLAUDE.md / system prompt 注入)           │
│   └── RalphLoop 验证规则                                      │
│   └── Token 预算感知                                          │
│   └── Reasoning 分级                                          │
│   └── 零成本、立即可用                                        │
└──────────────────────────────────────────────────────────────┘
```

### 2.2 各中间件适配路径

| AHE 中间件 | Layer 1 (Prompt) | Layer 2 (Hook) | Layer 3 (Framework) |
|-----------|:---:|:---:|:---:|
| RalphLoop 验证门控 | ✅ 验证规则注入 | ✅ PostToolUse 拦截 | ✅ 原生中间件 |
| ToolResultCompaction | ✅ 手动压缩指令 | ⚠️ 需 Token 计数 hook | ✅ 原生中间件 |
| LongToolOutput | ✅ 输出格式规则 | ✅ PostToolUse 截断 | ✅ 原生中间件 |
| LLM Failover | ❌ Prompt 做不到 | ❌ 需 LLM 调用层 hook | ✅ wrap_model_call |
| Token 预算提醒 | ✅ 每轮注入 | ⚠️ 需 Token 计数 | ✅ before_model |
| EnvironmentInfo | ✅ 启动指令 | ✅ SessionStart hook | ✅ before_agent |
| Reasoning 分级 | ✅ scenario 配置 | ❌ 需 LLM 调用层 | ✅ llm_config |
| EmergencyCompaction | ⚠️ 依赖 agent 自觉 | ❌ 需 Token 计数 | ✅ wrap_model_call |

---

## 3. 逐组件适配方案

### 3.1 RalphLoop → 千里马"闭环验证"规则

**千里马场景映射**：

| AHE 场景 | 千里马对应 | 验证规则 |
|---------|-----------|---------|
| 代码修改后无测试 | 广告竞价修改后无效果检查 | 调价后 30min 复查曝光/点击变化 |
| 文件写入后无验证 | 飞书表格写入后无回读 | 写完后读 1 行确认落库 |
| complete_task 无检查 | 日报生成后无完整性校验 | 检查 11 模块是否全部填充 |
| — | 关键词扫描后无交叉验证 | Sorftime 结果 vs Pangolinfo 交叉比对 |
| — | Listing 修改后无前台确认 | 修改后 Kimi 打开前台页面截图 |

**Prompt 层实现**（立即可用）：

```markdown
<!-- 注入到 CLAUDE.md 或 system prompt -->

## 🔴 RalphLoop 验证门控（强制执行）

在调用 complete_task 或宣称任务完成之前，必须通过以下验证门：

### 广告操作验证
- 调价后 → 等待 15min → 复查曝光量/点击量变化
- 预算修改后 → 检查 spend 是否在预算内
- 暂停/归档后 → 确认活动状态已变更

### 数据写入验证
- 飞书表格写入后 → 读回 1 行确认数据落库
- 报告生成后 → 检查文件存在且非空

### 巡检完整性验证
- 11 模块日报 → 逐模块检查是否全部有数据（非 "N/A" 占位）
- 关键词扫描 → 9 个重点词是否全部有排名数据

### 验证失败处理
- 第 1 次失败: 修复后重新验证
- 第 2 次失败: 标注风险，记录到踩坑日志
- 第 3 次失败: 允许跳过，但在报告中标记为 🔴 盲区

验证通过后，在回复末尾列出:
```
✅ 验证通过:
  [x] 调价复查: tig-kit CPC $0.60, 曝光 +15%
  [x] 飞书回读: KW日志 9/9 行确认
  [x] 巡检完整性: 11/11 模块有数据
```
```

### 3.2 ContextCompaction → 千里马"上下文治理"自动化

**千里马场景映射**：

千里马的 `context-policy.yaml` 已经定义了完整的压缩体系，但执行靠 agent 自觉。适配目标：让压缩**自动触发**。

**当前 context-policy 中的触发条件**：
```yaml
auto_compression_triggers:
  - planned_context_ratio_above_warning_threshold  # > 60%
  - more_than_5_files_needed
  - any_file_above_direct_read_limit               # > 20KB
  - repeated_reference_to_same_large_file
  - workflow_runs_longer_than_3_steps
  - user_provides_many_documents
  - conversation_history_blocks_current_task
```

**Layer 1 适配 — 在 Prompt 中实现自动触发规则**：

```markdown
<!-- 注入到 context-policy 执行规则 -->

## 🔴 上下文压缩自动触发规则

### 触发条件（每轮 LLM 调用后自动检查）

当以下任一条件满足时，**必须先压缩上下文再继续**：

1. **Token 阈值**: 估算当前上下文 > 60% 窗口（1M × 60% = 600K tokens）
   → 触发 ToolResultCompaction: 保留最近 3 个巡检模块，旧模块工具结果替换为 "[已压缩]"

2. **文件数量**: 已读取 > 5 个文件
   → 触发 L2 摘要: 将被引用过的文件替换为结构化摘要

3. **巡检步数**: 已执行 > 3 个巡检模块
   → 触发中间摘要: 已完成的模块输出 5 句摘要（目标/结果/异常/下一步）

4. **长对话**: 超过 50 轮对话
   → 触发索引式摘要: 保留关键索引，不追求完整复述
```

**ToolResult 压缩规则（千里马场景定制）**：

```markdown
### 工具结果压缩映射

| 工具 | 压缩策略 | 保留内容 |
|------|---------|---------|
| Sorftime keyword_scan | L2 摘要 | Top 10 + Bottom 5 + 排名变化标记 |
| Pangolinfo search | L2 摘要 | 前 3 页 ASIN 位置 + 是否有竞品 |
| Kimi WebBridge snapshot | L1 提取 | 仅提取数字（销售额/订单/ACoS） |
| 飞书 sheet read | L1 提取 | 仅保留当天行 + 环比变化 |
| Shell 输出 > 5000 字符 | 头 50 行 + 尾 30 行 | 完整版路径引用 |
```

### 3.3 LongToolOutput → 千里马"数据瘦身"规则

**千里马最大痛点**：Sorftime MCP 返回 100+ 个关键词排名、Pangolinfo 返回大量 ASIN 列表。这些输出占据大量 Token 但 agent 通常只关心前几个。

**Layer 1 适配（Prompt 规则 + 工具层指令）**：

```markdown
## 🔴 工具输出截断规则

### Sorftime MCP
- 关键词排名 > 30 条时，保留 Top 20 + Bottom 10
- 中间条目显示: "... [N 个词省略，完整数据见飞书 KW日志] ..."
- SPR 数据只保留 Top 10

### Pangolinfo MCP
- 搜索结果 > 50 条时，只保留前 3 页（每页 10 条）
- 定位目标 ASIN 后，周围 5 个竞品保留，其余省略

### Kimi WebBridge
- 页面截图 → 只提取关键数字，不保留完整 HTML
- 表格数据 → 只提取和当前任务相关的列

### Shell 命令
- 长输出自动使用 `| head -50` 和 `| tail -30`
- 日志文件默认 `tail -100` 而非全量读取
```

**Layer 2 适配（Claude Code Hook — 如果要做到自动化）**：

```json
// .claude/settings.json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Sorftime|Pangolinfo",
        "hooks": [{
          "type": "command",
          "command": "python C:\\Users\\UEFR\\Desktop\\Work Space\\_scripts\\truncate_tool_output.py --tool $CLAUDE_TOOL_NAME --max-chars 5000 --input $CLAUDE_TOOL_OUTPUT"
        }]
      }
    ]
  }
}
```

### 3.4 LLM Failover → 千里马"模型降级"链

**千里马当前**：DeepSeek V4 Pro 单点。如果 DeepSeek API 故障，整个运营工作流中断。

**适配方案（配置层）**：

```yaml
# 千里马 LLM 故障转移配置
llm_failover:
  primary:
    provider: deepseek
    model: deepseek-v4-pro
    base_url: "${DEEPSEEK_BASE_URL}"
    api_key: "${DEEPSEEK_API_KEY}"

  fallback_chain:
    - provider: anthropic
      model: claude-sonnet-4-6
      base_url: "https://api.anthropic.com/v1"
      api_key: "${ANTHROPIC_API_KEY}"
      priority: 1
      use_for: [ad_ops, keyword_tracking]    # 核心场景优先

    - provider: openai
      model: gpt-4o
      base_url: "https://api.openai.com/v1"
      api_key: "${OPENAI_API_KEY}"
      priority: 2
      use_for: [sales_tracking, profit_review]  # 非实时场景

  circuit_breaker:
    failure_threshold: 3
    recovery_timeout_seconds: 300

  # 降级时的行为调整
  degraded_mode:
    keyword_scan: "reduce_frequency"     # 降低扫描频率
    ad_bid_adjust: "manual_only"         # 仅手动调价
    report_generation: "minimal"         # 最小化报告
```

**当前限制**：LLM Failover 是唯一在 Prompt 层无法实现的中间件——它需要拦截 LLM 调用本身。目前只能：
1. 在 CodeWhale 配置中预设 fallback 模型
2. 为 Claude Code 配置 API key rotation
3. 等待 CodeWhale 支持此功能（已在 AHE 中实现，理论上可移植）

### 3.5 Token 预算提醒 → 千里马"预算感知"注入

**千里马场景**：每日巡检 11 模块，一般在模块 7-8 时上下文已很满。

**Layer 1 适配**：

```markdown
<!-- 在每个巡检模块执行前自动注入 -->

## Token 预算感知规则

当前预估 Token 使用率决定行为模式：

| 使用率 | 模式 | 行为调整 |
|:---:|------|---------|
| < 30% | 🟢 充裕 | 全模块深度扫描，保留原始数据 |
| 30-60% | 🟡 正常 | 标准流程，工具结果保留 Top 15 |
| 60-80% | 🟠 紧张 | 只扫描核心 5 模块，其余产出摘要 |
| > 80% | 🔴 告急 | 只产出结论，原始数据引用飞书表格 |

### 巡检场景 Token 预算分配 (基于 1M 窗口)
- 模块 1-3 (经营+趋势+商品): 30% (300K)
- 模块 4-6 (流量+推广+流失): 25% (250K)
- 模块 7-9 (关键词+竞争+成长): 25% (250K)
- 模块 10-11 (风险+说明): 10% (100K)
- 安全保留: 10% (100K)
```

### 3.6 EnvironmentInfo → 千里马"会话自检"

**适配**：在每个新会话启动时自动探测环境。

```markdown
<!-- 千里马 Bootstrap 增强 -->

## Phase 0: 环境自检（在所有业务逻辑之前）

每个新会话启动时，自动执行：
1. MCP 连通性检查: Sorftime MCP ping → Pangolinfo MCP ping
2. 飞书 Token 有效性: lark-cli 测试读取 1 行
3. Kimi WebBridge: daemon 状态检查
4. 网络环境: api.deepseek.com / api.anthropic.com 可达性
5. 时间校准: 当前 PT 时间 vs 本地时间

输出环境状态卡片：
```
🟢 环境就绪 | PT 06:30 | DeepSeek ✓ | Sorftime ✓ | 飞书 ✓ | Kimi ✓
```

如有组件不可用，立即通知用户并启动降级方案。
```

### 3.7 Reasoning Effort 分级 → 千里马"按需深度"

**适配**：

```yaml
# 千里马场景 × Reasoning 分级配置
scenario_reasoning:
  keyword_scan:
    effort: "low"              # 简单查询，排名数字
    reason: "数据查询为主，无需深度推理"

  ad_budget_adjust:
    effort: "medium"           # 需要分析 ACoS/CVR 趋势
    reason: "需要中等推理来评估调价合理性"

  competitor_analysis:
    effort: "high"             # 多源数据交叉验证
    reason: "需要深度推理来识别竞品策略"

  profit_modeling:
    effort: "high"             # 多变量计算
    reason: "涉及成本/费用/退款等多变量核算"

  listing_optimization:
    effort: "high"             # 需要理解搜索算法
    reason: "需要深度推理来优化关键词布局"

  weekly_strategy_review:
    effort: "xhigh"            # 最高级别——策略复盘
    reason: "需要综合所有数据做战略决策"

  daily_patrol:
    effort: "medium"           # 标准巡检
    reason: "标准流程，中等推理足够"
```

---

## 4. 千里马中间件架构演进路线

### Phase 1: Prompt 引擎升级（本周，零代码）

```
目标：将所有 Layer 1 适配规则注入 CLAUDE.md 和 system prompt

产出：
├── CLAUDE.md 新增 §中间件规则
│   ├── RalphLoop 验证门控
│   ├── Token 预算感知
│   ├── 工具输出截断规则
│   └── 环境自检流程
│
├── context-policy.yaml 增强
│   ├── 自动触发规则（带具体阈值）
│   ├── 工具级压缩映射
│   └── 巡检场景 Token 预算分配
│
└── model-adapters.yaml 增强
    ├── 场景 × Reasoning 分级映射
    └── LLM Failover 配置（声明式）
```

### Phase 2: Hook 自动化（下周，少量脚本）

```
目标：将高频重复的中间件逻辑写成 Hook 脚本

产出：
├── _scripts/
│   ├── truncate_tool_output.py    # LongToolOutput Hook
│   ├── verify_patrol_complete.py  # RalphLoop 验证脚本
│   ├── env_health_check.ps1       # EnvironmentInfo 探测
│   └── context_compaction.py      # ToolResult 压缩脚本
│
└── .claude/settings.json
    ├── PostToolUse hooks
    ├── SessionStart hooks
    └── Notification hooks (飞书推送)
```

### Phase 3: 框架迁移（下月，架构升级）

```
目标：将千里马从纯 Prompt Agent 迁移为 NexAU Agent

架构变化：
  当前:  CLAUDE.md → CodeWhale/Claude Code → 执行
  目标:  code_agent.yaml + middleware/ → NexAU Runtime → 执行

收益：
  - 所有中间件原生可用（不需要 Prompt 注入）
  - 上下文压缩自动化
  - LLM Failover 原生支持
  - Harbor 评测可量化 pass@1
```

---

## 5. 关键架构决策：继续 Prompt 路线还是迁移框架？

### 方案 A：激进迁移 → NexAU Agent

```
优势:
  ✅ 8 个中间件全部原生可用
  ✅ 上下文压缩真正自动化
  ✅ LLM Failover 原生支持
  ✅ Harbor 可以量化评测千里马的 pass@1
  ✅ 实验驱动迭代（改配置 → 跑评测 → 看分数）

劣势:
  ❌ 需要重写所有工具为 Python（Sorftime/Pangolino/Kimi/飞书）
  ❌ 需要搭建 E2B 或本地沙箱
  ❌ 需要将 11 模块巡检转为 Terminal-Bench 格式的测试用例
  ❌ 学习曲线 + 迁移风险
  ❌ 当前 PD 期间不宜做大规模架构变更
```

### 方案 B：渐进增强 → Prompt + Hook 混合

```
优势:
  ✅ 零风险，不影响现有工作流
  ✅ 立即可用，PD 期间也能部署
  ✅ 保留现有工具链（Sorftime MCP / Kimi / lark-cli）
  ✅ 逐步积累中间件脚本，为未来迁移打基础

劣势:
  ❌ Prompt 规则依赖 agent 自觉遵守（不如中间件强制执行可靠）
  ❌ Token 计数不精确（依赖估算，非实际 API 返回）
  ❌ 无法做 A/B 实验（无法量化评估改动效果）
```

### 建议：B 先行，A 并行准备

```
6/25-6/26 (PD Day 3-4):
  → Phase 1 Prompt 升级（不影响 PD 运营）
  → 将验证门控规则注入当前 CLAUDE.md

6/27-7/1 (PD 后复盘周):
  → Phase 2 Hook 脚本开发
  → 用 PD 数据做第一次 Harbor 评测基准

7/2-7/15:
  → 开始 Phase 3 迁移准备
  → 将 Sorftime/Pangolino/Kimi/飞书工具封装为 Python tools
  → 将 11 模块巡检转为测试用例

7/16+:
  → 首次 AHE 实验运行
  → 目标: 巡检 pass@1 从当前水平提升到 90%+
```

---

## 6. 立即可落地的 Prompt 补丁

以下内容可直接追加到 `CLAUDE.md`，在 PD Day 3-4 立即生效：

```markdown
## 🔴 中间件规则层 (AHE-adapted, v1.0)

### M1: 闭环验证 (RalphLoop)
- 广告调价后 15min，必须复查曝光/点击变化
- 飞书写入后，必须读回 1 行确认
- 巡检结束前，必须逐模块检查完整性（11/11）
- 验证失败重试 3 次，第 3 次可跳过但标记 🔴

### M2: 工具输出瘦身 (LongToolOutput)
- Sorftime > 30 行 → 保留 Top 20 + Bottom 10
- Pangolinfo > 50 行 → 保留前 3 页
- Shell 输出 > 5000 字符 → head -50 + tail -30
- 完整数据引用飞书表格，不复制到对话

### M3: Token 预算感知 (RoundReminder)
- 巡检执行中，每完成 3 个模块评估一次 Token 消耗
- 使用率 > 60%: 精简后续模块输出
- 使用率 > 80%: 只出结论，原始数据引用源

### M4: 按需推理深度 (Reasoning Effort)
- 关键词扫描/数据查询 → 低推理
- 广告调价/Listing 优化 → 中推理
- 竞品分析/利润核算 → 高推理
- 周度策略复盘 → 最高推理

### M5: 环境自检 (EnvironmentInfo)
- 会话启动时: MCP 连通性 + 飞书 Token + 时间校准
- 任一组件不可用 → 立即通知 + 启动降级
```

---

## 附录：千里马 × AHE 概念映射表

| AHE 概念 | 千里马对应 | 说明 |
|---------|-----------|------|
| code_agent | 巡检 agent (CodeWhale + CLAUDE.md) | 被优化的"病人" |
| evolve_agent | 人工复盘 (你本人) | 目前是人在分析失败、改进 prompt |
| Harbor 评测 | 每日巡检质量评估 | 11/11 模块完成率 = pass@1 |
| Terminal-Bench | 领星 ERP 11 模块 | 标准化任务集 |
| workspace/ | CLAUDE.md + .qianlima/ | agent 配置 + 治理文件 |
| middleware/ | 本设计文档中的规则 | 中间件逻辑 |
| change_manifest | 踩坑日志 | 变更记录 + 归因 |
| ADB 分析 | 人工轨迹审查 | 目前是你自己在 debug |
| Best-of-N | 暂无 | 未来可并行尝试不同策略 |

---

> 核心洞察：千里马不需要重写——它已经有了 AHE 所需的全部"规格文档"。缺失的只是从"agent 自觉遵守"到"harness 强制执行"的自动化层。这可以通过 Prompt 增强 → Hook 脚本 → 框架迁移三步走，在不中断 PD 运营的前提下逐步实现。
