# Investment Central Symbol Registry Protocol

This protocol tells every Codex trade-thesis tab how to register, update, and close followed symbols so the News Scalper and Notion Journal Investment Module share one source of truth.

The registry must be open, relationship-based, and thesis-aware. A symbol is not followed because one tab mentioned it once. A symbol is followed because at least one active thesis, watchlist, macro premise, alert, or manual pin still has an active relationship to it.

## Source Of Truth

Live registry data belongs in CloudKit, mirrored into local SQLite on every client.

This Markdown file is only the operating contract for Codex tabs and app agents. Do not treat Markdown, inline Swift arrays, or local-only files as the live registry. The app may use seed migrations to bootstrap CloudKit from existing Investment Module watchlists, but after seeding, fast reads should come from the local SQLite mirror and cross-device truth should sync through CloudKit.

## Core Rule

Do not delete a symbol just because one thesis closes.

Close the relationship between that thesis and the symbol. The symbol remains followed if any other active relationship still exists.

Follow status is derived:

```text
symbol.followed = any(symbol_relationship.status in ["active", "watch", "pinned", "alert_only"])
```

When the last active relationship closes, the symbol becomes inactive for news scalping, but its history remains in the registry.

## Why This Exists

The News Scalper needs to know what we care about without reading every trade thesis manually.

Trade thesis tabs need to know their responsibility:

- When adding a symbol to a thesis, add or update a registry relationship.
- When changing thesis status, update relationship status.
- When closing a thesis, close only that thesis relationship.
- When the same symbol belongs to multiple theses, preserve all other relationships.
- When a symbol stops being followed everywhere, mark it inactive rather than deleting it.

## Data Model

### Symbol

One canonical row per instrument or macro proxy.

Required fields:

```json
{
  "symbol_id": "US:PLTR",
  "display_symbol": "PLTR",
  "name": "Palantir",
  "asset_class": "equity",
  "market": "US",
  "exchange": "NYSE",
  "currency": "USD",
  "ib_symbol": "PLTR",
  "ib_sec_type": "STK",
  "ib_exchange": "SMART",
  "ib_currency": "USD",
  "news_keywords": ["Palantir", "AIP"],
  "macro_tags": ["AI software"],
  "status": "active",
  "created_at": "2026-05-06T00:00:00Z",
  "updated_at": "2026-05-06T00:00:00Z"
}
```

Use stable canonical IDs:

```text
US:PLTR
US:AMD
HK:0700
JP:6501
FX:USDJPY
COM:XAUUSD
ETF:SMH
INDEX:QQQ
CRYPTO:BTCUSD
MACRO:US30Y_AUCTION
MACRO:WAR_RISK
```

### Symbol Relationship

One row per reason we follow the symbol.

Required fields:

```json
{
  "relationship_id": "rel:saas-overshoot:US:PLTR",
  "symbol_id": "US:PLTR",
  "source_type": "trade_thesis",
  "source_id": "saas-overshoot",
  "source_title": "2026 Q1 Software overshoot",
  "role": "sector_verdict",
  "priority": 4,
  "status": "watch",
  "alert_mode": "digest",
  "opened_at": "2026-05-05T00:00:00Z",
  "closed_at": null,
  "notes": "AI software valuation/reaction barometer for DDOG and SNOW."
}
```

Valid `source_type` values:

```text
trade_thesis
watchlist
macro_premise
news_theme
manual_pin
calendar_event
alert_rule
```

Valid `role` examples:

```text
target
primary_trade
sector_verdict
read_through
hedge
macro_proxy
funding_proxy
credit_proxy
earnings_event
alert_only
```

Valid `status` values:

```text
active
watch
pinned
alert_only
paused
closed
archived
```

Valid `alert_mode` values:

```text
breaking
important
digest
silent
```

Priority scale:

```text
5 = active position or immediate thesis-critical symbol
4 = target / high-signal event / major read-through
3 = normal watchlist symbol
2 = background read-through
1 = archive / low-priority context
```

## News Scalper Behavior

The system has two separate steps:

1. **Journal for Mac pipeline:** the Mac mini fetches, deduplicates, classifies, archives, and writes news output.
2. **Notion Journal display pipeline:** Notion Journal reads the synced output, shows News Inbox state, badge counts, and notifications.

Do not make Notion Journal do the always-on news scalping. Notion Journal is the reader/UI. Journal for Mac is the worker.

The News Scalper reads symbols and active relationships, not trade thesis prose.

Every 15 minutes it should:

1. Load active symbols and relationships.
2. Query IBKR news / subscribed feeds / macro sources.
3. Deduplicate headlines.
4. Apply rule-based severity scoring.
5. Send likely-important items to Qwen 8B for classification.
6. Save all important and digest-worthy news.
7. Notify only when the item crosses the notification threshold.

The scalper must also watch macro-breaking topics that may not have symbols:

```text
war
missile strike
invasion
ceasefire collapse
failed bond auction
weak treasury auction
currency collapse
devaluation
intervention
capital controls
default
missed payment
bank run
deposit freeze
liquidity crisis
emergency central bank action
sanctions
export controls
oil/shipping disruption
exchange halt
circuit breaker
Mag 7 capex cut
AI data-center commitment cancellation
```

Macro topics should be represented as `MACRO:*` symbols or registry topics so they can have relationships too.

Example:

```json
{
  "symbol_id": "MACRO:US30Y_AUCTION",
  "display_symbol": "US30Y Auction",
  "name": "US 30Y Treasury Auction Stress",
  "asset_class": "macro",
  "market": "US",
  "news_keywords": ["30-year auction", "Treasury auction", "tail", "bid-to-cover"],
  "macro_tags": ["rates", "duration", "liquidity"],
  "status": "active"
}
```

## Notification Rules

Company news should normally be digest-only unless tied to an active trade or systemic read-through.

Immediate notification should focus on:

- macro regime shocks
- war / default / bank run / currency / rates / credit events
- Mag 7 capex cut or AI commitment cancellation
- active position or thesis-critical ticker with confirmed high severity
- news that affects multiple active relationships at once

Suggested thresholds:

```text
0-3 = ignore
4-6 = save to digest
7-8 = important alert inside News Module
9-10 = breaking notification + in-app popup
```

If a headline is market-wide and severe, it does not need a watched ticker match.

## Qwen 8B Contract

Qwen should receive structured input and return JSON only.

Input:

```json
{
  "headline": "US 30-year auction tails sharply as foreign demand weakens",
  "source": "IBKR News",
  "timestamp": "2026-05-06T18:02:00Z",
  "matched_symbols": ["MACRO:US30Y_AUCTION", "ETF:QQQ", "US:PLTR"],
  "active_relationships": [
    {
      "symbol_id": "ETF:QQQ",
      "source_title": "Dream Girl Trade / Mag 7",
      "role": "macro_proxy",
      "priority": 4
    }
  ],
  "rule_score": 8,
  "price_context": {
    "US10Y": "+10 bps in 20 min",
    "QQQ": "-1.1% in 15 min"
  }
}
```

Output:

```json
{
  "severity": 9,
  "urgency": "breaking",
  "bias": "risk_off",
  "category": "rates",
  "summary": "Weak long-end Treasury auction is a duration shock and can pressure high-multiple software, semis, and AI capex trades.",
  "why_it_matters": "A failed or badly tailed auction reprices discount rates and funding conditions across the active investment book.",
  "affected_symbols": ["ETF:QQQ", "ETF:SMH", "US:PLTR", "US:DDOG", "COM:XAUUSD"],
  "read_through": ["software_duration", "AI_capex", "private_credit", "banks"],
  "notify": true,
  "do_not_alert_reason": ""
}
```

Qwen must not recommend an order. It classifies news, explains read-through, and decides notification priority.

## Trade Thesis Tab Responsibilities

Every Codex tab responsible for a trade thesis must do the following.

### When Creating A Thesis

1. Create or confirm the thesis ID.
2. Add every cared-about symbol as a Symbol if missing.
3. Add a Symbol Relationship for every symbol used by the thesis.
4. Set priority and alert mode.
5. Add macro topics when relevant, not only tickers.

Example:

```json
{
  "relationship_id": "rel:global-ai-infra:US:URI",
  "symbol_id": "US:URI",
  "source_type": "trade_thesis",
  "source_id": "global-ai-infra",
  "source_title": "2026 Global AI Infrastructure",
  "role": "equipment_rental_proxy",
  "priority": 4,
  "status": "watch",
  "alert_mode": "digest"
}
```

### When Adding A Symbol

Add or update the relationship. Do not only edit the visible table.

Required update:

```text
Symbol exists?
- no: create Symbol
- yes: preserve Symbol

Relationship exists for this thesis?
- no: create relationship
- yes: update role / priority / status / notes
```

### When Promoting A Symbol

If a watch item becomes an active target:

```text
relationship.status = active
relationship.priority = 5
relationship.alert_mode = important or breaking
```

### When Pausing A Thesis

Set relationships to `paused` unless specific symbols remain active through another relationship.

Do not alter relationships owned by other theses.

### When Closing A Thesis

For every relationship where `source_id` equals the thesis ID:

```text
relationship.status = closed
relationship.closed_at = now
```

Then recompute the symbol:

```text
if symbol has no active/watch/pinned/alert_only relationships:
    symbol.status = inactive
else:
    symbol.status = active
```

Never delete the symbol or its historical news.

### When Reopening A Thesis

Reopen relationships or create new ones:

```text
relationship.status = watch or active
relationship.closed_at = null
symbol.status = active
```

## Relationship Examples

Same symbol in multiple theses:

```json
[
  {
    "symbol_id": "US:PLTR",
    "source_id": "saas-overshoot",
    "role": "sector_verdict",
    "status": "watch",
    "priority": 4
  },
  {
    "symbol_id": "US:PLTR",
    "source_id": "ai-revenue-vs-capex-short",
    "role": "AI_software_profit_pool",
    "status": "active",
    "priority": 5
  }
]
```

Closing `saas-overshoot` does not stop following `US:PLTR` because `ai-revenue-vs-capex-short` still has an active relationship.

## Minimum Registry API

The app should eventually expose helpers like:

```text
upsertSymbol(symbol)
upsertRelationship(relationship)
closeRelationship(source_id, symbol_id)
closeAllRelationshipsForSource(source_id)
activeRelationships(symbol_id)
activeSymbols()
activeSymbolsForSource(source_id)
recomputeSymbolStatus(symbol_id)
```

Until the API exists, Codex tabs should maintain the same model in the implementation they touch and record this protocol in their handoff.

## News Record Model

The News Scalper should write normalized records:

```json
{
  "news_id": "ibkr:2026-05-06:hash",
  "timestamp": "2026-05-06T18:02:00Z",
  "source": "IBKR News",
  "headline": "US 30-year auction tails sharply as foreign demand weakens",
  "body": "",
  "url": "",
  "matched_symbols": ["MACRO:US30Y_AUCTION", "ETF:QQQ"],
  "matched_relationship_ids": ["rel:japan-trade:FX:USDJPY"],
  "category": "rates",
  "rule_score": 8,
  "qwen_severity": 9,
  "urgency": "breaking",
  "bias": "risk_off",
  "summary": "Weak long-end Treasury auction is a duration shock.",
  "why_it_matters": "Can pressure QQQ, software duration and AI capex trades.",
  "notify": true,
  "notified_at": null,
  "dedupe_key": "us30y-auction-tail-foreign-demand"
}
```

## Notion Journal News Module

The Investment Module should have a News Inbox with:

- Breaking
- Important
- 15-Min Digest
- Macro Regime
- Trade Thesis News
- Symbol News
- Ignored / Archived

Clicking news should show:

- original headline/source
- Qwen classification
- affected symbols
- affected theses
- why it matters
- related price context
- follow-up action note

## Notification Delivery

For app-open notifications:

- Notion Journal polls the news feed.
- If `notify == true` and `notified_at == null`, show an in-app banner/popup.

For OS notifications:

- On Mac mini, Journal for Mac can send a macOS notification immediately.
- On iPhone/iPad, the robust path is CloudKit push:
  - Mac mini writes `BreakingNewsAlert` record.
  - Notion Journal subscribes to that record type.
  - iOS receives a push and opens the News Module / news item.

Local polling alone is acceptable for desktop, but not enough for reliable mobile wake-up alerts.

## Article Body Storage

CloudKit should store metadata and references. Full article bodies, screenshots, PDFs, and long Markdown captures should live in iCloud Drive.

Recommended archive path:

```text
iCloud Drive/Notion Journal/Investment News/YYYY/MM/DD/
```

CloudKit news records should carry:

```json
{
  "body_storage": "icloud_file",
  "icloud_relative_path": "Investment News/2026/05/06/story.md",
  "content_hash": "...",
  "original_url": "...",
  "source_story_id": "..."
}
```

This keeps CloudKit fast and lets old news be moved by date folders without losing the searchable index.

## Codex Handoff Instruction

Every trade-thesis Codex tab should include this line in its operating context:

```text
Follow Investment_Central_Symbol_Registry_Protocol.md. When adding, promoting, pausing, or closing any trade-thesis symbol, update the central Symbol Relationship model. Do not remove a Symbol unless all relationships are closed or archived; instead close only the relationship owned by this thesis.
```

## Non-Goals

This system does not auto-trade.

This system does not wake the user for every company headline.

This system is for thesis-aware news memory and macro-breaking alerts.
