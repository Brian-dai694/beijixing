# 流量异常诊断 Playbook（SIF 优先版）
# 版本: v0.3 | 更新: 2026-07-02
# 变更: SIF MCP 接入，从代理指标层升级为真值层

目标：优先用 SIF MCP 做 ASIN 流量异常诊断，Sorftime/Pangolinfo 仅做补充和降级。

## SIF 优先执行链（6 步）

### Step 1: 自动诊断
```
mcp__sif__analyze_traffic_anomaly(asin, country, time_type?, time_value?)
```
返回：conclusion + reasoning_path + evidence + recommendation + confidence
- conclusion 直接是端到端根因结论，不需要自己算代理指标
- reasoning_path 是多步假设检验，每步有 confirmed/rejected/unresolved
- 如果 conclusion 包含 competitor_displacement / market_demand_decline / seasonal_demand_drop，自动触发 Step 5 demand_check

### Step 2: 流量趋势确认
```
mcp__sif__ops_get_asin_traffic_trend(asin, country, granularity=week, lastMonths=3)
```
返回：按周的 totalScore / nfScore / adScore / spScore / recSpScore / sbScore / sbvScore + trend_analysis
- 直接用 nfScore 做自然流量基线，adScore 做广告流量基线
- trend_analysis 包含 anomaly_weeks，和 Step 1 结论交叉验证
- 替代原来的 organic_visibility_score / sponsored_visibility_score 代理指标

### Step 3: 关键词信号
```
mcp__sif__market_get_asin_keyword_signals(asin, country, topN=50)
```
返回：declining[] / gaining[] / rank_gaps[] / top_keywords[]
- 每个 top_keyword 包含 traffic_share / contri_change / natural_ratio / organic_rank / sp_rank / keyword_health / rank_evolution / channel_coverage / top3_click_share / top3_conversion_share / search_volume / aba_rank
- keyword_health 分 core / at_risk / volatile / paid_dependent / standard
- at_risk 词送 Step 4 下钻和 demand_check
- 替代原来从 traffic_terms_snapshot + keyword_rank_history + serp_competitor_snapshot 拼接代理信号

### Step 4: 异常周关键词下钻（按条件触发）
```
mcp__sif__ops_get_asin_traffic_trend_detail(asin, country, endDay=<异常周>, granularity=week, desc=true, pageNum=1, pageSize=50)
```
触发条件：Step 1 返回异常周 且 Step 3 有 at_risk 词
返回：按关键词的自然/广告流量分和排名
- 精确到单周单词的 naturalScore / adScore / naturalRank / spRank
- 替代原 product_ranking_trend_by_keyword

### Step 5: 变体流量拆解（多变体 ASIN 触发）
```
mcp__sif__ops_get_listing_traffic_structure(asin, country)
```
触发条件：ASIN 有多个变体
返回：每个变体的 totalScore / nfs / ads / sps / recs / sbs / sbvs
- 定位问题出在哪个变体
- 替代原来从 SERP 手动推断变体流量分布

### Step 6: 需求/竞争检查（按条件触发）
```
mcp__sif__market_get_keyword_demand(keywords=at_risk+declining, country)
mcp__sif__market_get_keyword_competition(keyword, asin, country, rank_evolution=true)
```
触发条件：
- Step 1 conclusion 包含 market / demand / seasonal / competitor_displacement
- 或 Step 3 有 at_risk 词但排名未明显掉

demand 返回：diagnosis / weeks_to_peak / action_hint
competition 返回：competition_position / concentration_profile / system_state / top_asins[]

两者的结论合并进最终报告的根因链路图。

## 降级方案

当 SIF MCP 不可用时（链接失败 / 超时 / UNAUTHORIZED / FORBIDDEN）：

### Sorftime 主链路
1. `product_detail(asin)` — 取产品基础信息
2. `product_traffic_terms(asin, page=1)` — 取关键词、搜索量、曝光位置
3. `product_trend(asin, SalesVolume / Rank)` — 取月度趋势
4. `product_ranking_trend_by_keyword(asin, keyword)` — 取关键词排名趋势

### Pangolinfo 现场链路
1. `get_amazon_product(asin)` — 校验 PDP
2. `search_amazon(keyword)` — 获取 SERP Top20

### 代理指标（仅降级模式）
- organic_visibility_score = sum(search_volume * ctr_weight * freshness_weight)
- sponsored_visibility_score = sum(search_volume * ad_position_weight * freshness_weight)
- competitor_pressure_score = top_sponsored + price_advantage + rating_advantage
- anomaly_score = 0.4*organic_drop + 0.25*sponsored_drop + 0.2*rank_loss + 0.15*competitor_pressure

降级模式报告必须标 "proxy" 并注明不等于真实流量。

## 输出要求

### 必须输出
- Mermaid 根因图
- 逐步推理（SIF 模式直接引用 reasoning_path）
- 一句话结论（SIF 模式直接引用 conclusion）
- 单一最紧迫行动（SIF 模式直接引用 recommendation.action）
- 数据来源标注（sif / sorftime / pangolinfo / local）
- 待验证项

### 禁止输出
- SIF 模式下标 "proxy" 的字段（SIF 已经是真值）
- 降级模式下不标 "proxy" 的代理指标
- 自动调价、调竞价、写回后台

## 真值 vs 代理速查

| 字段 | SIF 真值工具 | 降级代理 |
|---|---|---|
| 总流量分 | ops_get_asin_traffic_trend.totalScore | organic + sponsored visibility score |
| 自然流量分 | ops_get_asin_traffic_trend.nfScore | organic_visibility_score |
| 广告流量分 | ops_get_asin_traffic_trend.adScore | sponsored_visibility_score |
| SP/SB/SBV 拆分 | ops_get_asin_traffic_trend.spScore/sbScore/sbvScore | 不可获取 |
| 关键词流量贡献 | keyword_signals.top_keywords[].traffic_share | 不可获取 |
| 关键词健康度 | keyword_signals.top_keywords[].keyword_health | 不可获取 |
| ABA 搜索量 | market_get_keyword_history.volumes[] | Sorftime 站内搜索量 |
| ABA 排名 | market_get_keyword_history.ranks[] | 不可获取 |
| Top3 点击集中度 | market_get_keyword_history.top3_click_shares[] | SERP 密度估算 |
| Top3 转化集中度 | market_get_keyword_history.top3_conversion_shares[] | 不可获取 |
| 竞争自然/广告占比 | keyword_competition.top_asins[].natural_ratio | 不可获取 |
| competition_position | keyword_competition.competition_position | 推理推断 |
| 变体流量拆解 | listing_traffic_structure.list[].nfs/sps/sbvs | 不可获取 |
| 异常根因结论 | analyze_traffic_anomaly.conclusion | anomaly_score 阈值推断 |
