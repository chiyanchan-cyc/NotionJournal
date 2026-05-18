# Investment Macro Daily Refresh - 2026-05-01

Heartbeat: US close

As of: 2026-05-01 06:21 Asia/Shanghai

US market date: 2026-04-30

Placement correction: this heartbeat ran on Friday, May 1, 2026 in Asia/Shanghai, but the US snapshot rows below belong to the Thursday, April 30, 2026 US cash-session date.

Storage status: markdown fallback only. The active local database at `/Users/mac/Developer/Notion Journal/Notion Journal/db.sqlite3` is still 0 bytes, so durable targets `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event` were not available for write-back in this run.

## Verdict

The market held and even stretched to fresh highs on the April 30, 2026 US close, but the thesis only partly improved: earnings and better-than-feared growth bought time into Nvidia, while sticky inflation, unresolved VIX verification, and BOJ/JGB pressure still keep June pullback risk alive.

## Top Changes Since Previous Heartbeat

1. Thursday, April 30, 2026 ended with a real upside reset in US risk assets: the S&P 500 rose 1.0% to 7,209.01, the Dow jumped 1.6% to 49,652.14, and the Nasdaq closed at another record, supported by Alphabet-led earnings.
2. The macro data mix was better for growth than the market feared but worse for clean disinflation. BEA reported Q1 2026 real GDP at 2.0% SAAR versus 0.5% in Q4 2025, while March core PCE still ran at 0.3% m/m and 3.2% y/y.
3. The cross-asset stress channel eased, but did not disappear. The 10Y Treasury slipped 2 bps to 4.40%, Brent settled down to $114.01 after a spike above $126, and Europe finished firmer after the ECB and BOE held, but Japan remains a live rates-risk handoff into the next Asia session.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,209.01 | +73.06 / +1.02% | 2026-04-30 last-close | AP |
| US | 10Y Treasury yield | 4.40% | -2 bps vs 2026-04-29 | 2026-04-30 official close | U.S. Treasury |
| US | 2Y Treasury yield | 3.88% | -4 bps vs 2026-04-29 | 2026-04-30 official close | U.S. Treasury |
| US | 30Y Treasury yield | 4.98% | unchanged vs 2026-04-29 | 2026-04-30 official close | U.S. Treasury |
| US | 10Y real yield | 1.94% | -2 bps vs 2026-04-29 | 2026-04-30 official close | U.S. Treasury |
| US | VIX | 17.83 | latest directly verifiable official Cboe close still 2026-04-28; 2026-04-30 official CSV row pending direct fetch | 2026-04-28 official close / 2026-04-30 pending official Cboe refresh | Cboe historical-data page |
| HK / China | Hang Seng | 25,776.53 | -1.28% | 2026-04-30 last-close | Xinhua |
| HK / China | Shanghai Composite | 4,112.16 | +0.11% | 2026-04-30 last-close | Xinhua |
| Japan | Nikkei 225 | 59,284.92 | -632.54 / -1.06% | 2026-04-30 last-close | Xinhua |
| Japan | 10Y JGB yield | about 2.50% | about +4 bps vs 2026-04-28 | 2026-04-30 last-close | Trading Economics |
| Europe | STOXX Europe 600 | about 1% higher | rebound after ECB / BOE holds | 2026-04-30 close | Trading Economics |
| Europe | Euro Stoxx 50 | about +0.6% | rebound after ECB / BOE holds | 2026-04-30 close | Trading Economics |
| Europe | Germany 10Y Bund | 3.05% | lower on the day, still near 2011 highs | 2026-04-30 close | Trading Economics |
| Europe | UK 10Y Gilt | 5.00% | lower on the day after BOE hold | 2026-04-30 close | Trading Economics |
| FX | EUR/USD | 1.1706 | last official ECB reference carry | 2026-04-29 official reference / 2026-04-30 live follow-up incomplete | ECB |
| Commodity / Crypto | BTC | 76,316.44 | -1.09% vs prior day | 2026-04-30 08:45 ET intraday | Fortune |
| Commodity / Crypto | ETH | 2,265.02 | -2.16% vs prior day | 2026-04-30 08:45 ET intraday | Fortune |
| Commodity / Crypto | Brent | 114.01 | -3.41% settle; intraday high 126.41 | 2026-04-30 settle | Reuters / WSJ |
| Commodity / Crypto | WTI | 105.07 | -1.7% settle | 2026-04-30 settle | WSJ |
| Commodity / Crypto | Gold | 4,614.70 | +69.50 / +1.53% | 2026-04-30 close | WSJ |
| Commodity / Crypto | Silver | 73.534 | +1.55% | 2026-04-30 close | WSJ |

## Trade Thesis Watch List Refresh

Rule used here: when a clean April 30, 2026 same-session quote-plus-range pair was not retrievable from a reliable source in this environment, the prior visible row was preserved and a symbol-level follow-up remained open instead of blanking the row.

| Thesis | Symbol | Monitor Date | 52H | 52W Low | Today Price | Daily % |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| SaaS Overshoot | DDOG | 2026-04-29 | $201.69 | $98.01 | $133.98 | +1.85% |
| SaaS Overshoot | MDB | 2026-04-29 | $444.72 | $148.88 | $258.29 | +0.03% |
| SaaS Overshoot | TEAM | 2026-04-30 | $242.00 | $56.01 | $68.21 | -3.23% |
| SaaS Overshoot | NET | 2026-04-30 | $260.00 | $117.07 | $204.97 | -3.30% |
| SaaS Overshoot | SNOW | 2026-04-29 | $280.67 | $118.30 | $141.22 | -0.94% |
| China AI | BIDU | 2026-04-27 | $165.30 | $81.17 | $128.01 | -0.54% |
| China AI | BABA | 2026-04-27 | $192.67 | $103.71 | $132.52 | -2.43% |
| Global AI Infrastructure | FCX | 2026-04-28 | $70.97 | $34.45 | $58.21 | -3.90% |
| Global AI Infrastructure | SCCO | 2026-04-28 | $218.85 | $84.13 | $189.32 | prior row kept |
| Global AI Infrastructure | NEE | 2026-04-28 | $86.29 | $63.88 | $83.23 | prior row kept |
| Global AI Infrastructure | DUK | 2026-04-28 | $132.50 | $111.22 | $131.82 | prior row kept |
| Global AI Infrastructure | VST | 2026-04-28 | $219.82 | $9.96 | $162.94 | prior row kept |
| Global AI Infrastructure | ETN | 2026-04-27 | $432.34 | $283.00 | $416.77 | -1.69% |
| Global AI Infrastructure | VRT | 2026-04-27 | $330.30 | $80.51 | $322.43 | -0.32% |
| Global AI Infrastructure | JCI | 2026-04-28 | $146.49 | $80.19 | $141.59 | -1.25% |
| Global AI Infrastructure | TT | 2026-04-28 | $471.46 | $346.45 | $425.47 | -1.06% |

## Watch-List Refresh Summary

- The required US SaaS overshoot list stayed row-complete, with `TEAM` and `NET` refreshed to the April 30, 2026 US market-session date.
- `DDOG`, `MDB`, and `SNOW` kept prior verified rows because I did not retrieve a clean same-session April 30 close-plus-range pair in this environment.
- The non-SaaS thesis rows were preserved rather than degraded to `Needs refresh`, and each source gap remains a symbol-level follow-up instead of a table-wide failure.

## US Snapshot

- The April 30, 2026 US close was a genuine risk-on session rather than just a hold. AP reported the S&P 500 up 1.02% to 7,209.01, the Dow up 1.62% to 49,652.14, and the Nasdaq up 0.88% to 24,892.31.
- Earnings did the heavy lifting. Alphabet's results helped offset the geopolitical drag that had briefly pushed oil above $126 earlier in the day.
- The macro data mix mattered just as much. BEA's advance GDP estimate showed Q1 growth rebounding to 2.0% SAAR from 0.5% in Q4 2025, which reduced immediate hard-landing fear.
- Inflation did not give a full all-clear. BEA's March personal income and outlays release showed headline PCE up 0.7% m/m and core PCE up 0.3% m/m, with core PCE still at 3.2% y/y.
- The Treasury curve reflected that mixed read. Official Treasury closes showed 2Y at 3.88%, 10Y at 4.40%, and 30Y unchanged at 4.98%, which is better than Wednesday's stress but still not a genuine valuation reset.
- VIX remains populated per runbook, but not fully refreshed. The direct Cboe daily CSV could not be fetched in this environment, so the note keeps the latest directly verifiable official close, 17.83 for April 28, 2026, and leaves April 30 pending official Cboe refresh.

## HK / China Snapshot

- The most recent closed Asia session is still Thursday, April 30, 2026. Hong Kong closed weaker, with the Hang Seng down 1.28% to 25,776.53, while the Shanghai Composite added 0.11% to 4,112.16.
- That is still a mixed China read rather than a breakdown. Mainland resilience helps the "hold into Nvidia" leg, but Hong Kong's weaker tape says beta is not broadening cleanly.
- USD/CNH, USDHKD, and HIBOR still need a cleaner close-quality refresh for the cross-border liquidity read.

## Japan Snapshot

- Japan remains the cleanest macro risk handoff into the next Asia session. The Nikkei 225 fell 1.06% on April 30, 2026, and the 10Y JGB yield pushed to about 2.5%, around the highest level since 1997.
- That means the BOJ / JGB / carry channel is still confirming, not invalidating, the June-risk side of the thesis.

## Europe Snapshot

- Europe finished better than the Asia-close handoff implied. Trading Economics reported the STOXX 600 up about 1% and the Euro Stoxx 50 up about 0.6% after the ECB and BOE both held rates steady and oil retreated from its highs.
- Even so, the rates message remains restrictive rather than easy. Germany's 10Y Bund still sat near 3.05%, close to multi-year highs, and the UK 10Y gilt remained around 5.00%.
- The ECB and BOE both chose to hold, but neither gave markets a clean dovish reset. That keeps Europe from becoming a reliable shock absorber if Japan or US inflation re-tightens the global rates narrative.

## Commodity / Crypto Snapshot

- Oil was the main intraday stress channel and then partially retraced. Reuters and the WSJ reported Brent spiking above $126 before settling at $114.01 and WTI settling at $105.07.
- That pullback helped equities and Treasuries on the day, but it did not erase the underlying energy-supply risk.
- Crypto stayed mixed. Fortune's early US-day prints showed BTC at $76,316.44, down 1.09% day over day, and ETH at $2,265.02, down 2.16%.
- Precious metals bounced. WSJ reported gold finishing April 30 at $4,614.70 and silver at $73.534, both higher on the day after the prior post-Fed slide.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Supportive | New index highs and better breadth at the index level bought time into Nvidia. | Treasury refunding May 4-6; payrolls May 8 |
| Rates And Curve | Mixed | Treasury yields eased modestly, but 10Y at 4.40% is still restrictive rather than easy. | Payrolls May 8; CPI May 12 |
| Credit Stress | Watch | Same-session MOVE and clean HY/IG spread refresh still were not available in this run. | Credit and rates-vol refresh |
| Consumer And Labor | Mixed | GDP improved, but sticky March PCE says the growth/inflation mix is not clean. | Payrolls May 8; CPI May 12 |
| Earnings And Breadth | Supportive | Alphabet-led earnings extended the tape, but AI concentration risk still matters into Nvidia. | Nvidia May 20; breadth follow-through |
| China Credit Impulse | Mixed | Shanghai held up, but Hong Kong still lagged and FX/liquidity cross-checks remain incomplete. | China CPI/PPI May 9; activity and credit data |
| FX And Property Stress | Watch | CNH and HKD liquidity channels still need cleaner same-session verification. | USD/CNH, USDHKD, HIBOR refresh |
| BOJ And JGB | Stress | Japan's rates channel remains the clearest unresolved macro risk. | BOJ Summary of Opinions May 12; BOJ June 15-16 |
| JPY Carry Stress | Stress | Higher JGB yields still threaten risk appetite spillover into Asia. | USD/JPY and JGB reopening flow |
| Crypto Liquidity | Mixed | BTC and ETH softened while equities rallied, which argues against broad speculative easing. | ETF flow and cross-asset risk response |
| Oil And Metals | Watch | Oil settled well off its highs, but the geopolitical supply shock is still live. | Treasury refunding; CPI; Hormuz / OPEC headlines |

## Thesis Check

Confirming:

- The market can still hold near highs into Nvidia; April 30 strengthened that leg materially.
- The BOJ / JGB channel remains unresolved and still argues for higher June pullback risk.
- Sticky inflation data means the Fed path is not cleanly easing even after a good equity day.

Weakening:

- The US tape improved more than the bearish June-risk case would want, with records in both the S&P 500 and Nasdaq.
- Oil's reversal off the $126 spike prevented a more obvious stagflation stress handoff.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Probability | Base Case | Upside / Bull Case | Downside / Bear Case | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| U.S. Treasury quarterly refunding financing estimates | 2026-05-04 | No major coupon shock expected | Feb. 2, 2026 financing estimates | Market is sensitive to term-premium risk after April's duration pressure | Heavy but manageable supply | Stable funding needs help long-end yields keep easing | Larger borrowing need or duration-heavy tone lifts term premium again | 10Y / 30Y UST, duration equities, USD | Confirmed by stable issuance mix; invalidated by a fresh long-end selloff | U.S. Treasury |
| JOLTS, March | 2026-05-05 | consensus needs refresh | prior release needs refresh in this environment | Labor cooling without a break is the desired path | Openings keep drifting lower without signaling labor stress | Softer openings ease rate pressure | Sticky openings keep wage/inflation fears alive | Front end, cyclicals, small caps | Confirm if labor cools orderly; invalidate if demand re-accelerates | BLS |
| U.S. Treasury quarterly refunding announcement | 2026-05-06 | Coupon sizes broadly expected to stay steady | Feb. 4, 2026 statement | Long-end is still the key macro valve | No shock to auction sizes or mix | Supply profile is easier than feared and 10Y drifts lower | Heavier duration burden re-tightens financial conditions | Long bonds, REITs, high-multiple growth | Confirmed by calm post-announcement price action; invalidated by a term-premium jump | U.S. Treasury |
| U.S. payrolls, April | 2026-05-08 | consensus needs refresh in this environment | +178K; unemployment 4.3% | Market wants a slower-but-still-positive labor print | Moderate cooling, not contraction | Payrolls cool with stable unemployment and softer wages | Hot payrolls revive higher-for-longer; weak payrolls revive hard-landing fear | Front end, USD, small caps, cyclicals | Confirmed by orderly cooling; invalidated by reacceleration or labor break | BLS |
| China CPI / PPI | 2026-05-09 | consensus needs refresh | prior low-inflation backdrop | Market wants evidence that PMI resilience can broaden | Benign inflation and only mild producer-price drag | Better domestic-demand mix helps HSI, CNH, and miners | Deeper disinflation revives China-lag concerns | HSI, CNH, copper, miners | Confirmed by firmer domestic-demand components; invalidated by weak inflation breadth | NBS calendar |
| BOJ Summary of Opinions | 2026-05-12 | qualitative release | Apr. 27-28 BOJ hold | Market is listening for how close the BOJ is to another hike | Still gradual tightening bias | Language is less urgent and JGB pressure eases | Language validates faster normalization and keeps JGBs under pressure | JGBs, JPY, Nikkei carry trades | Confirmed by a measured tone; invalidated by stronger inflation / FX urgency | BOJ |
| U.S. CPI, April | 2026-05-12 | consensus needs refresh in this environment | March CPI 3.3% y/y | Core path matters more than headline oil noise | Headline firm, core only slowly easing | Core cools enough to keep June FOMC balanced | Oil spillover broadens and inflation re-accelerates | USTs, USD, Nasdaq, gold | Confirmed by softer core services; invalidated by broad inflation stickiness | BLS |
| Nvidia Q1 FY2027 earnings | 2026-05-20 | consensus needs refresh | prior quarter revenue $68.1B; guide $78.0B +/- 2% | Positioning remains crowded into the print | Beat-and-maintain is enough to keep the tape together | Beat-and-raise broadens leadership and validates the highs | Guide wobble or softer AI commentary hits crowded positioning | Nasdaq, SOX, S&P breadth | Confirmed by strong data-center demand and confident guide; invalidated by growth or margin wobble | Nvidia IR |
| Japan CPI | 2026-05-22 | consensus needs refresh | prior print still elevated | JGB market sensitivity remains high | Sticky inflation keeps BOJ normalization alive but gradual | Softer CPI cools JGB pressure and JPY-carry stress | Hot CPI validates another BOJ tightening step sooner | JGBs, JPY, Nikkei | Confirmed by contained services and core; invalidated by hotter underlying inflation | Statistics Bureau of Japan |
| U.S. GDP second estimate and Personal Income / Outlays, April | 2026-05-28 | next official release date confirmed | Apr. 30 releases showed Q1 GDP 2.0% SAAR and Mar. core PCE 0.3% m/m | Market will reassess whether April inflation cooled after the March stickiness | Growth holds and inflation cools modestly | Softer inflation reopens easing hope | Sticky inflation with decent growth keeps rates elevated | USTs, USD, growth stocks | Confirmed by cooler monthly core PCE; invalidated by another sticky print | BEA |
| BOJ meeting | 2026-06-15 to 2026-06-16 | policy rate unchanged in base case | Apr. 27-28 hold | JGB market still leans toward more pressure than less | Hold with tightening bias intact | Oil eases, yen stabilizes, BOJ waits | Inflation and FX pressure pull BOJ closer to another hike | JGBs, JPY, Nikkei, global carry | Confirmed by calmer JGBs and FX; invalidated by hotter CPI and renewed yen weakness | BOJ |
| FOMC meeting | 2026-06-16 to 2026-06-17 | no near-term move in base case | Apr. 28-29 hold | Market will arrive focused on energy pass-through and core inflation stickiness | Hold with data dependence | Softer inflation and labor allow a more balanced tone | Oil-plus-core persistence keeps the Fed more hawkish than equities want | USTs, USD, equities, gold, BTC | Confirmed by softer CPI/PCE and calmer oil; invalidated by persistent inflation pressure | Federal Reserve |

## Probability-Weighted Policy Scenarios

### Treasury Refunding on May 4-6, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Manageable financing mix with no big duration surprise | Long-end pressure eases modestly but does not disappear |
| Bearish supply surprise | 25% | Heavier long-end burden or worse fiscal tone | Term premium rises again and rate-sensitive equities lag |
| Supportive mix | 15% | Smaller burden or better demand support | 10Y and 30Y stabilize faster, helping growth valuation |

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
- 2026-05-05: U.S. JOLTS for March.
- 2026-05-06: U.S. Treasury quarterly refunding announcement.
- 2026-05-08: U.S. payrolls for April.
- 2026-05-09: China CPI / PPI.

## Follow-Up Tasks

- Expose durable storage for `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event`; the active local SQLite file remains empty.
- Backfill every required market snapshot line from `2026-01-01` forward once durable storage exists.
- Verify the official Cboe `VIX_History.csv` row for the April 30, 2026 US close; keep Apr. 30 marked pending official Cboe refresh until the file is directly fetchable.
- Refresh same-session April 30 close-plus-range rows for `DDOG`, `MDB`, and `SNOW`.
- Refresh exact same-session rows for `BIDU`, `BABA`, `FCX`, `SCCO`, `NEE`, `DUK`, `VST`, `ETN`, `VRT`, `JCI`, and `TT`.
- Refresh same-session `USD/CNH`, `USDHKD`, `HIBOR`, MOVE, and clean US HY / IG spread prints.
- Refresh exact consensus values for April payrolls, April CPI, China CPI/PPI, Japan CPI, and Treasury refunding dealer expectations.

## Backfill Status

- No durable `nj_agent_heartbeat_run` history was available because the active local database file is empty, so missed-window detection still could not be computed from stored rows.
- No durable `nj_agent_backfill_task` rows could be created for the same reason.
- The markdown note chain shows the expected `2026-04-30 Asia Close` heartbeat exists, so no new missed-window gap was evident in the visible markdown fallback history before this run.
- Markdown-tracked pending backfills remain:
- `pending`: heartbeat history bootstrap for missed Asia-close and US-close windows from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: market snapshot historical backfill for required lines from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: official VIX verification for the `2026-04-30` US close, reason `official_source_not_yet_updated`.

## Source Links

- Prior Asia close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-04-30 Asia Close.md`
- Prior US close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-04-30.md`
- AP US close recap for Thursday, April 30, 2026: https://apnews.com/article/4e1442eeb72e72fc921e6804287d2b89
- BEA GDP advance estimate, Q1 2026: https://www.bea.gov/news/2026/gdp-advance-estimate-1st-quarter-2026
- BEA Personal Income and Outlays, March 2026: https://www.bea.gov/news/2026/personal-income-and-outlays-march-2026
- U.S. Treasury daily par yield curve rates: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_yield_curve
- U.S. Treasury daily real yield curve rates: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_real_yield_curve
- Cboe VIX historical-data page: https://www.cboe.com/tradable_products/vix/vix_historical_data
- Xinhua Hong Kong close for Thursday, April 30, 2026: https://english.news.cn/20260430/09d4d449accf4b08b3ec4b08e960a73f/c.html
- Xinhua Shanghai close for Thursday, April 30, 2026: https://english.news.cn/20260430/518d1a9ea6254b7f8197f3f311c19ddc/c.html
- Xinhua Tokyo close for Thursday, April 30, 2026: https://english.news.cn/20260430/c43b7def7dfa489c83db0344ad9124a4/c.html
- Trading Economics Europe equities update for April 30, 2026: https://tradingeconomics.com/euro-area/stock-market/news/546765
- Trading Economics Germany 10Y Bund update for April 30, 2026: https://tradingeconomics.com/germany/government-bond-yield/news/546751
- Trading Economics UK gilt update for April 30, 2026: https://tradingeconomics.com/united-kingdom/government-bond-yield/news/546675
- Trading Economics Japan 10Y yield update for April 30, 2026: https://tradingeconomics.com/japan/government-bond-yield/news/546356
- ECB euro reference rates page: https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html
- Fortune BTC price page for April 30, 2026: https://fortune.com/article/price-of-bitcoin-04-30-2026/
- Fortune ETH price page for April 30, 2026: https://fortune.com/article/price-of-ethereum-04-30-2026/
- Reuters oil wrap via MarketScreener for April 30, 2026: https://www.marketscreener.com/news/oil-retreats-after-hitting-four-year-high-on-concern-of-us-iran-war-escalation-ce7f58dbd089fe25
- WSJ oil settlement wrap for April 30, 2026: https://www.wsj.com/finance/commodities-futures/oil-prices-mixed-prospect-of-prolonged-strait-of-hormuz-closure-may-buoy-e4f2616f
- WSJ precious-metals wrap for April 30, 2026: https://www.wsj.com/finance/commodities-futures/gold-edges-higher-on-likely-technical-recovery-482342a6
- TEAM historical data: https://ca.investing.com/equities/atlassian-corp-plc-historical-data
- NET same-session quote via peer article: https://www.marketwatch.com/data-news/netapp-inc-stock-outperforms-competitors-on-strong-trading-day-cf6fa757-436407b4d33d
- NVIDIA Q1 FY2027 earnings date: https://investor.nvidia.com/news/press-release-details/2026/NVIDIA-Sets-Conference-Call-for-First-Quarter-Financial-Results/default.aspx
- U.S. Treasury quarterly refunding documents: https://home.treasury.gov/policy-issues/financing-the-government/quarterly-refunding/most-recent-quarterly-refunding-documents
- BLS Employment Situation schedule: https://www.bls.gov/schedule/news_release/empsit.htm
- BLS CPI schedule: https://www.bls.gov/schedule/news_release/cpi.htm
- Statistics Bureau of Japan CPI release schedule: https://www.stat.go.jp/english/data/cpi/1582.htm
- BOJ monetary policy meeting schedule: https://www.boj.or.jp/en/mopo/mpmsche_minu/index.htm
