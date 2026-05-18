# Investment Macro Daily Refresh - 2026-05-04

Heartbeat: US close carry

As of: 2026-05-04 05:32 Asia/Shanghai

US market date: 2026-05-01

Placement rule: Monday, May 4, 2026 in Asia/Shanghai is only the local heartbeat timestamp. There was no Sunday, May 3, 2026 U.S. cash session, so U.S. snapshot rows below still belong to the Friday, May 1, 2026 U.S. cash close. Japan rows still belong to Friday, May 1, 2026. Hong Kong and mainland China remain on Thursday, April 30, 2026 because Friday, May 1 was a holiday and no new cash session has occurred yet.

Backfill status at start: no new visible missed-window gap was found in the markdown chain before this run. Durable `nj_agent_heartbeat_run` / `nj_agent_backfill_task` inspection still could not run because the active local database remains unavailable.

Storage status: markdown fallback only. The active local database at `/Users/mac/Developer/Notion Journal/Notion Journal/db.sqlite3` is still 0 bytes, so durable targets `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event` were not available for write-back in this run.

## Verdict

The market still looks capable of holding near highs into Nvidia because the latest valid U.S. close is still Friday’s record-holding tape, but the setup is now more fragile than strong: Treasury refunding starts today, OPEC+ has already approved a June supply increase, and the June-risk thesis still runs through BOJ/JGB pressure plus crowded AI leadership rather than through any fresh weekend breakdown.

## Top Changes Since Previous Heartbeat

1. No new U.S. cash close exists beyond Friday, May 1, 2026, so this heartbeat correctly carries the May 1 session forward instead of misdating Sunday or Monday-local data as a new U.S. close.
2. OPEC+ added a new near-term oil catalyst. On Sunday, May 3, 2026, the seven OPEC+ countries said they will implement a `188 kbpd` production adjustment in June and meet again on `2026-06-07`, which modestly softens the immediate oil-shock tail without clearing the broader inflation risk.
3. The catalyst stack is now immediate rather than distant: Treasury financing estimates are due later on Monday, May 4, 2026 U.S. time, AMD reports Tuesday, Treasury’s refunding statement lands Wednesday, and DDOG / NET plus payrolls follow Thursday and Friday.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,230.12 | +21.11 / +0.29% | 2026-05-01 last-close | AP |
| US | 2Y Treasury yield | 3.88% | unchanged vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | 10Y Treasury yield | 4.39% | -1 bp vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | 30Y Treasury yield | 4.97% | -1 bp vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | VIX | 16.89 latest accessible official-close chain; 2026-05-01 pending official Cboe CSV refresh | -1.92 / -10.21% vs 2026-04-29 on latest official-close chain | 2026-04-30 official close / 2026-05-01 pending | Cboe source chain via FRED mirror; direct Cboe CSV still not retrievable in this run |
| HK / China | Hang Seng | 25,776.53 | market_closed; carry 2026-04-30 close after Labor Day holiday | 2026-04-30 last-close | Xinhua |
| HK / China | Shanghai Composite | 4,112.16 | market_closed; carry 2026-04-30 close after Labor Day holiday | 2026-04-30 last-close | Xinhua |
| Japan | Nikkei 225 | 59,513.12 | +228.20 / +0.38% | 2026-05-01 close | Xinhua |
| Japan | 10Y JGB yield | 2.5%+ zone | delayed; still near multi-decade highs | 2026-05-01 Asia session / carry | BOJ context; market follow-up |
| Europe | STOXX Europe 600 | 611.28 | +8.32 / +1.38% | 2026-04-30 last-close / 2026-05-04 carry | finanzen.net |
| Europe | Euro Stoxx 50 | 5,881.51 | +65.03 / +1.12% | 2026-04-30 last-close / 2026-05-04 carry | Investing.com |
| Europe | Germany 10Y Bund | 3.03% | roughly flat vs 2026-04-30 | 2026-05-01 Europe session / carry | Investing.com |
| Europe | UK 10Y Gilt | ~5.04% | elevated near highest close since 2008 | 2026-05-01 Europe session / carry | Reuters; WSJ |
| FX | EUR/USD | 1.1702 | +0.0022 vs 2026-04-28 ECB reference 1.1680 | 2026-04-30 official ECB reference / carry | ECB |
| Commodity / Crypto | BTC | ~78,231 | weekend spot; exact 24h move needs cleaner source pass | 2026-05-04 Asia run / U.S. weekend carry | CoinGecko |
| Commodity / Crypto | ETH | ~2,323 | weekend spot; exact 24h move needs cleaner source pass | 2026-05-04 Asia run / U.S. weekend carry | CoinGecko |
| Commodity / Crypto | Brent | 108.17 | -2.23 / -2.02% settle | 2026-05-01 settle | Reuters |
| Commodity / Crypto | WTI | 101.94 | -3.13 / -2.98% settle | 2026-05-01 settle | Reuters |
| Commodity / Crypto | Gold | 4,592 | -1.08% last verified | 2026-05-01 last verified quote / carry | Fortune |
| Commodity / Crypto | Silver | 74.73 | +1.34% last verified | 2026-05-01 last verified quote / carry | Fortune |

## Trade Thesis Watch List Refresh

Rule used here: `NJInvestmentModuleView.swift` currently exposes six enum-backed Trade Thesis tabs: `2026 Q1 SaaS overshoot`, `2026 Q1 US Trade`, `2026 Japan Trade`, `HK/China Tech AI Trade`, `HK/China High Yield Trade`, and `2026 Global AI Infrastructure`. This heartbeat carries all six tabs on their latest valid market-session dates instead of blanking any row or restamping them onto the Monday-local run date.

### 2026 Q1 SaaS overshoot

| Symbol | Monitor Date | Result Date | T+1 | T+2 | T+3 | Today Price | Change / State | High / Low Reference |
| --- | --- | --- | --- | --- | --- | ---: | --- | --- |
| DDOG | 2026-05-01 | 2026-05-07 BMO | Pending | Pending | Pending | $140.53 | +6.31% last-close | 52H $201.69 / 52W low $98.01 |
| MDB | 2026-05-01 | Est. 2026-06-03 | Pending | Pending | Pending | $263.46 | +5.04% last-close | 52H $444.72 / 52W low $169.26 |
| TEAM | 2026-05-01 | 2026-04-30 AMC | $88.88 +29.58% | Pending May 4 | Pending May 5 | $88.88 | +29.58% last-close | 52H $232.36 / 52W low $56.01 |
| NET | 2026-05-01 | 2026-05-07 AMC | Pending | Pending | Pending | $217.50 | +6.11% last-close | 52H $260.00 / 52W low $120.46 |
| SNOW | 2026-05-01 | Est. 2026-05-27 | Pending | Pending | Pending | $141.00 | +3.32% last-close | 52H $280.67 / 52W low $118.30 |

### 2026 Q1 US Trade required list

| Symbol | Monitor Date | Result Date | Today Price | Change / State | High / Low Reference |
| --- | --- | --- | ---: | --- | --- |
| QQQ | 2026-05-01 | Apple / AMD window | $674.13 | +1.0%; no index fade | prior session H/L ref $668.90 / $657.56 |
| SMH | 2026-05-01 | AMD T+1/T+2 | $509.70 | +0.6%; semis stayed bid | prior session H/L ref $507.79 / $495.02 |
| SPY | 2026-05-01 | Broad fade check | $720.75 | +0.3%; broad market held | prior session H/L ref $719.79 / $710.45 |
| SOXX | 2026-05-01 | AMD T+1/T+2 | $465.75 | +0.9%; close near high | prior session H/L ref $462.14 / $449.34 |
| AAPL | 2026-05-01 | 2026-04-30 AMC | May 1 close +3.3% | relief bid held | prior session H/L ref $275.94 / $268.14 |
| AMD | 2026-05-01 | 2026-05-05 AMC | May 1 close +1.7% | primary add trigger still pending the print | prior session H/L ref $354.95 / $332.64 |
| NVDA | 2026-05-01 | 2026-05-20 | May 1 close -0.6% | below 200; isolated weakness | prior session H/L ref $210.30 / $198.70 |
| MSFT | 2026-05-01 | 2026-04-29 AMC | May 1 close +1.6% | recovered; not a fade confirmation | prior session H/L ref $414.42 / $398.01 |
| META | 2026-05-01 | 2026-04-29 AMC | May 1 close -0.5% | weakest Mag 7 print reaction | prior session H/L ref $620.40 / $600.00 |
| AMZN | 2026-05-01 | 2026-04-29 AMC | May 1 close +1.3% | recovered from open; no fade trigger | prior session H/L ref $273.82 / $256.16 |
| GOOGL | 2026-05-01 | 2026-04-29 AMC | May 1 close +10.2% vs pre-earnings | clean beat still held | prior session H/L ref $385.84 / $365.83 |
| INTC | 2026-05-01 | Reported 2026-04-23 | May 1 close +5.4% | outlier strength | prior session H/L ref $94.49 / $91.50 |
| MU | 2026-05-01 | Reported 2026-03-18 | May 1 close +9.2% | AI infra still bid | prior session H/L ref $535.50 / $502.58 |
| AVGO | 2026-05-01 | Reported 2026-03-04 | May 1 close +25.9% | AI custom silicon still rewarded | prior session H/L ref $418.38 / $404.23 |
| QCOM | 2026-05-01 | 2026-04-29 AMC | May 1 close -1.4% | big gap did not fully hold | prior session H/L ref $186.89 / $163.56 |
| WDC | 2026-05-01 | 2026-04-30 AMC est. | May 1 close -0.6% | possible storage fade | prior session H/L ref $438.86 / $422.00 |
| JPM | 2026-05-01 | Reported 2026-04-14 | May 1 close +0.1% | stabilized, not leading | prior session H/L ref $314.10 / $306.57 |
| LLY | 2026-05-01 | 2026-04-30 BMO | May 1 close +3.1% | health-care growth still rewarded | prior session H/L ref $945.50 / $896.80 |
| COST | 2026-05-01 | Reported 2026-03-05 | May 1 close +1.2% | premium retail still rewarded | prior session H/L ref $1,017.69 / $996.32 |

### 2026 Japan Trade

| Symbol | Monitor Date | Result Date | Today Price | Change / State | High / Low Reference |
| --- | --- | --- | ---: | --- | --- |
| USD/JPY | 2026-04-30 | spot | 160 zone | pressure to 162 | ref 162 test / 139.89 |
| 7515 HK | 2026-04-30 | inverse Nikkei expression | HK$18.66 | Apr30 close carried | session H/L HK$19.01 / HK$18.52 |
| EWV | 2026-04-30 | inverse Japan ETF expression | $19.99 | Apr30 close carried | session H/L $20.62 / $19.81 |

### HK/China Tech AI Trade

| Symbol | Monitor Date | Result Date | Today Price | Change / State | High / Low Reference |
| --- | --- | --- | ---: | --- | --- |
| 9988 HK | 2026-04-27 | 2026-05-14 ind. | HK$126.50 | -2.84% carried | 52H HK$182.90 / 52W low HK$94.15 |
| 0700 HK | 2026-04-27 | 2026-05-13 20:00 | HK$478.60 | -3.00% carried | 52H HK$683.00 / 52W low HK$469.00 |
| 9888 HK | 2026-04-27 | 2026-05-27 ind. | HK$123.30 | -1.91% carried | 52H HK$155.50 / 52W low HK$75.00 |
| 3888 HK | 2026-04-30 | TBD | HK$22.80 | Apr30 close carried | session H/L HK$23.18 / HK$22.64 |
| 3896 HK | 2026-04-30 | TBD | HK$7.63 | Apr30 close carried | session H/L HK$7.96 / HK$7.44 |
| 0020 HK | 2026-04-30 | TBD | HK$1.98 | Apr30 close carried | session H/L HK$1.99 / HK$1.93 |
| USD/CNH | 2026-04-27 | Daily | 6.83 | reference only; no fresh holiday session | ref only |
| 3690 HK | 2026-04-30 | TBD | HK$83.25 | Apr30 close carried | session H/L HK$84.50 / HK$81.25 |
| 9618 HK | 2026-04-30 | TBD | HK$116.30 | Apr30 close carried | session H/L HK$117.50 / HK$115.60 |
| 1024 HK | 2026-04-30 | TBD | HK$42.90 | Apr30 close carried | session H/L HK$43.22 / HK$42.48 |
| 9999 HK | 2026-04-30 | TBD | HK$179.00 | Apr30 close carried | session H/L HK$180.30 / HK$177.70 |
| 9961 HK | 2026-04-30 | TBD | HK$417.80 | Apr30 close carried | session H/L HK$419.60 / HK$414.40 |
| 1211 HK | 2026-04-30 | TBD | HK$102.50 | Apr30 close carried | session H/L HK$109.10 / HK$102.10 |
| 3750 HK | 2026-04-30 | TBD | prior verified row kept | source refresh still needed | no clean same-session high/low pass in this run |

### HK/China High Yield Trade

| Basket | Latest Market Session | State |
| --- | --- | --- |
| Banks: `0005 HK`, `2388 HK`, `2888 HK`, `1398 HK`, `0939 HK`, `1288 HK`, `3988 HK` | 2026-04-30 | prior verified rows kept; next live refresh belongs to the next HK close |
| Dividends: `0941 HK`, `0728 HK`, `0883 HK`, `1088 HK`, `0002 HK`, `0006 HK`, `6823 HK`, `1044 HK`, `1378 HK` | 2026-04-30 | prior verified rows kept; no table-wide stale reset |

### 2026 Global AI Infrastructure

| Symbol | Monitor Date | Today Price | Change / State | High / Low Reference |
| --- | --- | ---: | --- | --- |
| URI | 2026-04-22 | $959.84 | Apr30 close carried | session H/L $959.84 / $945.66 |
| HRI | 2026-04-30 | $126.92 | Apr30 close carried | session H/L $126.92 / $124.17 |
| FCX | 2026-04-28 | $58.21 | prior verified row kept | 52H $70.97 / 52W low $34.45 |
| SCCO | 2026-04-30 | $171.69 | Apr30 close carried | 52H $218.85 / 52W low $84.13 |
| 2899 HK | 2026-04-15 | HK$37.98 | +0.74% prior verified row kept | 52H HK$46.98 / 52W low HK$16.70 |
| GEV | 2026-04-30 | $1,083.46 | Apr30 close carried | session H/L $1,094.00 / $1,066.61 |
| NEE | 2026-04-30 | $97.88 | Apr30 close carried | session H/L $98.03 / $94.44 |
| DUK | 2026-04-30 | $129.55 | Apr30 close carried | session H/L $129.84 / $126.11 |
| VST | 2026-04-30 | $157.84 | Apr30 close carried | session H/L $159.63 / $155.73 |
| ETN | 2026-04-27 | $416.77 | prior verified row kept | 52H $432.34 / 52W low $283.00 |
| SU FP | 2026-04-15 | EUR266.20 | -0.50% prior verified row kept | 52H EUR280.05 / 52W low EUR196.54 |
| ENR GR | 2026-04-15 | EUR169.32 | -0.96% prior verified row kept | 52H EUR171.94 / 52W low EUR56.04 |
| 6501 JP | 2026-04-28 | JPY5,220 | +5.31% prior verified row kept | 52H JPY6,039 / 52W low JPY2,590 |
| VRT | 2026-04-27 | $322.43 | prior verified row kept | 52H $330.30 / 52W low $80.51 |
| JCI | 2026-04-28 | $141.59 | prior verified row kept | 52H $146.49 / 52W low $80.19 |
| TT | 2026-04-28 | $425.47 | prior verified row kept | 52H $471.46 / 52W low $346.45 |
| ANET | 2026-04-30 | $172.71 | Apr30 close carried | session H/L $173.58 / $167.76 |
| CSCO | 2026-04-30 | $91.47 | Apr30 close carried | session H/L $91.67 / $89.32 |
| CIEN | 2026-04-30 | $527.58 | Apr30 close carried | session H/L $529.89 / $486.25 |
| 0763 HK | 2026-04-30 | HK$24.94 | Apr30 close carried | session H/L HK$25.20 / HK$24.22 |

## Watch-List Refresh Summary

- All six enum-backed Trade Thesis tabs in `NJInvestmentModuleView.swift` were refreshed or correctly carried on their last valid market-session dates.
- `2026 Q1 SaaS overshoot` and `2026 Q1 US Trade` remain anchored to the Friday, May 1, 2026 U.S. close because no later U.S. cash session exists yet.
- `2026 Japan Trade` stays on the April 30 expression rows while the broader Japan macro read still uses the May 1 Nikkei close and the elevated JGB signal.
- `HK/China Tech AI Trade` and `HK/China High Yield Trade` remain on April 27 to April 30 verified sessions because May 1 was a holiday and no later HK / mainland close exists.
- `2026 Global AI Infrastructure` kept all required rows populated; symbols without a cleaner same-session source kept their last verified values rather than reverting to `Needs refresh`.

## US Snapshot

- Friday, May 1, 2026 remains the latest valid U.S. cash close. AP reported the S&P 500 at `7,230.12`, up `0.29%`, and Reuters reported both the S&P 500 and Nasdaq finishing the week at record closing highs.
- Treasury’s official May 1 curve still reads `2Y 3.88%`, `10Y 4.39%`, and `30Y 4.97%`. That is softer than the prior day, but still not low enough to remove valuation friction.
- VIX is still populated per runbook, but the target May 1 official Cboe row is still pending direct CSV verification in this environment. The latest accessible official-close chain remains `16.89` for Thursday, April 30, 2026.
- Breadth still looks less convincing than the index level. Reuters’ Friday recap highlighted headline strength, while separate breadth commentary still describes an advance led by leadership rather than a fully broad market.

## HK / China Snapshot

- There is still no newer Hong Kong or mainland China cash session for this U.S.-close heartbeat. The correct carried market date remains Thursday, April 30, 2026.
- That leaves the China-beta read basically unchanged: no fresh holiday-gap downside shock, but also no reopening confirmation strong enough to improve the thesis.
- `USD/CNH`, `USDHKD`, and `HIBOR` still need a cleaner next-session pass.

## Japan Snapshot

- Japan remains the cleanest spillover risk for the next Asia open. The latest valid Nikkei close is still Friday, May 1, 2026 at `59,513.12`, up `0.38%`.
- The more important signal remains rates. The `10Y JGB` is still in the `2.5%+` zone, which keeps BOJ normalization and carry-trade stress active.
- The next hard official Japan checkpoints are the BOJ Summary of Opinions on `2026-05-12` and nationwide April CPI on `2026-05-22`.

## Europe Snapshot

- Europe remains a carry section because the latest clean continental cash close is still Thursday, April 30, 2026 after the May Day holiday.
- STOXX Europe 600 at `611.28` and Euro Stoxx 50 at `5,881.51` say Europe was firm into the break, but the more important macro message is still the rates backdrop.
- Germany’s 10Y Bund near `3.03%` and the U.K. 10Y gilt near `5.04%` say global duration pressure is still elevated even after the modest U.S. easing on May 1.

## Commodity / Crypto Snapshot

- Oil is the one meaningful cross-asset update since the prior carry note. OPEC+ said on May 3 that the seven participating countries will implement a `188 kbpd` production adjustment in June and meet again on `2026-06-07`, which modestly reduces the odds of a one-way supply shock.
- Friday’s verified settlements still matter more than weekend noise for the macro read: Brent settled at `108.17` and WTI at `101.94`.
- Crypto weekend spot remains firm rather than stressed, with BTC around `78.2K` and ETH around `2.32K`, but this run still did not retrieve a clean source for exact 24-hour changes.
- Gold and silver remain high enough to say macro hedging demand is still alive, not abandoned.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Supportive | The latest valid U.S. close still shows record-index resilience. | Treasury refunding May 4-6; payrolls May 8 |
| Rates And Curve | Mixed | U.S. yields eased on May 1, but JGB, Bund, and gilt pressure still keep the global rates channel restrictive. | Treasury financing estimates May 4; CPI May 12 |
| Credit Stress | Watch | Clean MOVE and same-session HY / IG spread refreshes remain incomplete. | Credit-spread refresh; rates-vol check |
| Consumer And Labor | Mixed | Softer oil helps, but labor still needs to cool without cracking. | Payrolls May 8; CPI May 12 |
| Earnings And Breadth | Supportive | Index highs still hold, but leadership remains crowded and breadth is not fully broad. | AMD May 5; DDOG/NET May 7; Nvidia May 20 |
| China Credit Impulse | Watch | No fresh China cash session has printed since the holiday window. | China CPI/PPI May 11; China reopening flow |
| FX And Property Stress | Watch | CNH, HKD, and HK liquidity still need a cleaner live-market pass. | USD/CNH; USDHKD; HIBOR |
| BOJ And JGB | Stress | Japan’s rates channel remains the clearest unresolved macro stress point. | BOJ Summary May 12; BOJ June 15-16 |
| JPY Carry Stress | Stress | Elevated JGB yields keep yen / carry unwind risk active. | USD/JPY and JGB follow-through |
| Crypto Liquidity | Mixed | Crypto is firm, but it is still following rather than leading risk appetite. | ETF flows; cross-asset follow-through |
| Oil And Metals | Watch | OPEC+ softened immediate oil-risk tails, but metals still point to persistent macro hedging demand. | EIA Wednesday; OPEC+ June 7; CPI May 12 |

## Thesis Check

Confirming:

- The market can still hold near all-time highs into Nvidia because the latest valid U.S. close still did.
- Japan still validates the BOJ / JGB / carry-stress side of the June-risk thesis.
- Treasury refunding and AMD / DDOG / NET now provide near-term tests before Nvidia rather than leaving the tape on pure drift.

Weakening:

- OPEC+ moving to a June production adjustment modestly reduces the odds of a straight-line oil shock.
- No fresh weekend price action delivered a new downside confirmation for the June pullback thesis on its own.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Probability | Base Case | Upside / Bull Case | Downside / Bear Case | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Treasury quarterly refunding financing estimates | 2026-05-04 | scheduled for 3:00 p.m. ET | Feb. 2, 2026 financing estimates | no clean public probability series; term premium remains elevated | Heavier borrowing need, but no immediate coupon-size shock | Manageable estimate lets the 10Y stay near Friday’s 4.39% close | Bigger borrowing estimate or more alarming guidance lifts long-end yields again | 10Y / 30Y UST, duration equities, USD | Confirmed by a calm long-end reaction; invalidated by a fresh term-premium jump | U.S. Treasury |
| AMD earnings | 2026-05-05 | AI GPU / CPU demand should remain solid; exact street line needs cleaner source pass | prior report already embedded strong AI expectations | semis still priced for good demand, not perfect numbers | Good print keeps semis bid without needing a huge beat | Data-center and MI roadmap commentary extends AI leadership | Any guide wobble or AI-demand caution weakens the pre-Nvidia hold thesis | SOXX, SMH, QQQ, NVDA sympathy | Confirmed by strong DC/AI commentary; invalidated by guide wobble | company IR; market setup |
| Treasury quarterly refunding announcement | 2026-05-06 | coupon sizes broadly expected steady | Feb. 4, 2026 statement kept auction sizes unchanged | Reuters preview points to another steady-coupon quarter | No duration surprise | Steady sizing helps equities absorb inflation noise | Heavier long-end load re-tightens financial conditions | Long bonds, REITs, growth stocks | Confirmed by steady sizing language; invalidated by heavier long-end issuance | U.S. Treasury; Reuters |
| Datadog and Cloudflare earnings | 2026-05-07 | key SaaS overshoot window | TEAM already delivered a strong first proof point | software beta needs beat-and-hold follow-through | At least one clean reward signal keeps the SaaS overshoot trade alive | Beat-and-hold broadens the SaaS rebound beyond TEAM | Beat-but-fade damages the overshoot thesis quickly | DDOG, NET, IGV, software beta | Confirmed by strong T+1 / T+2 holds; invalidated by good numbers sold on impact | company IR calendars |
| U.S. payrolls, April | 2026-05-08 | 178K consensus; 4.3% unemployment rate consensus | Mar. payrolls +178K; unemployment 4.3% | no clean prediction-market series used in this run | Slower but still healthy labor data | Payrolls cool without labor damage, easing rate pressure | Hot payrolls revive higher-for-longer fears; weak payrolls revive hard-landing fears | Front end, USD, small caps, cyclicals | Confirmed by orderly cooling; invalidated by reacceleration or a labor crack | BLS |
| China CPI / PPI, April | 2026-05-11 | release date confirmed for May 11; exact consensus still needs cleaner source pass | Mar. CPI 1.0% y/y; Mar. PPI 0.5% y/y | no clean market-implied pricing source available | Benign CPI with producer inflation still marginally positive | Better domestic-demand mix helps HSI, CNH, and industrial cyclicals | Softer CPI and PPI revive China-lag concerns | HSI, CNH, industrial metals | Confirmed by stable core and non-negative PPI; invalidated by a broader disinflation relapse | NBS release calendar |
| Fed-chair transition / Warsh Senate vote window | week of 2026-05-11 | vote timing still points to the week of May 11 | committee advanced nomination on 2026-04-29 | no clean public probability series; policy premium still lives in the long end | Process advances without immediate repricing shock | Confirmation is orderly and independence concerns cool | Confirmation turns into a louder fight over Fed independence | USTs, USD, banks, long-duration tech | Confirmed by calm rhetoric and pricing; invalidated by Senate conflict or policy-signaling shock | Reuters |
| BOJ Summary of Opinions | 2026-05-12 | qualitative release at 8:50 a.m. JST | Apr. 27-28 BOJ hold at 0.75% | no formal probability series retrieved; rates market still biased toward further tightening pressure | Still gradual tightening bias without immediate action | Tone is less urgent and JGB pressure eases | Tone validates faster normalization and pushes JGBs / JPY higher | JGBs, JPY, Nikkei carry trades | Confirmed by measured language; invalidated by stronger inflation / FX urgency | BOJ |
| U.S. CPI, April | 2026-05-12 | headline April CPI releases at 8:30 a.m. ET; exact consensus still needs cleaner source pass | Mar. CPI 3.3% y/y; core 2.6% y/y | June FOMC hold remains the dominant base case | Headline stays firm while core only eases slowly | Core services soften enough to keep June FOMC balanced | Headline and core both re-accelerate | USTs, USD, Nasdaq, gold | Confirmed by softer core services; invalidated by broad inflation stickiness | BLS; Federal Reserve context |
| Nvidia Q1 FY2027 earnings | 2026-05-20 | reports at 5:00 p.m. ET; prior quarter revenue $68.1B and Q1 guide $78.0B +/- 2% | Q4 FY2026 revenue $68.1B | positioning remains crowded | Beat-and-maintain is enough to keep the tape together | Beat-and-raise broadens leadership and extends the hold-near-highs thesis | Guide wobble or softer AI demand commentary hits crowded positioning hard | Nasdaq, SOX, S&P breadth | Confirmed by strong data-center demand and guide confidence; invalidated by growth or margin wobble | Nvidia IR |
| Japan CPI, April | 2026-05-22 | nationwide April CPI due May 22 | Mar. nationwide core CPI 1.8% y/y | no clean market-implied probability series available | Sticky-enough inflation keeps BOJ normalization alive but gradual | Softer CPI cools JGB pressure and carry stress | Hot CPI validates another BOJ step sooner | JGBs, JPY, Nikkei | Confirmed by contained services and core; invalidated by hotter underlying inflation | Statistics Bureau of Japan |
| OPEC+ follow-up meeting | 2026-06-07 | seven countries will review market conditions after the June adjustment | May 3 decision set a 188 kbpd June adjustment | monthly review format keeps policy flexible | Incremental supply stays manageable and data-dependent | Added barrels keep oil from re-spiking through June | Geopolitics or compliance slippage overwhelms the supply increase | Brent, WTI, inflation breakevens, EM FX | Confirmed by stable crude; invalidated by renewed oil squeeze | OPEC |
| BOJ meeting | 2026-06-15 to 2026-06-16 | policy rate unchanged in base case | Apr. 27-28 hold at 0.75% | no precise market-implied hike probability captured; rates pressure still skews hawkish | Hold with tightening bias intact | Oil eases, yen stabilizes, BOJ waits | Inflation and FX pressure pull BOJ closer to another hike | JGBs, JPY, Nikkei, global carry | Confirmed by calmer JGBs and FX; invalidated by hotter CPI and renewed yen weakness | BOJ |
| FOMC meeting | 2026-06-16 to 2026-06-17 | no near-term move in base case | Apr. 28-29 hold | market still leans heavily toward hold | Hold with data dependence | Softer CPI/PCE and slower jobs allow a more balanced tone | Oil-plus-core persistence keeps the Fed more hawkish than equities want | USTs, USD, equities, gold, BTC | Confirmed by softer inflation and labor data; invalidated by persistent inflation pressure | Federal Reserve |

## Probability-Weighted Policy Scenarios

### Treasury Refunding on May 4-6, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Financing estimates rise but coupon sizes stay unchanged | Long-end pressure remains elevated but does not break higher immediately |
| Bearish supply surprise | 25% | Borrowing estimate or guidance signals earlier coupon-size increases | Term premium rises and duration-sensitive equities lag |
| Supportive mix | 15% | Manageable estimate with steady sizing and calm language | 10Y and 30Y yields stabilize further |

### Fed-Chair Transition / Warsh Vote Path

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Full Senate confirms on time or close enough that transition stays orderly | Mild policy premium stays in long-end yields |
| Relief case | 15% | Confirmation is smooth and independence concerns cool | Long-end and dollar calm modestly |
| Stress case | 25% | Confirmation fight or rhetoric turns messy around Fed independence | Macro risk premium rises, especially for duration assets |

### BOJ on June 15-16, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 55% | Hold at 0.75% with tightening bias intact | JGBs stay pressured and carry remains fragile |
| Calmer hold | 15% | Hold and downplay near-term urgency | JGB yields ease and Nikkei pressure fades |
| More hawkish hold | 30% | Hold but validate another hike soon | JGB yields and JPY jump; risk assets wobble |

### FOMC on June 16-17, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 65% | Hold with data dependence and no clean easing signal | Highs can hold, but rates stay a valuation headwind |
| Dovish hold | 15% | Hold and lean toward softer labor / inflation conditions | Duration and quality growth outperform |
| Hawkish hold | 20% | Hold with stronger inflation concern after energy pass-through | 10Y rises again and June pullback risk increases |

## Next 7 Days

- 2026-05-04: U.S. Treasury quarterly refunding financing estimates.
- 2026-05-05: U.S. international trade release from BEA; AMD earnings.
- 2026-05-06: U.S. Treasury quarterly refunding announcement.
- 2026-05-07: Datadog and Cloudflare earnings; BOJ March meeting minutes.
- 2026-05-08: U.S. payrolls for April.
- 2026-05-11: China CPI / PPI for April; Warsh Senate vote window.
- 2026-05-12: BOJ Summary of Opinions; U.S. CPI for April.

## Follow-Up Tasks

- Expose durable storage for `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event`; the active local SQLite file remains empty.
- Backfill every required market snapshot line from `2026-01-01` forward once durable storage exists.
- Verify the official Cboe `VIX_History.csv` row for the Friday, May 1, 2026 U.S. close; keep May 1 marked pending official Cboe refresh until the file is directly fetchable.
- Refresh clean same-session rows for `USD/CNH`, `USDHKD`, `HIBOR`, MOVE, and clean U.S. HY / IG spread prints.
- Refresh the `3750 HK` CATL row with a cleaner same-session source pass on the next HK close heartbeat.
- Decide whether non-trade-tab watch lists elsewhere in `NJInvestmentModuleView.swift` should be added to this automation scope; the current run covered the six enum-backed Trade Thesis tabs required by the visible Trade Thesis section.

## Backfill Status

- No durable `nj_agent_heartbeat_run` history was available because the active local database file is still empty, so missed-window detection still could not be computed from stored rows.
- No durable `nj_agent_backfill_task` rows could be created for the same reason.
- Visible markdown fallback history shows the Sunday, May 3, 2026 Asia-close heartbeat and the Sunday, May 3, 2026 U.S.-close backfill are already present, so this run did not expose a new visible missed-window gap.
- Markdown-tracked pending backfills remain:
- `pending`: heartbeat history bootstrap for missed Asia-close and U.S.-close windows from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: market snapshot historical backfill for required lines from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: official VIX verification for the `2026-05-01` U.S. close, reason `official_source_not_yet_updated`.

## Source Links

- Prior heartbeat note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-03 Asia Close.md`
- Prior U.S.-close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-03.md`
- AP Friday, May 1, 2026 U.S. close recap: https://apnews.com/article/ee0fd67a1f14608ef46165f6dd693592
- Reuters Friday, May 1, 2026 U.S. close recap: https://ca.marketscreener.com/news/s-p-500-nasdaq-end-higher-notch-weekly-gains-after-earnings-heavy-week-ce7f58d9de8af02d
- U.S. Treasury daily par yield curve rates: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_yield_curve
- Treasury refunding document hub: https://home.treasury.gov/policy-issues/financing-the-government/quarterly-refunding/most-recent-quarterly-refunding-documents
- Cboe VIX historical-data page: https://www.cboe.com/tradable-products/vix/vix-historical-data
- FRED VIXCLS page: https://fred.stlouisfed.org/series/VIXCLS
- Accessible Apr. 30 VIX mirror: https://www.ideal-investisseur.fr/marches/vix.html
- BLS payroll release schedule: https://www.bls.gov/schedule/news_release/empsit.htm
- BLS CPI release schedule: https://www.bls.gov/schedule/news_release/cpi.htm
- BEA release schedule: https://www.bea.gov/news/schedule
- Federal Reserve FOMC calendar: https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm
- BOJ meeting schedule: https://www.boj.or.jp/en/mopo/mpmsche_minu/index.htm
- Japan CPI release schedule: https://www.stat.go.jp/english/data/cpi/1582.htm
- China NBS release calendar: https://www.stats.gov.cn/english/PressRelease/ReleaseCalendar/202512/t20251226_1962154.html
- OPEC May 3, 2026 statement: https://www.opec.org/pr-detail/1779602-3-may-2026.html
- EIA weekly petroleum report schedule: https://www.eia.gov/petroleum/supply/weekly/schedule.php
- Nvidia Q1 FY2027 call notice: https://investor.nvidia.com/news/press-release-details/2026/NVIDIA-Sets-Conference-Call-for-First-Quarter-Financial-Results/default.aspx
