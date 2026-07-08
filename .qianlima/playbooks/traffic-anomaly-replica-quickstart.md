# Traffic Anomaly Replica Quickstart

Use this when the user asks to replicate Xiyou `analyze_traffic_anomaly` with Sorftime and Pangolinfo.

## What This Tool Does

It builds a public-data replica of Xiyou's traffic anomaly diagnosis:

1. Sorftime provides product status, traffic terms, keyword rank trends, and monthly trends.
2. Pangolinfo provides current Amazon SERP and competitor pressure.
3. Local CSV history stores normalized snapshots.
4. The report script calculates proxy metrics and produces a Markdown diagnosis.

It does not claim to know true Xiyou daily organic traffic, ad traffic, clicks, spend, sessions, or CVR.

## One-Command Flow

After the Agent has normalized MCP results into a snapshot JSON:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".qianlima/scripts/run-traffic-anomaly-replica.ps1" `
  -InputJson ".qianlima/local-data/traffic-history/snapshot-schema.example.json"
```

This imports the snapshot and writes a report to `reports/`.

## Prepare a Blank Snapshot

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".qianlima/scripts/new-traffic-anomaly-snapshot-template.ps1" `
  -Asin B09PCSR9SX `
  -Marketplace US `
  -Date 2026-07-02 `
  -Keywords "neck fan,fathers day gifts"
```

Fill the generated JSON using:

- `.qianlima/local-data/traffic-history/mcp-to-snapshot-mapping.md`
- Sorftime `product_detail`
- Sorftime `product_traffic_terms`
- Sorftime `product_ranking_trend_by_keyword`
- Pangolinfo `get_amazon_product`
- Pangolinfo `search_amazon`

## Output Interpretation

- `organic_visibility_score`: proxy for natural visibility, not true organic traffic.
- `sponsored_visibility_score`: proxy for ad visibility, not clicks or spend.
- `competitor_pressure_score`: SERP Top 10 competitor pressure.
- Root-cause labels are directional and require backend verification before budget or bid changes.

## Verified Example

The example ASIN `B09PCSR9SX` has been tested with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".qianlima/scripts/run-traffic-anomaly-replica.ps1" `
  -InputJson ".qianlima/local-data/traffic-history/snapshot-schema.example.json" `
  -HistoryDir "working/traffic-final-test" `
  -OutputDir "working/traffic-final-test" `
  -Version "Vfinal"
```

Expected output:

`working/traffic-final-test/2026-07-02_traffic-anomaly-diagnosis_B09PCSR9SX_US_Vfinal.md`

