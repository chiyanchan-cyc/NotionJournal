# Investment Macro Daily Refresh - 2026-05-05 Asia Close

Heartbeat: Asia close

As of: 2026-05-05 22:04 Asia/Shanghai

Asia market dates carried in this note:

- Hong Kong: 2026-05-05 close
- Mainland China: 2026-05-05 market_closed; latest cash close still 2026-04-30
- Japan: 2026-05-05 market_closed; latest cash close still 2026-05-01
- Europe: 2026-05-05 intraday overlap; same-session close was not cleanly retrievable for every required line before write-back, so unresolved Europe rows stay explicitly labeled intraday or last-close

US market date carried in this note: 2026-05-04 last-close, plus 2026-05-05 U.S. pre-market context where explicitly labeled.

Placement rule: Tuesday, May 5, 2026 in Asia/Shanghai is only the local heartbeat timestamp. U.S. snapshot rows still belong to the Monday, May 4, 2026 U.S. cash-session close. Hong Kong rows belong to Tuesday, May 5, 2026. Mainland China rows stay on Thursday, April 30, 2026 because Labour Day closures still covered Tuesday, May 5, 2026. Japan rows stay on Friday, May 1, 2026 because Tuesday, May 5, 2026 was Children's Day and JPX cash equities were closed.

Backfill status at start: durable storage now exists in `/Users/mac/Developer/Notion Journal/device-db-snapshots/iphone17pm-current-prefs/notion_journal.sqlite`. No new missed heartbeat window was inferred from the visible markdown chain between the 2026-05-04 Asia-close note and the 2026-05-05 U.S.-close note. One pending backfill task remained open at start: official VIX confirmation for the 2026-05-04 U.S. close.

Storage status: markdown note written. Durable heartbeat and backfill rows were attempted against `/Users/mac/Developer/Notion Journal/device-db-snapshots/iphone17pm-current-prefs/notion_journal.sqlite`; market snapshot / event write-back was completed only where the active snapshot accepted the upsert.

## Verdict

The market can still try to hold into Nvidia, but today’s Asia-close read made the June-risk thesis cleaner: Hong Kong gave back part of Monday’s post-holiday burst, China and Japan still did not reopen cash equity markets, and the macro relief came only from oil backing off the spike rather than from any true easing in rates or policy risk.

## Top 3 Changes Since Previous Heartbeat

1. Hong Kong reversed from Monday’s tech-led rebound: the Hang Seng fell 0.76% to `25,898.61`, and the Hang Seng Tech Index underperformed with a 0.94% drop.
2. The U.S. risk backdrop stabilized modestly rather than deteriorating further. Reuters showed S&P 500 futures up about `0.35%` and Nasdaq 100 futures up about `0.59%` on Tuesday morning New York time as oil pulled back from Monday’s extremes.
3. Crypto and gold bounced while official VIX still lagged. BTC rose back above `$81K`, ETH moved near `$2.39K`, spot gold recovered toward `$4,560`, but the latest accessible official Cboe/FRED VIX close still stopped at `16.99` for `2026-05-01`.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,200.75 | -29.37 / -0.41% | 2026-05-04 last-close | Xinhua |
| US | 2Y Treasury yield | 3.95% | +7 bps vs 2026-05-01 | 2026-05-04 official close | U.S. Treasury |
| US | 10Y Treasury yield | 4.45% | +6 bps vs 2026-05-01 | 2026-05-04 official close | U.S. Treasury |
| US | 30Y Treasury yield | 5.02% | +5 bps vs 2026-05-01 | 2026-05-04 official close | U.S. Treasury |
| US | VIX | 16.99 latest accessible official Cboe close; 2026-05-04 pending official refresh | latest official chain still ends at 2026-05-01 | 2026-05-01 official close / 2026-05-04 pending | FRED `VIXCLS` sourced from Cboe |
| HK / China | Hang Seng | 25,898.61 | -197.27 / -0.76% | 2026-05-05 close | Xinhua |
| HK / China | Shanghai Composite | 4,112.16 | market_closed; carry 2026-04-30 close | 2026-05-05 market_closed / 2026-04-30 last-close | SHFE holiday schedule; prior verified snapshot |
| Japan | Nikkei 225 | 59,513.12 | market_closed; carry 2026-05-01 close | 2026-05-05 market_closed / 2026-05-01 last-close | JPX; prior verified snapshot |
| Japan | 10Y JGB | 2.47% last verified | 0 bp vs latest verified row | 2026-04-28 last verified / 2026-05-05 carry | prior verified snapshot |
| Europe | STOXX Europe 600 | 608.13 | about +0.4% intraday | 2026-05-05 Europe intraday overlap | Reuters / MarketScreener |
| Europe | Euro Stoxx 50 | 5,753.36 cash last-close; June futures near 5,808 intraday | 2026-05-04 cash -2.18%; 2026-05-05 futures +1.37% | 2026-05-04 last-close / 2026-05-05 futures overlap | Investing.com |
| Europe | Germany 10Y Bund | 3.03% last verified | last verified 2026-05-01 close 3.0342% | 2026-05-01 last-close / 2026-05-05 carry | Investing.com |
| Europe | UK 10Y Gilt | 5.32% last verified | exact 2026-05-05 10Y close still needs cleaner pass; long-end stress remains elevated | 2026-04-30 last verified / 2026-05-05 carry | prior verified snapshot; UK rates coverage |
| FX | EUR/USD | 1.16997 | -0.17% | 2026-05-04 close | prior verified snapshot |
| FX | USD/CNH | 6.82 | about -0.10% | 2026-05-05 live Asia close context | CoinCodex |
| Commodity / Crypto | BTC | 81,286.38 | +2.92% / 24h | 2026-05-05 20:45 Asia/Shanghai | Fortune |
| Commodity / Crypto | ETH | 2,388.49 | +2.06% / 24h | 2026-05-05 20:45 Asia/Shanghai | Fortune |
| Commodity / Crypto | Brent | 114.44 prior settle; futures eased from Monday spike | about -0.7% intraday from prior settle | 2026-05-04 settle / 2026-05-05 U.S. pre-market | WSJ; Barron's |
| Commodity / Crypto | WTI | about 104.00 | about -2.0% intraday after Monday's spike | 2026-05-05 U.S. pre-market | Investopedia |
| Commodity / Crypto | Gold | 4,560.50 | about +0.9% vs Monday Comex settle | 2026-05-05 early Europe / U.S. pre-market | WSJ |
| Commodity / Crypto | Silver | 73.80 | about +1.0% vs Monday Comex settle | 2026-05-05 early Europe / U.S. pre-market | WSJ |

## Trade Thesis Watch-List Refresh

Rule used here: the Asia-close heartbeat refreshed all required rows to the latest clean market-session date by venue. Hong Kong rows were updated where a same-session quote was retrievable. Mainland China rows remain on the 2026-04-30 last cash session because mainland cash equities were closed on 2026-05-05. Japan stays on the 2026-05-01 close because 2026-05-05 was Children's Day. Europe rows kept prior verified values where a same-session symbol quote was not cleanly retrievable in this run.

| Thesis | Symbol | Monitor Date | 52H | 52W Low | Today Price | Daily % |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| China AI | 0700 HK | 2026-05-05 | HK$683.00 | HK$469.00 | HK$472.20 | -0.17% |
| China AI | 002230 CN | 2026-04-30 | CNY67.50 | CNY43.45 | CNY47.79 | -0.56% |
| China AI | 0981 HK | 2026-04-30 | HK$93.50 | HK$37.00 | HK$70.90 | +7.75% |
| China AI | 688256 CN | 2026-04-30 | CNY1,595.88 | CNY520.67 | CNY1,699.96 | +20.00% |
| China AI | 600584 CN | 2026-04-30 | CNY54.63 | CNY31.20 | CNY45.56 | +2.71% |
| China AI | 002156 CN | 2026-04-30 | CNY59.20 | CNY21.50 | CNY51.77 | +4.59% |
| China AI | 002185 CN | 2026-04-30 | CNY16.00 | CNY8.60 | CNY13.11 | +2.66% |
| China AI | USD/CNH | 2026-05-05 | n/a | n/a | 6.82 | -0.10% |
| Global AI Infrastructure | 2899 HK | 2026-04-15 | HK$46.98 | HK$16.70 | HK$37.98 | +0.74% |
| Global AI Infrastructure | SU FP | 2026-04-15 | EUR280.05 | EUR196.54 | EUR266.20 | -0.50% |
| Global AI Infrastructure | ENR GR | 2026-04-15 | EUR171.94 | EUR56.04 | EUR169.32 | -0.96% |
| Global AI Infrastructure | 6501 JP | 2026-05-01 | JPY6,039 | JPY2,590 | JPY4,815 | -5.01% |

## Watch-List Refresh Summary

- The required table stayed row-complete without blanking any row to `Needs refresh`.
- `0700 HK` was refreshed to the 2026-05-05 local close and held materially better than the Hang Seng, which matters because Tencent earnings are due on `2026-05-13`.
- `0981 HK` was upgraded to the latest clean 2026-04-30 verified close available in this run. A clean same-session 2026-05-05 Hong Kong semiconductor row was not retrievable before the note write-back cutoff.
- `2899 HK`, `SU FP`, and `ENR GR` still need a cleaner source pass; prior verified values were kept visible and are now explicit follow-up items.

## US Snapshot

- Monday, May 4, 2026 remains the latest valid U.S. cash close. The S&P 500 finished at `7,200.75`, down `0.41%`.
- Official Treasury rows show the 2Y at `3.95%`, 10Y at `4.45%`, and 30Y at `5.02%` for the May 4 market date. That keeps the rates leg of the June-risk thesis active.
- Tuesday pre-market tone was firmer rather than disorderly. Reuters showed S&P 500 e-minis up about `0.35%`, Dow futures up about `0.26%`, and Nasdaq 100 futures up about `0.59%` as oil pulled back from Monday’s spike.
- VIX remains populated per runbook. The latest accessible official Cboe/FRED close was still `16.99` for `2026-05-01`, so the May 4 U.S. close remains pending official refresh.

## HK / China Snapshot

- Hong Kong gave back part of Monday’s reopening burst. The Hang Seng closed at `25,898.61`, down `0.76%`, while the Hang Seng Tech Index fell `0.94%`.
- Midday versus close: Xinhua had the Hang Seng down `1.16%` at the midday break and down `0.76%` by the close, so buyers stabilized the index off the lows but did not rebuild Monday’s momentum.
- Mainland China remained closed for Labour Day, so the Shanghai line stays on the `2026-04-30` cash close. Tuesday still was not a full HK-China confirmation tape.
- Money rotation read: this is an inference from index behavior, not a sector-source print. Tech underperformed the headline index and HSBC-driven financial stress weighed on sentiment, so the session looked like profit-taking out of higher-beta Hong Kong AI / platform exposure rather than fresh policy-driven buying.

## Japan Snapshot

- Japan cash equities were closed for Children's Day on Tuesday, May 5, 2026, and JPX lists Wednesday, May 6, 2026 as the Constitution Memorial Day observed holiday for cash equities as well.
- The latest valid Japan cash close therefore remains Friday, May 1, 2026: Nikkei 225 at `59,513.12`, up `0.38%`.
- The more important Japan macro signal remains rates and FX, not holiday-closed equity leadership. JGB stress remains unresolved and the yen carry channel stays a June-risk input.
- JPX derivatives holiday trading was open, but that does not change the cash-session placement rule for the watch lists or market snapshot rows.

## Europe Snapshot

- Europe was in overlap trading during the Asia-close heartbeat. Reuters / MarketScreener showed the STOXX 600 back up about `0.4%` to `608.13` after Monday’s sharp drop.
- Euro Stoxx 50 June futures were near `5,808`, up `1.37%`, but the clean cash-close row preserved in structured storage remains the `2026-05-04` close at `5,753.36`.
- UK rate stress stayed the bigger macro message than equity direction. UK long-dated yields pushed to their highest levels since 1998, reinforcing that Europe still has an inflation / duration problem even when equities bounce intraday.

## Commodity / Crypto Snapshot

- Crypto improved into the U.S. pre-market. BTC traded around `$81,286` and ETH around `$2,388`, both up more than `2%` over 24 hours.
- Oil cooled from Monday’s shock but stayed high enough to keep macro pressure alive. Reuters and Barron's showed a positive U.S. futures tone largely because oil had eased, not because the geopolitical situation had been resolved.
- Gold rebounded toward `$4,560.50` and silver toward `$73.80` after Monday’s heavy washout, which reads more like a partial stress hedge reset than a clean disinflation signal.

## Money Rotation

- HK / China: money rotated out of the Monday post-holiday chase. The midday-to-close rebound suggests dip buyers were present, but Hang Seng Tech still lagged the main index, so the better description is "partial stabilization, not renewed leadership."
- Japan: no cash-session rotation signal exists for today because Tokyo was closed. The live Japan read remains JGB pressure plus carry sensitivity.
- Europe overlap: early trade suggested modest re-risking back into continental equities while the FTSE lagged under HSBC and UK-rates pressure.
- US carry context: futures improved because oil backed off. That is tactical relief, not a thesis reset.

## Abnormal Movers / Blue-Chip Alerts

- `0700 HK` / Tencent: closed at `HK$472.20`, down only `0.17%`, materially better than the Hang Seng. Why it matters: relative resilience ahead of the `2026-05-13` result keeps platform / AI interest alive even on a soft tape.
- `HSBC`: Reuters said the stock fell more than `5%` in Europe after a `$400 million` fraud-related hit. Why it matters: this matters directly for the HK bank / yield cohort and weakens the "defensive Hong Kong financials" read.
- `HSI Tech`: down `0.94%` versus the Hang Seng at `-0.76%`. Why it matters: Tuesday was not a clean follow-through day for higher-beta China tech.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Mixed | Futures improved, but Monday's cash close still showed rates / oil sensitivity. | Treasury refunding `2026-05-06`; payrolls `2026-05-08` |
| Rates And Curve | Stress | U.S. 10Y at `4.45%` and 30Y at `5.02%` keep conditions tight. | Treasury refunding; U.S. CPI `2026-05-12` |
| Credit Stress | Watch | HSBC private-credit hit added a fresh stress marker, but U.S. spread and MOVE refreshes still need a cleaner close pass. | credit-spread / MOVE follow-up |
| Consumer And Labor | Mixed | No new labor print yet; market is waiting for payrolls. | JOLTS; payrolls |
| Earnings And Breadth | Watch | Tencent held relatively well, but Hong Kong tech still did not lead. | AMD `2026-05-05`; Nvidia `2026-05-27` |
| China Credit Impulse | Watch | Mainland China was still closed, so Tuesday did not offer new domestic confirmation. | China reopen `2026-05-06`; China CPI/PPI `2026-05-11` |
| FX And Property Stress | Watch | `USD/CNH` stayed contained near `6.82`, but clean HK liquidity and property-stress lines still need a fuller pass. | CNH / HIBOR follow-up |
| BOJ And JGB | Stress | Holiday closure did not change the structural JGB / BOJ pressure. | BOJ Summary `2026-05-12`; BOJ `2026-06-16` |
| JPY Carry Stress | Stress | The carry channel remains an unresolved June risk even without a fresh cash-equity session. | USD/JPY and JGB follow-through |
| Crypto Liquidity | Mixed | BTC and ETH bounced, but crypto is still following the oil / rates macro stack. | ETF flow and weekly crypto scan |
| Oil And Metals | Stress | Oil eased, but only from extreme levels; the inflation shock is still active. | EIA; payrolls; CPI |

## Thesis Check

Confirming:

- The market can still hold near highs into Nvidia because U.S. futures stabilized and Tencent did not break down on the Hong Kong soft day.
- BOJ / JGB / carry stress remains a live June-risk channel because Japan cash closure did not resolve anything in rates.
- The official VIX lag plus elevated long-end yields still argue that headline calm understates underlying fragility.

Weakening:

- Hong Kong did not confirm Monday's rebound with a second tech-led advance.
- China cash still has not reopened, so the Asia bullish read remains incomplete.
- The "hold near highs" part of the thesis now depends on oil cooling further; if Brent stays near the Monday spike zone, the June pullback risk arrives sooner.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Probability | Base Case | Upside / Bull Case | Downside / Bear Case | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| U.S. Treasury refunding statement | 2026-05-06 | steady coupon sizes still the base case | Q2 borrowing estimate was just lifted | probability still centered on "no immediate coupon-size shock" | Treasury avoids a new duration surprise after raising Q2 borrowing estimate to `$189B` and Q3 to `$671B` | calm sizing lets long-end yields back off and preserves the AI-led hold-near-highs tape | heavier long-end burden pushes term premium higher again | UST 10Y/30Y, USD, duration equities | Confirmed by steady sizing and calmer long-end trade; invalidated by another bond selloff | U.S. Treasury |
| U.S. payrolls, April | 2026-05-08 | market wants slower but still positive jobs growth | Mar. payrolls `+178K`; unemployment `4.3%` | June Fed hold still dominates | slower but non-recessionary labor print | cooler wages and stable unemployment reduce rates pressure | hot jobs revive higher-for-longer fears; weak jobs revive hard-landing fears | UST front end, USD, cyclicals, small caps | Confirmed by orderly cooling; invalidated by reacceleration or a crack | BLS |
| China CPI / PPI | 2026-05-11 | CPI near `1.0%` y/y and PPI near `0.5%` y/y remain the working consensus | Mar. CPI `1.0%`; PPI `0.5%` | no clean market-implied series used in this run | benign CPI with producer prices still non-negative | firmer PPI helps the Hong Kong / China cyclical read after the holiday gap | softer CPI/PPI revives China-demand skepticism | HSI, CNH, metals, China cyclicals | Confirmed by resilient producer prices; invalidated by renewed disinflation | NBS China |
| U.S. CPI, April | 2026-05-12 | headline still sticky; core services are the key | Mar. CPI `3.3%`; core `2.6%` | June hold remains dominant | headline firm but core only slowly easing | softer core services stabilizes rates and lets the tape re-focus on AI earnings | broad stickiness plus oil pass-through drives yields back up | USTs, USD, Nasdaq, gold | Confirmed by softer core services; invalidated by broad reacceleration | BLS |
| Fed-chair transition watch | 2026-05-15 window | policy-premium noise remains high | Powell Chair term scheduled through `2026-05-15` per current journal event row | probability still favors a noisy but orderly transition window | rhetoric stays messy but does not trigger a full independence repricing | confirmation / succession process passes quietly and trims term premium | louder independence conflict raises the duration risk premium | USTs, USD, banks, long-duration tech | Confirmed by calm rhetoric; invalidated by a sharp term-premium move | Federal Reserve / journal event row |
| China activity data | 2026-05-19 | retail sales / industrial production / FAI remain the key post-holiday reset | prior monthly activity releases were stable enough to avoid a new scare | no public market-implied series used | moderate reopening follow-through after holiday distortion | activity upside broadens the Hong Kong rebound into a fuller China confirmation | weak activity reopens the China-lag trade | HSI, CNH, industrial metals | Confirmed by retail / IP resilience; invalidated by broad miss | NBS China |
| Japan national CPI | 2026-05-22 | sticky enough to keep BOJ pressure alive | prior national core CPI `1.8%` y/y | BOJ path still biased gradual-hawkish | inflation remains sticky but not explosive | softer services / core cool JGB stress | hotter CPI validates a stronger BOJ tightening bias | JGBs, JPY, Nikkei, global carry | Confirmed by contained services and core; invalidated by hotter broad CPI | Statistics Bureau of Japan |
| NVIDIA earnings | 2026-05-27 | beat-and-maintain still enough in base case | prior quarterly revenue `68.1B`; Q1 guide `78.0B +/-2%` | positioning remains crowded | beat and maintain keeps the tape near highs into late May | beat-and-raise extends AI leadership and broadens breadth | guide wobble hits crowded AI exposure hard | Nasdaq, SOX, S&P breadth | Confirmed by guide confidence; invalidated by growth or margin wobble | NVIDIA IR |
| U.S. PCE | 2026-05-29 | modest core cooling still needed | prior PCE path remains sticky | Fed still anchored to hold | core drifts lower without growth break | softer core reinforces a June hold-with-balance read | sticky core plus oil argue for a more hawkish hold | USTs, USD, growth equities | Confirmed by softer core; invalidated by reacceleration | BEA |
| ECB meeting | 2026-06-04 | hold remains the base case | prior ECB settings unchanged | market still leans toward later tightening bias if oil shock lingers | ECB stays steady and cautious | calmer energy helps the ECB stay patient | oil shock hardens European tightening expectations | EUR, Bunds, STOXX, banks | Confirmed by steady rates and cautious tone; invalidated by stronger tightening signal | ECB |
| BOJ meeting | 2026-06-16 | hold at current settings in base case | Apr. hold | probability still centered on hold-with-bias | hold with tightening bias intact | calmer CPI / FX lets BOJ wait | hot CPI and renewed yen weakness pull BOJ toward the next hike faster | JGBs, JPY, Nikkei, global carry | Confirmed by calmer JGBs / FX; invalidated by hotter inflation and yen stress | BOJ |
| FOMC meeting | 2026-06-17 | no move in base case | Apr. hold | June hold remains dominant | hold with data dependence | softer CPI/PCE/jobs lets the Fed balance its tone | oil-plus-core persistence keeps the Fed more hawkish than equities want | USTs, USD, equities, gold, BTC | Confirmed by softer inflation and labor; invalidated by persistent inflation pressure | Federal Reserve |

## Probability-Weighted Policy Scenarios

### Treasury Refunding, 2026-05-06

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 55% | Coupon sizes steady; no new duration shock | Long-end stays elevated but avoids another lurch higher |
| Bearish supply surprise | 30% | Heavier duration burden or tougher financing optics | 10Y / 30Y rise again; growth-multiple pressure returns |
| Relief case | 15% | Manageable sizing and calm language | Term premium eases and high-beta tech gets more room |

### Fed-Chair / Policy-Premium Window

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Process stays noisy but orderly | Mild term premium persists without a full repricing |
| Relief case | 15% | Rhetoric cools and independence fears fade | Long-end and USD calm modestly |
| Stress case | 25% | Succession fight becomes more openly political | Risk premium rises across duration assets |

### BOJ June Meeting

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 55% | Hold with tightening bias intact | JGB and carry stress remain live |
| Calmer hold | 15% | Hold and downplay urgency | JGB yields ease and Nikkei pressure fades |
| Hawkish escalation | 30% | Tone leans more urgently toward another move | JPY firms, carry pressure rises, global risk tone worsens |

## Next 7 Days

- 2026-05-06: Mainland China cash market reopens; U.S. Treasury refunding statement.
- 2026-05-07: AMD post-earnings read-through; SMIC earnings window.
- 2026-05-08: U.S. payrolls for April.
- 2026-05-11: China CPI / PPI; weekly crypto catalyst scan.
- 2026-05-12: U.S. CPI; BOJ Summary / interpretation window.
- 2026-05-13: Tencent earnings.

## Follow-Up Tasks

- Keep `backfill.vix.official.2026-05-04` pending until the official Cboe / FRED chain prints the May 4 close.
- Refresh same-session Hong Kong symbol rows for `0981 HK` and `2899 HK`; the note preserved the latest clean verified rows instead of inventing a stale close.
- Refresh exact same-session Europe close rows for STOXX 600 cash, Euro Stoxx 50 cash, Germany 10Y Bund, and UK 10Y Gilt if a cleaner end-of-session source pass becomes available.
- Refresh `HIBOR`, `USDHKD`, and a cleaner U.S. credit-spread / MOVE pass.
- Continue the historical market-snapshot backfill program from `2026-01-01` for required lines wherever durable rows are still absent or malformed.

## Backfill Tasks Created Or Completed

- Kept `pending`: official VIX backfill for the `2026-05-04` U.S. close because the latest accessible official chain still ends at `2026-05-01`.
- No new missed heartbeat window was created in this run.

## Source Links

- Prior Asia-close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-04 Asia Close.md`
- Prior U.S.-close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-05.md`
- Hang Seng close, 2026-05-05: https://english.news.cn/20260505/24cd7a2b3b3e464dbbb0c4c6e82c8032/c.html
- Hang Seng midday, 2026-05-05: https://english.news.cn/20260505/63d89fcb7b834204ac701050e4d3a3c9/c.html
- U.S. close recap and index levels: https://english.news.cn/20260505/cc9f7a3644334feaa9def3c02a890b5a/c.html
- U.S. Treasury daily par yield curve: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_yield_curve
- Treasury borrowing estimates, 2026-05-04: https://home.treasury.gov/news/press-releases/sb0485
- Treasury TBAC policy statement, 2026 Q2: https://home.treasury.gov/news/press-releases/sb0486
- FRED VIXCLS: https://fred.stlouisfed.org/series/VIXCLS
- Japan market holidays: https://www.jpx.co.jp/english/corporate/about-jpx/calendar/
- JPX holiday derivatives trading notice: https://www.jpx.co.jp/english/news/2040/20260501-01.html
- Europe intraday Reuters wrap: https://www.marketscreener.com/news/european-shares-gain-as-positive-earnings-outweigh-mideast-worries-ce7f58dfd18ef422
- Euro Stoxx 50 futures historical page: https://za.investing.com/indices/eu-stocks-50-futures-historical-data
- Germany 10Y bond historical page: https://za.investing.com/rates-bonds/germany-10-year-bond-yield-historical-data
- Tencent same-session quote: https://0700.hk/
- U.S. futures Reuters pre-market: https://www.investing.com/news/stock-market-news/us-stock-futures-rise-as-oil-dips-middle-east-tensions-linger-4658289
- Gold / silver rebound context: https://www.wsj.com/finance/commodities-futures/gold-steady-amid-likely-technical-recovery-8b97323c
- Monday gold / silver settle: https://www.wsj.com/finance/commodities-futures/gold-edges-higher-amid-signs-of-resilience-627248e3
- Monday oil settle: https://www.wsj.com/livecoverage/stock-market-today-dow-sp-500-nasdaq-05-04-2026/card/oil-prices-end-higher-following-flare-of-mideast-fighting-xjhkqsGurs2QI2dXLq4m
- BTC current price: https://fortune.com/article/price-of-bitcoin-05-05-2026/
- ETH current price: https://fortune.com/article/price-of-ethereum-05-05-2026/
- USD/CNH live rate: https://coincodex.com/forex/usd-cnh/
