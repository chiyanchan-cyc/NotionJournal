# Investment Macro Daily Refresh Automation

Purpose: run one daily Codex heartbeat that refreshes the Investment Macro module, writes the latest market data and signal notes back into Notion Journal / CloudKit, and creates research tasks for anything that needs deeper follow-up.

## Schedule

Run twice per day so the module has both a clean Asia close read and a clean US close read.

Recommended times:

- `20:30 Asia/Shanghai`
- `08:30 New York` during US daylight saving time

- `05:30 Asia/Shanghai` after US market close, if we want the US close captured before the next local morning.

Run intent:

- `20:30 Asia/Shanghai`: Asia close heartbeat. Prioritize HK / China, Japan, commodity / crypto, macro calendar, forecast updates, and US pre-market / last-close context.
- `05:30 Asia/Shanghai`: US close heartbeat. Prioritize final US cash close, Treasury curve, VIX / MOVE, US credit and breadth, US catalyst forecast changes, and spillover implications for the next Asia session.

## Automation Prompt

Use this as the daily heartbeat instruction:

```text
You are the Investment Macro daily refresh heartbeat for Notion Journal.

Run the daily refresh for the Investment Module.

Date context:
- Use today's date in Asia/Shanghai.
- Also note whether US market data is last-close, pre-market, intraday, or post-close.
- Identify whether this is the Asia close heartbeat or US close heartbeat, and prioritize the relevant close while still refreshing all modules.
- Store each market snapshot on its market session date, not on the local heartbeat run date. Example: a `05:30 Asia/Shanghai` Tuesday heartbeat that captures Monday's US close must write S&P 500, US 10Y, VIX, and US breadth to Monday's US market date, not Tuesday's Asia date.

Refresh these areas:

1. US snapshot
- S&P 500: level, point change, percent change, source, timestamp.
- US 10Y Treasury: yield, daily basis-point move, source, timestamp.
- Store Treasury yields as yield levels, for example `4.30%`, and store daily changes separately as basis points. Do not confuse decimal form (`0.043`) with percent display (`4.30%`), and never write US 10Y as `0.43%` unless the source truly says the yield is below 1%.
- VIX: level, point change, percent change, source, timestamp.
- Use Cboe's daily VIX history file as the primary source when available: `https://cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv`. If the target US close is not yet in that file, display the latest official Cboe close and mark the target close as `pending official Cboe refresh`; do not leave VIX blank.
- If available, also note 2Y, 30Y, real yield, VIX, MOVE, and S&P breadth if any changed the macro read.

2. HK / China snapshot
- Hang Seng / HKSE: level, percent change, source, timestamp.
- Shanghai A / Shanghai Composite: level, percent change, source, timestamp.
- Check USDCNH, USDHKD, HIBOR / HK liquidity, China credit or property stress headlines.

3. Japan snapshot
- Nikkei 225 / Tokyo equity market: level, percent change, source, timestamp.
- 10Y JGB: yield, daily basis-point move, source, timestamp.
- Check USDJPY, BOJ headlines, JGB auction stress, and carry-trade stress.

4. Commodity / Crypto snapshot
- Bitcoin: price and 24h percent change.
- ETH: price and 24h percent change.
- Brent: price and daily percent change.
- WTI: price and daily percent change.
- Gold: price and daily percent change.
- Silver: price and daily percent change.
- Check stablecoin supply, crypto ETF flows, OPEC/EIA/oil headlines, and major regulatory/security news.

5. Calendar
- Add or update any major macro events in the next 45 days.
- Mark market-closed days for US, HK/China, and Japan if missing.
- For each important event, include expected value, prior value, why it matters, likely market impact, and source links.
- Refresh the forecast for each high-impact upcoming event. Include consensus/expected value, prior value, market-implied expectation when available, the heartbeat's base case, upside/downside scenarios, likely affected markets, and what would confirm or invalidate the base case.
- For central-bank and policy events such as BOJ, FOMC, Fed-chair transition, Treasury refunding, and major China policy meetings, include a probability-weighted scenario table instead of a single-point forecast.

6. Macro dashboard scorecard
Update status, note, and next catalyst for:
- US Liquidity
- Rates And Curve
- Credit Stress
- Consumer And Labor
- Earnings And Breadth
- China Credit Impulse
- FX And Property Stress
- BOJ And JGB
- JPY Carry Stress
- Crypto Liquidity
- Oil And Metals

Status should be one of:
- Supportive
- Calm
- Watch
- Mixed
- Stress

7. Output format
Write the result back to Notion Journal / CloudKit as structured rows where possible.
Also produce a concise daily note with:
- One-line macro verdict.
- Top 3 changes since yesterday.
- Signals that confirm the current thesis.
- Signals that invalidate or weaken the current thesis.
- Forecast updates for the highest-impact events in the next 45 days.
- Events to watch in the next 7 days.
- Source links.

8. Trade thesis watch lists
- Refresh every visible trade-thesis watch-list row on each relevant market close.
- Required columns are: Symbol, Monitor Date, 52H, 52W Low, Today Price, and daily percent change.
- `Monitor Date` must be the instrument's market-session date, not the local heartbeat run date.
- For US-listed symbols, refresh on the US close heartbeat. For HK/China/Japan/Europe symbols, refresh on the Asia close heartbeat when the local market has closed, or mark as delayed / last-close if the source lags.
- If a quote source fails, keep the prior value visible and create a follow-up task for that symbol instead of displaying a full row of `Needs refresh`.
- Current trade watch-list universes include:
  - SaaS Overshoot: DDOG, MDB, TEAM, NET, SNOW.
  - China AI: BIDU, BABA, 0700 HK, 002230 CN, 0981 HK, 688256 CN, 600584 CN, 002156 CN, 002185 CN, USD/CNH.
  - Global AI Infrastructure: FCX, SCCO, 2899 HK, NEE, DUK, VST, ETN, SU FP, ENR GR, 6501 JP, VRT, JCI, TT.

Current macro thesis to evaluate:
- Market can hold near all-time highs into Nvidia.
- Pullback risk rises into June because Fed-chair uncertainty, BOJ rate pressure, and stretched AI positioning converge.

Do not over-write manually written trade thesis notes.
If data is not available from a reliable source, mark it as "needs refresh" and create a follow-up research task instead of inventing a value.
```

## Data Freshness Rules

- Use official sources first where practical.
- Use reliable market feeds for prices when official sources lag.
- Always store `as_of` time and source.
- Never mix intraday and close data without labeling it.
- If a market is closed, show the most recent close and mark `market_closed`.
- If a price is delayed, mark `delayed`.

## Write-Back Targets

Current UI is partly static. Until the dedicated market snapshot and macro signal tables are implemented, the heartbeat should write results into a daily note or CK task answer.

Future database targets:

- `nj_market_snapshot`
- `nj_macro_signal`
- `nj_finance_macro_event`
- `nj_agent_task`
- `nj_agent_answer`

Implemented reliability / backfill targets:

- `nj_agent_heartbeat_run`
- `nj_agent_backfill_task`

`nj_agent_heartbeat_run` records each scheduled heartbeat window, including:

- `run_id`
- `heartbeat_key`
- `scheduled_for_ms`
- `started_at_ms`
- `completed_at_ms`
- `status`: `scheduled`, `running`, `succeeded`, `failed`, `missed`, `backfilled`, or `skipped`
- `coverage_start_ms`
- `coverage_end_ms`
- `date_key`
- `market_session`
- `output_ref`
- `error_summary`
- `source_refs_json`

`nj_agent_backfill_task` stores catch-up work for missed analysis windows, including:

- `task_id`
- `heartbeat_key`
- `missed_run_id`
- `target_run_id`
- `date_key`
- `market_session`
- `coverage_start_ms`
- `coverage_end_ms`
- `reason`: for example `mba_sleep`, `vpn_dropped`, `network_unavailable`, `automation_not_run`, or `source_unavailable`
- `status`: `pending`, `running`, `succeeded`, `failed`, or `skipped`
- `priority`
- `attempt_count`
- `last_attempt_at_ms`
- `result_ref`
- `result_summary`

Backfill rules:

- At the start of every heartbeat, inspect `nj_agent_heartbeat_run` for expected windows since the last successful run of the same `heartbeat_key`.
- For US close backfills, derive `date_key` from the US cash-session close date. The local Asia/Shanghai run date belongs in the heartbeat run metadata, not in the market snapshot event date.
- If a scheduled Asia close or US close window is missing, insert a `missed` heartbeat run and a `pending` `nj_agent_backfill_task`.
- Before doing the current refresh, process pending backfill tasks in priority order.
- Backfilled notes must be labeled as backfill and must use the original missed market session and coverage window, not the current session.
- If VPN/network/source access fails, keep the task `pending` or mark it `failed` with `attempt_count` and `last_attempt_at_ms`; do not delete it.
- A successful catch-up should mark the backfill task `succeeded`, write `result_ref`, and mark the missed heartbeat run `backfilled`.
- Market snapshot backfills must cover every trading day from `2026-01-01` forward for each enabled line. Current required lines include: S&P 500, US 10Y Treasury, VIX, Hang Seng, Shanghai A, Nikkei 225, 10Y JGB, STOXX Europe 600, Euro Stoxx 50, Germany 10Y Bund, UK 10Y Gilt, EUR/USD, BTC, ETH, Brent, WTI, gold, and silver.

Recommended stable IDs:

- `snapshot.us.spx`
- `snapshot.us.us10y`
- `snapshot.us.vix`
- `snapshot.china_hk.hang_seng`
- `snapshot.china_hk.shanghai_a`
- `snapshot.japan.nikkei_225`
- `snapshot.japan.jgb_10y`
- `snapshot.commodity_crypto.btc`
- `snapshot.commodity_crypto.eth`
- `snapshot.commodity_crypto.brent`
- `snapshot.commodity_crypto.wti`
- `snapshot.commodity_crypto.gold`
- `snapshot.commodity_crypto.silver`

## Daily Note Template

```markdown
# Investment Macro Daily Refresh - YYYY-MM-DD

## Verdict

One sentence.

## Top Changes

1. ...
2. ...
3. ...

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | | | | |
| US | 10Y Treasury | | | | |
| HK / China | Hang Seng | | | | |
| HK / China | Shanghai A | | | | |
| Japan | Nikkei 225 | | | | |
| Japan | 10Y JGB | | | | |
| Commodity / Crypto | BTC | | | | |
| Commodity / Crypto | ETH | | | | |
| Commodity / Crypto | Brent | | | | |
| Commodity / Crypto | WTI | | | | |
| Commodity / Crypto | Gold | | | | |
| Commodity / Crypto | Silver | | | | |

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | | | |
| Rates And Curve | | | |
| Credit Stress | | | |
| Consumer And Labor | | | |
| Earnings And Breadth | | | |
| China Credit Impulse | | | |
| FX And Property Stress | | | |
| BOJ And JGB | | | |
| JPY Carry Stress | | | |
| Crypto Liquidity | | | |
| Oil And Metals | | | |

## Thesis Check

Confirming:
- ...

Weakening:
- ...

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Base Case | Bull Case | Bear Case | Markets Most Exposed | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  |  |  |  |

## Next 7 Days

- YYYY-MM-DD: event, expected value, why it matters.

## Follow-Up Tasks

- ...
```

## Failure Handling

If the heartbeat cannot complete:

- Write a failed task answer with the failure reason.
- Keep the previous values in place.
- Create a new `needs_refresh` task for the missing market or signal.
- Do not delete prior snapshots.
