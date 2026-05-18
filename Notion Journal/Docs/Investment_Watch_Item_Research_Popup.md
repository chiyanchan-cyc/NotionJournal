# Investment Watch Item Research Popup

This document defines the shared popup module used by every Investment watchlist row, trade item, stock, ETF, FX pair, commodity, crypto asset, or macro indicator.

The popup is the living research note for the symbol.

## Goals

- One reusable popup for all watchlists and trades.
- External market chart data with hourly and daily views.
- Optional user-drawn trend line on the chart.
- Markdown-backed research sections so analysis can be updated without rebuilding bespoke UI for each symbol.
- Same structure for stocks and non-stock indicators.
- One symbol-level note reused across every trade tab where the symbol appears.

## Popup Tabs

Every watch item uses the same tabs:

1. `Chart`
   - External price data.
   - Hourly and daily chart toggle.
   - Trend summary for the visible chart range.
   - Manual trend-line drawing.
   - Future: volume bars under the price chart.

2. `Synopsis`
   - What the company / indicator is.
   - Chinese name if relevant.
   - Industry or macro category.
   - Standing versus peers.
   - Why it belongs in the current watchlist.

3. `Latest Result`
   - Latest quarter, interim, annual, or macro release.
   - Revenue, profit, margin, dividend, or equivalent metrics.
   - What improved.
   - What deteriorated.
   - Whether the result confirms or weakens the thesis.

4. `Analysis`
   - Living research note.
   - Current thesis.
   - Price/chart read.
   - Key catalyst.
   - Add / hold / cut / remove logic.
   - Notes from Codex or user research.

5. `Risk`
   - Fundamental risk.
   - Valuation risk.
   - Balance sheet / dividend / result-quality risk.
   - Technical risk from the chart.
   - Exact invalidation trigger.

## Markdown Storage Model

Each symbol should have one durable research record.

Recommended key:

```text
investment.research.symbol.{normalizedSymbol}
```

Examples:

```text
investment.research.symbol.1044_HK
investment.research.symbol.1234_HK
investment.research.symbol.DDOG
investment.research.symbol.USDJPY
investment.research.symbol.HSI
```

Recommended fields:

```json
{
  "symbol": "1044 HK",
  "displayName": "Hengan International",
  "assetType": "stock",
  "market": "HK",
  "primaryTradeIDs": ["china-high-yield"],
  "synopsisMD": "...",
  "latestResultMD": "...",
  "analysisMD": "...",
  "riskMD": "...",
  "sourcesMD": "...",
  "chartSettings": {
    "defaultInterval": "daily",
    "externalSymbol": "1044.HK",
    "source": "Yahoo"
  },
  "annotations": {
    "daily": {
      "trendLine": {
        "start": { "x": 0.18, "y": 0.72 },
        "end": { "x": 0.86, "y": 0.34 }
      }
    },
    "hourly": {
      "trendLine": null
    }
  },
  "updatedAt": "2026-04-29T20:10:00+08:00"
}
```

## How A Watchlist Calls It

A watchlist row should only need:

```swift
NJInvestmentWatchRow(
    id: "chinadividend-hengan",
    symbol: "1044 HK",
    name: "Hengan International",
    ...
)
```

The popup then resolves:

```text
row.symbol -> normalizedSymbol -> investment.research.symbol.{normalizedSymbol}
```

If a research record exists, render its Markdown sections.

If no record exists, render fallback Markdown templates:

- Synopsis template.
- Latest result template.
- Analysis template.
- Risk template.

This lets every trade tab use the same popup immediately, while deeper notes can be filled in over time.

## Chart Data

Current chart source:

```text
Yahoo Finance chart API
```

Current mapping examples:

```text
1044 HK -> 1044.HK
1234 HK -> 1234.HK
DDOG -> DDOG
USD/JPY -> JPY=X
```

Current intervals:

```text
Hourly: range=5d, interval=1h
Daily:  range=1y, interval=1d
```

The Yahoo chart response includes OHLCV-style data. Today the UI uses `close`. It can also read `volume` from the same response:

```json
{
  "indicators": {
    "quote": [
      {
        "close": [],
        "volume": [],
        "open": [],
        "high": [],
        "low": []
      }
    ]
  }
}
```

## Volume Support

Yes, volume can be pulled from outside data.

Implementation plan:

1. Extend chart point:

```swift
private struct NJInvestmentChartPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let volume: Double?
    let change: String
    let isDown: Bool
}
```

2. Parse `quote["volume"]` from Yahoo chart data.

3. Add volume bars below the price chart:

```swift
BarMark(
    x: .value("Date", point.date),
    y: .value("Volume", point.volume ?? 0)
)
```

4. Add volume analysis text:

```text
Volume read: current bar is above / below recent average.
```

Recommended default:

- Price chart on top.
- Volume bars underneath.
- 20-period average volume reference.
- Highlight volume spikes above 1.5x average.

## Trend-Line Drawing

Yes, trend-line drawing is possible.

Current implementation:

- The chart has a `Draw Trend` button.
- User drags on the chart.
- The popup stores normalized start/end points for the visible chart panel.
- `Reset` clears the trend line.

Current storage shape:

```json
{
  "trendLine": {
    "start": { "x": 0.18, "y": 0.72 },
    "end": { "x": 0.86, "y": 0.34 }
  }
}
```

Why normalized coordinates:

- Works across different screen sizes.
- Can persist in JSON.
- Can be replayed when the chart reopens.

Future improvement:

- Convert drag coordinates into actual date/price anchors.
- Store trend lines as:

```json
{
  "trendLine": {
    "start": { "date": "2026-03-12", "price": 22.45 },
    "end": { "date": "2026-04-29", "price": 26.80 }
  }
}
```

That would make the line stable even if chart range or zoom changes.

## Markdown Template

Use this template for any new symbol:

```markdown
# {SYMBOL} / {NAME}

## Synopsis

**Company / Indicator:**  

**Chinese name:**  

**Industry / Category:**  

**Standing:**  

**Why it belongs in this trade:**  

## Latest Result

**Latest period:**  

**Key numbers:**  

- Revenue / equivalent:
- Profit / equivalent:
- Margin / equivalent:
- Dividend / cash return:

**What improved:**  

**What deteriorated:**  

**Read-through for thesis:**  

## Analysis

**Current thesis:**  

**Price / chart read:**  

**Catalyst:**  

**Add / hold / cut rule:**  

**Research notes:**  

## Risk

**Main risks:**  

- 
- 
- 

**Invalidation trigger:**  

## Sources

- 
```

## Current Code Status

Already implemented:

- Shared popup tabs.
- Markdown rendering for popup sections.
- External hourly/daily Yahoo chart.
- Manual trend-line drawing.
- Trend summary.
- Rich Markdown content for `1044 HK`, `1234 HK`, and `DDOG`.
- Fallback Markdown templates for all other rows.

Next implementation steps:

- Persist Markdown records to the local Notion Journal database.
- Persist trend-line annotations per symbol and interval.
- Parse and display chart volume.
- Add multiple trend lines, not only one.
- Add source links per research section.
- Add edit/save UI for the Markdown tabs.

