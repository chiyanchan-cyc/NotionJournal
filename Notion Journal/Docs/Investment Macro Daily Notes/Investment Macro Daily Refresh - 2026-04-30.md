# Investment Macro Daily Refresh - 2026-04-30

Heartbeat: US close

As of: 2026-04-30 07:21 Asia/Shanghai

US market date: 2026-04-29

Placement correction: this heartbeat ran on Thursday, April 30, 2026 in Asia/Shanghai, but the US snapshot rows below belong to the Wednesday, April 29, 2026 US cash-session date.

Storage status: markdown fallback only. The active local database at `/Users/mac/Developer/Notion Journal/Notion Journal/db.sqlite3` is still 0 bytes, so durable targets `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event` were not available for write-back in this run.

## Verdict

The market is still holding near highs into the Nvidia window, but the April 29, 2026 US close kept pushing the June-risk thesis forward: the Fed held, oil stayed inflationary, and the Treasury curve re-priced higher instead of giving equities relief.

## Top Changes Since Previous Heartbeat

1. Wednesday, April 29, 2026 ended with the S&P 500 almost flat at 7,135.95, but the composition mattered more than the index level: the market held, not rallied, after the Fed hold and ahead of the after-close mega-cap earnings cluster.
2. The Fed held the target range at 3.50%-3.75% on April 29, 2026, but the statement split was hawkish at the margin: one dissenter wanted a cut and three wanted no easing bias, which helped push the 10Y Treasury to 4.42%.
3. Oil remained the cleanest macro stress channel. Brent jumped 5.8% to $110.44, and that spillover kept Europe under pressure, left UK gilts near post-2008 highs, and raises the bar for any clean Asia risk-on follow-through.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,135.95 | -2.85 / -0.04% | 2026-04-29 last-close | AP |
| US | 10Y Treasury yield | 4.42% | +6 bps vs 2026-04-28 | 2026-04-29 official close | U.S. Treasury |
| US | 2Y Treasury yield | 3.92% | +8 bps vs 2026-04-28 | 2026-04-29 official close | U.S. Treasury |
| US | 30Y Treasury yield | 4.98% | +4 bps vs 2026-04-28 | 2026-04-29 official close | U.S. Treasury |
| US | 10Y real yield | 1.96% | +4 bps vs 2026-04-28 | 2026-04-29 official close | U.S. Treasury |
| US | VIX | 17.83 | latest cited completed close; 2026-04-29 official Cboe row pending direct verification | 2026-04-28 last-cited close / 2026-04-29 pending official CSV | Cboe historical-data page; Saxo |
| HK / China | Hang Seng | 26,111.84 | +432.06 / +1.68% | 2026-04-29 close | MT Newswires |
| HK / China | Shanghai Composite | 4,107.51 | +0.71% | 2026-04-29 close | Xinhua |
| Japan | Nikkei 225 | 59,917.46 | market_closed; last close -1.02% on 2026-04-28 | 2026-04-29 holiday carry | Xinhua |
| Japan | 10Y JGB yield | 2.465% | market_closed; last verified close | 2026-04-28 last-close | Reuters recap |
| Europe | STOXX Europe 600 | 602 | -0.7% | 2026-04-29 close | Trading Economics |
| Europe | Euro Stoxx 50 | 5,814 | -0.4% | 2026-04-29 close | Trading Economics |
| Europe | Germany 10Y Bund | about 3.10% | higher on the day / near 2011 highs | 2026-04-29 Europe session | Trading Economics; Bund auction |
| Europe | UK 10Y Gilt | 5.067% | higher on the day / near highest since 2008 | 2026-04-29 Europe session | WSJ; Reuters |
| FX | EUR/USD | 1.1680 | delayed ECB reference carry | 2026-04-28 reference / 2026-04-29 live follow-up incomplete | ECB |
| Commodity / Crypto | BTC | 77,643 | +1.8% | 2026-04-29 US session snapshot | Barron's |
| Commodity / Crypto | ETH | about 2,230 | about +2.5% early; exact close needs refresh | 2026-04-29 US session | Barron's; Robinhood CF Benchmarks-linked market |
| Commodity / Crypto | Brent | 110.44 | +5.8% | 2026-04-29 close context | AP |
| Commodity / Crypto | WTI | 99.93 | last verified close 2026-04-28; traded above $100 on 2026-04-29 | 2026-04-28 last-close / 2026-04-29 intraday | AJU Press; Investopedia |
| Commodity / Crypto | Gold | 4,545.20 | -1.02% | 2026-04-29 close | WSJ |
| Commodity / Crypto | Silver | 71.569 | -2.25% | 2026-04-29 close | WSJ |

## Trade Thesis Watch List Refresh

Rule used here: for any symbol where I could not retrieve a clean same-session quote-plus-range pair from a reliable source in this environment, I preserved the prior visible row and logged a symbol-level follow-up. Monitor Date is the market-session date for the displayed row, not the local heartbeat date.

| Thesis | Symbol | Monitor Date | 52H | 52W Low | Today Price | Daily % |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| SaaS Overshoot | DDOG | 2026-04-29 | $201.69 | $98.01 | $133.98 | +1.85% |
| SaaS Overshoot | MDB | 2026-04-29 | $444.72 | $167.19 | $258.29 | +0.03% |
| SaaS Overshoot | TEAM | 2026-04-29 | $242.00 | $56.01 | $70.49 | +1.12% |
| SaaS Overshoot | NET | 2026-04-29 | $260.00 | $117.07 | $211.97 | +1.66% |
| SaaS Overshoot | SNOW | 2026-04-29 | $280.67 | $118.30 | $141.22 | -0.94% |
| China AI | BIDU | 2026-04-27 | $165.30 | $81.17 | $128.01 | -0.54% |
| China AI | BABA | 2026-04-27 | $192.67 | $103.71 | $132.52 | -2.43% |
| Global AI Infrastructure | FCX | 2026-04-28 | $70.97 | $34.45 | $58.21 | -3.90% |
| Global AI Infrastructure | SCCO | 2026-04-28 | $218.85 | $84.13 | $189.32 | source failed; prior row kept |
| Global AI Infrastructure | NEE | 2026-04-28 | $86.29 | $63.88 | $83.23 | source failed; prior row kept |
| Global AI Infrastructure | DUK | 2026-04-28 | $132.50 | $111.22 | $131.82 | source failed; prior row kept |
| Global AI Infrastructure | VST | 2026-04-28 | $219.82 | $9.96 | $162.94 | source failed; prior row kept |
| Global AI Infrastructure | ETN | 2026-04-27 | $432.34 | $283.00 | $416.77 | -1.69% |
| Global AI Infrastructure | VRT | 2026-04-27 | $330.30 | $80.51 | $322.43 | -0.32% |
| Global AI Infrastructure | JCI | 2026-04-28 | $146.49 | $80.19 | $141.59 | -1.25% |
| Global AI Infrastructure | TT | 2026-04-28 | $471.46 | $346.45 | $425.47 | -1.06% |

## Watch-List Refresh Summary

- The required 2026 Q1 SaaS overshoot US-listed watch symbols were refreshed to the April 29, 2026 US market-session date using the current visible seeded rows.
- `BIDU`, `BABA`, `ETN`, and `VRT` still carry their last verified prior rows because I did not retrieve a cleaner same-session close-plus-range pair in this environment.
- `SCCO`, `NEE`, `DUK`, and `VST` remain populated rather than blank, but they need follow-up for an exact daily percent change refresh.

## US Snapshot

- The US close on Wednesday, April 29, 2026 was mixed rather than outright weak. The S&P 500 slipped only 0.04% to 7,135.95, the Dow fell 0.57% to 48,861.81, and the Nasdaq added 0.04% to 24,673.24.
- The more important message came from rates and policy. The FOMC held the target range at 3.50%-3.75%, but the statement highlighted elevated inflation tied in part to higher global energy prices and showed an internal split around the easing bias.
- The Treasury curve confirmed that message. Official Treasury closes showed 2Y at 3.92%, 10Y at 4.42%, and 30Y at 4.98%, all higher than Tuesday, April 28, 2026.
- I did not retrieve a clean same-day MOVE or US HY/IG spread print from a primary source in this run, so credit and rates-vol remain an explicit data gap, not a false calm signal.
- VIX is kept populated per the runbook. The direct Apr. 29, 2026 Cboe CSV row was not verifiable through this environment, so the note carries the latest cited completed close, 17.83 for Apr. 28, 2026, and keeps Apr. 29 pending official Cboe refresh.

## HK / China Snapshot

- Hong Kong and mainland China were firmer on Wednesday, April 29, 2026. The Hang Seng rose 1.68% to 26,111.84, and the Shanghai Composite gained 0.71% to 4,107.51.
- That is a better Asia handoff than the prior session, but it still does not invalidate the broader thesis. China beta improved while US duration stress and oil inflation worsened, which is not yet a clean global risk-on mix.
- USDCNH, USDHKD, and HIBOR still need a cleaner close-quality refresh.

## Japan Snapshot

- Japan was closed on Wednesday, April 29, 2026 for Showa Day, so the latest cash-equity and JGB references remain the Tuesday, April 28, 2026 session.
- That leaves the BOJ / JGB channel unresolved rather than improved. The last verified 10Y JGB level was 2.465% after a stressy prior session, and Japan remains a live June-risk amplifier.

## Europe Snapshot

- Europe absorbed the oil shock poorly on Wednesday, April 29, 2026. The STOXX Europe 600 closed down 0.7% at 602, and the Euro Stoxx 50 closed down 0.4% at 5,814.
- Germany's 10Y Bund moved toward 3.1%, while the UK 10Y gilt traded around 5.067%, near its highest level since 2008. Europe is still adding to, not damping, the global duration-pressure narrative.

## Commodity / Crypto Snapshot

- Oil remains the cleanest thesis-confirming macro input. Brent jumped 5.8% to $110.44 on Wednesday, April 29, 2026, while WTI traded back above $100 intraday after the last verified $99.93 settlement on Tuesday, April 28, 2026.
- Gold and silver both fell after the Fed decision, which says the market traded the higher-real-yield / stronger-inflation-risk mix more than a pure safety bid.
- BTC held up better than equities, trading around $77,643 in the retrieved session snapshot. ETH traded firmer as well, but the exact close remained secondary-source only.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Mixed | The market held after the Fed hold, but the tape is no longer broad or clean. | US GDP / core PCE on 2026-04-30; Treasury refunding May 4-6 |
| Rates And Curve | Watch | The curve re-priced higher after the Fed hold; 10Y closed at 4.42%. | US GDP / core PCE on 2026-04-30; payrolls on 2026-05-08 |
| Credit Stress | Watch | Same-day MOVE and cash credit-spread refresh remain incomplete. | Credit / rates-vol refresh |
| Consumer And Labor | Mixed | The Fed still describes solid activity, but oil is now the clearer household tax. | GDP / PCE on 2026-04-30; payrolls on 2026-05-08 |
| Earnings And Breadth | Watch | Breadth still needs confirmation, and the after-close mega-cap earnings cluster now matters more. | MSFT / META / AMZN / GOOGL results; Nvidia date refresh |
| China Credit Impulse | Watch | China cash indices bounced, but the broader macro confirmation is incomplete. | China PMIs on 2026-04-30; credit and liquidity refresh |
| FX And Property Stress | Mixed | CNH, HKD-peg pressure, HIBOR, and property stress still need cleaner monitoring. | HIBOR / aggregate balance / property headlines |
| BOJ And JGB | Stress | Japan was closed, so there was no relief signal from the rates channel. | Tokyo CPI; next BOJ / JGB follow-up |
| JPY Carry Stress | Watch | No fresh holiday-session resolution. | USDJPY and JGB reopening follow-up |
| Crypto Liquidity | Mixed | BTC held in, but ETH close quality still lags. | ETF flows; risk reaction to US data |
| Oil And Metals | Stress | Oil remains the clearest inflationary headwind across the dashboard. | EIA / OPEC / Hormuz headlines |

## Thesis Check

Confirming:

- The market is still close enough to highs that the "hold near all-time highs into Nvidia" leg remains alive.
- The April 29, 2026 Fed hold did not calm the rates market; that supports the "pullback risk rises into June" leg.
- BOJ/JGB stress remains unresolved because Japan did not provide a fresh stabilizing session.
- Oil is still acting as the cleanest cross-asset inflation shock.

Weakening:

- Hong Kong and Shanghai improved on April 29, 2026, which slightly softens the immediate Asia-bear read from the prior heartbeat.
- If the April 30, 2026 GDP / core PCE combo comes in soft-growth but benign-inflation, the June-risk case weakens quickly.

## Forecast Updates

| Event | Date | Consensus / Prior | Market-Implied / Base Case | Upside Scenario | Downside Scenario | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| US Q1 GDP advance | 2026-04-30 | Consensus about 0.5% SAAR; prior quarter 0.5% | Base case: soft but still positive growth | Sub-0.5% with benign inflation helps duration and quality growth | Flat / negative growth with sticky inflation deepens stagflation fear | UST curve, USD, cyclicals, small caps | Confirm if growth cools without re-acceleration in inflation; invalidate if growth is too firm for cuts or too weak with sticky prices | BEA |
| US core PCE, March | 2026-04-30 | Consensus roughly 0.24%-0.28% m/m; prior still firm | Base case: sticky but not re-accelerating | 0.2% area or lower reopens easing debate | 0.3%+ m/m extends higher-for-longer | Real yields, Nasdaq, gold, BTC | Confirm if core disinflation resumes; invalidate if oil shock starts bleeding into the core path | BEA |
| China PMIs | 2026-04-30 | Consensus needs refresh; prior mixed | Base case: no broad China re-rating | Better PMIs strengthen HSI and industrial cyclicals | Weak PMIs reinforce China lag | HSI, CNH, copper, miners | Confirm if growth surprise is broad; invalidate if policy-sensitive sectors still lag | NBS / follow-up |
| ECB decision | 2026-04-30 | Hold expected; prior hold | Base case: hold with inflation caution | Growth-sensitive tone eases Bund pressure | Oil / inflation emphasis hardens ECB path | EUR, Bunds, STOXX, global duration | Confirm if ECB stays cautious without adding hawkish shock; invalidate if it validates more tightening | ECB |
| BOE decision | 2026-04-30 | Hold expected; prior hold | Base case: hold with hawkish bias | Growth concern cools gilt pressure | Inflation focus drives another gilt spike | Gilts, GBP, UK equities | Confirm if BOE avoids validating aggressive hike pricing; invalidate if it leans into more tightening | BOE |
| Treasury quarterly refunding | 2026-05-04 to 2026-05-06 | No major coupon shock expected; prior cycle manageable | Base case: heavy but digestible supply | Softer mix stabilizes long-end yields | Heavier duration burden lifts term premium again | 10Y / 30Y UST, REITs, duration trades | Confirm if supply is absorbed without fresh long-end stress; invalidate if term premium jumps | U.S. Treasury |
| US payrolls, April | 2026-05-08 | Consensus needs refresh; prior +178K, unemployment 4.3% | Base case: slower but still positive hiring | Cooling without a labor break helps duration | Hot print revives rate fear; weak print revives growth fear | Front end, USD, equities | Confirm if labor cools orderly; invalidate if the labor read re-accelerates or cracks | BLS |
| US CPI, April | 2026-05-12 | Consensus needs refresh; prior CPI 3.3% y/y | Base case: headline firm from energy, core only slowly easing | Softer core rebuilds cut hopes | Energy spillover lifts both headline and core concern | USTs, USD, growth stocks, gold | Confirm if core remains contained; invalidate if headline shock bleeds into the core trend | BLS |
| Nvidia earnings | Late May 2026; exact date still needs refresh | Consensus needs refresh; prior quarter revenue $68.1B, outlook $78.0B +/- 2% | Base case: beat-and-maintain is enough to hold the tape together | Beat-and-raise broadens the AI rally | Guidance wobble hits crowded AI positioning | Nasdaq, SOX, S&P breadth | Confirm if leadership broadens after the print; invalidate if AI capex enthusiasm fails to carry price | Nvidia IR |
| US personal income and outlays, April | 2026-05-29 | Consensus needs refresh | Base case: income and inflation stay sticky but manageable | Softer spending plus cooler inflation helps bonds | Sticky spending and inflation keep yields elevated | USTs, USD, consumer cyclicals | Confirm if disinflation resumes; invalidate if higher-for-longer gets reinforced | BEA |

## Probability-Weighted Policy Scenarios

### ECB on Thursday, April 30, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 70% | Hold with inflation caution, no policy shift | Bunds stay pressured but avoid a new shock |
| Growth-sensitive hold | 15% | Hold and acknowledge growth drag more clearly | EUR softens, Bunds rally, risk assets stabilize |
| Hawkish hold | 15% | Hold but validate more tightening risk because of oil | Bunds and gilts sell off further; equities fade |

### BOE on Thursday, April 30, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Hold with hawkish bias | Gilt pressure persists |
| Balanced hold | 20% | Hold and stress growth risk more evenly | Gilts cool and UK rate stress eases |
| More hawkish than priced | 20% | Hold but reinforce market hike expectations | Gilts push higher and pressure global duration again |

### Treasury Refunding on May 4-6, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Manageable supply profile | Long-end pressure persists but does not break the tape |
| Bearish supply surprise | 25% | Heavier long-end burden | Term premium rises; rate-sensitive equities underperform |
| Supportive mix | 15% | Smaller burden or stronger buyback support | Long end stabilizes and valuation pressure eases |

## Next 7 Days

- 2026-04-30: US Q1 GDP advance estimate.
- 2026-04-30: US personal income and outlays, including core PCE.
- 2026-04-30: ECB decision.
- 2026-04-30: BOE decision.
- 2026-04-30: China PMIs.
- 2026-05-04: Treasury quarterly refunding financing estimates.
- 2026-05-06: Treasury refunding announcement.
- 2026-05-08: US payrolls.

## Follow-Up Tasks

- Expose durable storage for `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event`; the active local SQLite file remains empty.
- Backfill every required market snapshot line from `2026-01-01` forward once durable storage exists.
- Verify the official Cboe `VIX_History.csv` row for the April 29, 2026 close; keep Apr. 29 marked pending official Cboe refresh until the file is directly verifiable.
- Refresh exact same-session MOVE, HY OAS, and IG spread lines for the April 29, 2026 US close.
- Refresh exact same-session close-plus-range pairs for `BIDU`, `BABA`, `ETN`, and `VRT`.
- Refresh exact daily percent change for `SCCO`, `NEE`, `DUK`, and `VST`.
- Refresh USDCNH, USDHKD, and HIBOR.
- Refresh the exact WTI Apr. 29 settlement and ETH end-session print from a cleaner source.

## Backfill Status

- No durable `nj_agent_heartbeat_run` history was available because the active local database file is empty, so missed-window detection still could not be computed from stored rows.
- No durable `nj_agent_backfill_task` rows could be created for the same reason.
- Markdown-tracked pending backfills remain:
- `pending`: heartbeat history bootstrap for missed Asia-close and US-close windows from 2026-01-01 forward, reason `automation_not_run`.
- `pending`: market snapshot historical backfill for required lines from 2026-01-01 forward, reason `automation_not_run`.
- `pending`: official VIX verification for the 2026-04-29 US close, reason `official_source_not_yet_updated`.

## Source Links

- AP US close recap for Wednesday, April 29, 2026: https://apnews.com/article/f01ef6ed118e30e2cde9d25b4a1fdfc5
- AP market / oil wrap: https://apnews.com/article/16286a529f0fbb34ed213005ffda74b2
- Federal Reserve statement, April 29, 2026: https://www.federalreserve.gov/newsevents/pressreleases/monetary20260429a.htm
- U.S. Treasury daily par yield curve rates: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_yield_curve
- U.S. Treasury daily real yield curve rates: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_real_yield_curve
- Cboe VIX historical data page: https://www.cboe.com/tradable_products/vix/vix_historical_data
- Saxo market quick take for April 29, 2026: https://www.home.saxo/en-mena/content/articles/macro/market-quick-take---29-april-2026-29042026
- Xinhua Shanghai close for Wednesday, April 29, 2026: https://www.china.org.cn/china/Off_the_Wire/2026-04/29/content_118469912.shtml
- MT Newswires Hang Seng close recap: https://www.indopremier.com/ipotnews/newsDetail.php?group_news=IPOTNEWS&halaman=1&jdl=Hong_Kong_Stocks_Rebound_as_China_Policy_Signals_Lift_Sentiment__Sunmi_Tech_Shines_on_Debut&name=&news_id=217123&q=hong+kong+stocks%2C+hang+seng%2C&search=y_general&taging_subtype=Develop+Market
- Europe close recap: https://tradingeconomics.com/euro-area/stock-market/news/546154
- Germany bund context: https://tradingeconomics.com/germany/government-bond-yield/news/546126
- Bund auction: https://finobird.com/calendar/economic/de-germany-10-year-bund-auction-2026-04-29/
- UK gilt / Reuters context: https://www.wsj.com/articles/energy-prices-key-factor-in-driving-volatility-in-u-s-treasurys-52af78d1
- BTC / ETH morning crypto wrap: https://www.barrons.com/articles/bitcoin-price-xrp-ethereum-cryptos-today-ceba33b2
- WTI / Brent April 28 settlement carry: https://www.ajupress.com/view/20260429144170075
- Gold / silver close context: https://www.wsj.com/finance/commodities-futures/gold-edges-lower-on-prospects-of-dollar-strength-0b24e4d8
- ECB reference rates: https://www.ecb.europa.eu/stats/eurofxref/eurofxref-xml.html
- BEA schedule: https://www.bea.gov/news/schedule
- BLS May 2026 release calendar: https://www.bls.gov/schedule/2026/05_sched_list.htm
- Treasury refunding documents: https://home.treasury.gov/policy-issues/financing-the-government/quarterly-refunding/most-recent-quarterly-refunding-documents
- Nvidia IR results context: https://investor.nvidia.com/news/press-release-details/2026/NVIDIA-Announces-Financial-Results-for-Fourth-Quarter-and-Fiscal-2026/
