# work.example.ws — 工作状态总索引（脱敏模板）
# 复制此文件为 work.ws 并填入真实数据
# Harness v2.2 | 千里马计划

workspace:
  id: amazon_ops_enterprise
  name: 亚马逊运营工作台
  owner: current_user
  mode: enterprise
  root: "<YOUR_WORKSPACE_PATH>"
  created: "<YYYY-MM-DD>"
  updated: "<YYYY-MM-DD>"

status:
  overall: active
  health: green
  last_patrol: "<YYYY-MM-DD>"
  last_report: "<最近报告路径>"
  last_keyword_report: "<最近关键词报告路径>"
  context_policy: enabled
  harness_version: v2.2
  harness_health: green

current_focus:
  primary_scenario: ad_ops
  active_event: null
  active_projects: []
  attention_required: []

scenarios:
  - id: ad_ops
    name: 广告运营
    priority: high
    status: active
    frequency: daily
    core_metrics: [spend, sales, orders, acos, cpc, cvr, tacos]
    workflows: [daily_ad_report]
    data_sources: [lingsing_ads]
    risk_level: medium

  - id: sales_tracking
    name: 销量台账
    priority: high
    status: active
    frequency: daily
    workflows: [sales_ledger]
    data_sources: [lingsing_product, lark_asin_sales]

  - id: keyword_tracking
    name: 关键词排名追踪
    priority: high
    status: active
    frequency: daily
    keywords: [<YOUR_KEYWORDS>]
    workflows: [keyword_rank_scan]
    data_sources: [sorftime_mcp, pangolinfo_mcp, kimi_webbridge]
    last_scan: "<YYYY-MM-DD>"

  - id: inventory_monitor
    name: 库存预警
    priority: high
    status: active
    frequency: daily
    workflows: [inventory_alert]

  - id: profit_review
    name: 利润复盘
    priority: medium
    status: active
    frequency: weekly

  - id: product_selection
    name: 选品分析
    priority: low
    status: paused

  - id: knowledge_digest
    name: 资料消化
    priority: low
    status: active

# ⚠️ 隐私: 以下为示例数据，请替换为你自己的产品信息
products:
  active:
    - {asin: "<YOUR_ASIN>", sku: "<YOUR_SKU>", name: "<产品名>", price: 0.00, margin: 0.0, inventory: 0, stage: growth}
  clearance:
    - {asin: "<YOUR_ASIN>", sku: "<YOUR_SKU>", name: "<产品名>", price: 0.00, margin: 0.0, inventory: 0, stage: clearance}

annual_targets:
  net_sales: 0
  net_profit_rate: 0.0
  breakeven: 0
  ytd_actual: 0
  jun_target: 0
  jul_target: 0
  ad_budget_monthly: 0

reports_generated: []

harness_evolution:
  inspiration:
    - "Lilian Weng — Harness Engineering for Self-Improvement (2026-07-04)"
    - "机器之心 SOTA: loop-engineering / memgovern / nemo-skills / alembic / gdpo / marshal / celery"
  version: v2.2
  last_optimization: "<YYYY-MM-DD>"

context_governance:
  policy_file: context-policy.yaml
  summary_folder: context-summaries
