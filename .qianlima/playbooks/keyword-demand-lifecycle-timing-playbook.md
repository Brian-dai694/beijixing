# 关键词三层需求 + 竞争格局 Playbook（SIF 优先版）
# 版本: v0.3 | 更新: 2026-07-02
# 变更: SIF MCP 接入，四层全部从代理/估算升级为 SIF 真值

目标：优先用 SIF MCP 四件套做关键词需求+竞争分析，Sorftime/Pangolinfo/Google Trends 仅做降级。

## SIF 优先执行链

### 1. 需求量化层
```
mcp__sif__market_get_keyword_history(keywords, country, granularity=week)
```
返回：ABA 搜索量 / ABA 排名 / Top3 点击集中度 / Top3 转化集中度 完整历史时序
- 1-10 个关键词一次调用
- 直接拿到的 latest.volume / latest.rank / latest.top3_click_share / latest.top3_conversion_share 是 ABA 真值
- 不再需要 Sorftime keyword_detail（标"非 ABA"）和 SERP 密度估算

判断信号：
- 转化集中度 >> 点击集中度 → 品牌黏性极强，用户心智已被占领
- latest.rank=0 → 该词当前未进入 ABA 排名，搜索量可能较低或数据暂缺

### 2. 需求边界层
```
mcp__sif__market_get_keyword_root_trend(keyword, country, granularity=week)
```
返回：精确词搜索量时序 + 词根综合搜索量时序 + coverage_ratio
- 只接受单个关键词
- coverage_ratio > 0.8 = 需求集中；0.4-0.8 = 各占一部分；< 0.4 = 高度分散
- 精确词量下降但 ext 平稳/上升 = 需求转移到长尾
- 同步下降 = 品类萎缩

不再需要 keyword_extends 数量 + Google Trends 粗估 coverage_ratio。

### 3. 需求判断层
```
mcp__sif__market_get_keyword_demand(keywords, country)
```
返回：
- profiles[] 每词一个，含 diagnosis / interpretation / current_phase / weeks_to_peak / action_hint / seasonal_strength
- timing_summary[] 按 weeks_to_peak 升序排列
- diagnosis 标签：growing / peaking_reversing / recovering / recent_weakening / mature_stable / seasonal_dip / structural_declining / insufficient_data
- action_hint 直接给行动建议（进场/加速/收割/收缩/数据不足）

不再需要 Google Trends 自算 YoY / annual_decay / momentum / seasonality。
Agent 只负责透传 SIF 的 diagnosis 和 action_hint，不做二次推断。

### 4. 竞争格局
```
mcp__sif__market_get_keyword_competition(keyword, asin?, country, rank_evolution=true)
```
返回：
- competition_position (dominant/defending/advancing/stalled/opportunity/challenging/blocked/displaced)
- concentration_profile.{level, trend.divergence, leader_diverge, efficiency_leader.reliable}
- top_asins[].{asin, natural_ratio, sp_ratio, brand_ratio, video_ratio, total_share, competition_mode}
- demand_snapshot.interpretation
- market_context.{is_branded_keyword, recommended_ad_focus, rationale}
- system_state.{可进入性, 可沉淀性, 可持续性}
- supply_profile.total_asin_trend
- my_position.key_insight (当提供 asin)

不再需要 SERP 推理 competition_position。
natural_ratio / sp_ratio / brand_ratio / video_ratio 是 SIF 真值，不再标 proxy。

关键信号：
- concentration_profile.trend.divergence = diverging → 最佳机会信号
- efficiency_leader.reliable = false → Top3 之外仍有机会
- conversion_gap = true → Top3 拿走点击但未赢得转化，强产品有切入机会

## 自动编排

### 全链路（用户问"这个词值不值得做"）
demand_data → demand_judgment → competition
（demand_boundary 只在用户问"总盘子"/"分散度"时调，因为只接受单个词）

### 从 traffic_anomaly 进入
触发条件：analyze_traffic_anomaly 的 conclusion 包含 competitor_displacement / seasonal_demand_drop / market_demand_decline
执行顺序：
1. demand_judgment（确认需求是否在萎缩）
2. competition（确认竞品是否在取代）
3. demand_data（出原始数字做证据）

### 关键词信号优先
触发条件：用户提供 ASIN 但不确定看哪些词
执行顺序：
1. market_get_asin_keyword_signals（先找 at_risk / declining 词）
2. demand_judgment（对 at_risk 词判断需求生命周期）
3. competition（对 top traffic_share 词评估竞争格局）

## 降级方案

### demand_data 降级
Sorftime keyword_detail + keyword_trend（标"站内搜索量，非 ABA"）+ Pangolinfo search_amazon（SERP Top3 密度代理）

### demand_boundary 降级
Sorftime keyword_extends + Pangolinfo keyword_trends（标"estimation"）

### demand_judgment 降级
Pangolinfo keyword_trends 自算 YoY / 季节性 / 动量（标"proxy，Google Trends 相对热度"）

### competition 降级
Pangolinfo search_amazon + Sorftime product_search + get_amazon_product（标"proxy，SERP 推理"）

## SIF 模式 vs 降级模式 标注规则

| 字段 | SIF 模式 | 降级模式 |
|---|---|---|
| 搜索量 | 标 "ABA" | 标 "站内搜索量，非 ABA" |
| 排名 | 标 "ABA rank" | 标 "不可获取" |
| Top3 点击集中度 | 标 "ABA" | 标 "SERP 密度代理" |
| Top3 转化集中度 | 标 "ABA" | 标 "不可获取" |
| coverage_ratio | 标 "SIF 真值" | 标 "估算" |
| diagnosis | 标 "SIF" | 标 "Google Trends 自算 proxy" |
| action_hint | 标 "SIF" | 标 "proxy" |
| competition_position | 标 "SIF 数据驱动" | 标 "推理，无 SIF 验证" |
| natural/sp/brand/video ratio | 标 "SIF 真值" | 标 "不可获取" |
| system_state | 标 "SIF" | 标 "推理" |
