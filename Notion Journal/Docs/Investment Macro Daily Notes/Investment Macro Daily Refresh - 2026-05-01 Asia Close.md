# Investment Macro Daily Refresh - 2026-05-01 Asia Close

Heartbeat: Asia close

As of: 2026-05-01 20:31 Asia/Shanghai

Asia market date: 2026-05-01

US market date carried in this note: 2026-04-30 last-close

Placement rule: Asia rows below are stored on the Friday, May 1, 2026 local market-session date. US snapshot rows remain on the Thursday, April 30, 2026 US cash-session date even though this heartbeat ran on Friday evening in Asia/Shanghai.

Storage status: markdown fallback only. The active local database at `/Users/mac/Developer/Notion Journal/Notion Journal/db.sqlite3` is still 0 bytes, so durable write-back targets `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event` were not available in this run.

## Verdict

The market can still hold near highs into Nvidia, but the May 1 Asia close did not clear the June-risk thesis: holiday-thinned Hong Kong, China, and continental Europe left Japan's still-hot rates channel, unresolved Fed-chair politics, and oil-sensitive inflation prints as the main risks still converging into mid-May and June.

## Top Changes Since Previous Heartbeat

1. Japan was the only major Asia cash market with a fresh close on Friday, May 1, 2026: the Nikkei 225 rose 0.38% to 59,513.12, but the 10Y JGB stayed above 2.5% and the yen-intervention story kept the FX/rates channel stressed.
2. Hong Kong, mainland China, and most of continental Europe were shut for Labour Day on Friday, May 1, 2026, so the cross-asset handoff stayed dependent on carried April 30 closes rather than a broad new risk-on confirmation.
3. Oil stayed below Thursday's spike but did not normalize. AP showed Brent around $111.13 and WTI around $104.27 on May 1, which helped preserve the "hold into Nvidia" leg without removing the inflation and refunding risk into May 4-12.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,209.01 | +73.06 / +1.02% | 2026-04-30 last-close | AP; Xinhua |
| US | 10Y Treasury yield | 4.40% | -2 bps vs 2026-04-29 | 2026-04-30 official close | U.S. Treasury |
| US | VIX | 17.83 | latest directly verifiable official Cboe close still 2026-04-28; 2026-04-30 official CSV row pending direct fetch | 2026-04-28 official close / 2026-04-30 pending official Cboe refresh | Cboe |
| HK / China | Hang Seng | 25,776.53 | market_closed for Labour Day; carry 2026-04-30 close | 2026-05-01 market_closed / 2026-04-30 last-close | HKEX; Xinhua |
| HK / China | Shanghai Composite | 4,112.16 | market_closed for Labour Day; carry 2026-04-30 close | 2026-05-01 market_closed / 2026-04-30 last-close | SSE; Xinhua |
| Japan | Nikkei 225 | 59,513.12 | +228.20 / +0.38% | 2026-05-01 close | Xinhua |
| Japan | 10Y JGB yield | about 2.50% | delayed; still above 2.5% / near 29-year high area | 2026-05-01 Asia session | Trading Economics |
| Europe | STOXX Europe 600 | about +1.0% | market_closed for Labour Day; carry 2026-04-30 close | 2026-05-01 market_closed / 2026-04-30 last-close | Trading Economics; Euronext |
| Europe | Euro Stoxx 50 | about +0.6% | market_closed for Labour Day; carry 2026-04-30 close | 2026-05-01 market_closed / 2026-04-30 last-close | Trading Economics; Euronext |
| Europe | Germany 10Y Bund | 3.05% | market_closed for Labour Day; carry 2026-04-30 close | 2026-05-01 market_closed / 2026-04-30 last-close | Deutsche Borse; Trading Economics |
| Europe | UK 10Y Gilt | just above 5.00% | near unchanged; still close to 2008 highs | 2026-05-01 Europe session | Trading Economics |
| FX | EUR/USD | 1.1729 | +0.4% vs prior 1.1682 late-NY comparison | 2026-04-30 late New York / carried into Asia close | Xinhua |
| Commodity / Crypto | BTC | 76,316.44 | -1.09% | 2026-04-30 08:45 ET last verified | Fortune |
| Commodity / Crypto | ETH | 2,265.02 | -2.16% | 2026-04-30 08:45 ET last verified | Fortune |
| Commodity / Crypto | Brent | 111.13 | about +0.7% intraday | 2026-05-01 Europe / Asia session | AP |
| Commodity / Crypto | WTI | 104.27 | about -0.8% intraday vs Apr. 30 settle | 2026-05-01 Europe / Asia session | AP |
| Commodity / Crypto | Gold | 4,642 | +1.87% | 2026-04-30 09:00 ET last verified | Fortune |
| Commodity / Crypto | Silver | 73.74 | +1.80% | 2026-04-30 08:30 ET last verified | Fortune |

## Trade Thesis Watch List Refresh

Rule used here: May 1 was a holiday for Hong Kong and mainland China, and I did not retrieve clean same-session closes for every required HK/China/Europe symbol. Prior verified rows stay visible instead of being blanked out, and each missing same-session quote remains a symbol-level follow-up. Japan was open, so `6501 JP` is refreshed to the May 1 market-session date.

| Thesis | Symbol | Monitor Date | 52H | 52W Low | Today Price | Daily % |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| China AI | 0700 HK | 2026-04-29 | HK$683.00 | HK$469.00 | HK$479.20 | +1.14% |
| China AI | 002230 CN | 2026-04-28 | CNY67.50 | CNY44.98 | CNY49.17 | -1.28% |
| China AI | 0981 HK | 2026-04-29 | HK$93.50 | HK$38.65 | HK$65.80 | -0.38% |
| China AI | 688256 CN | 2026-04-29 | CNY1,595.88 | CNY520.67 | CNY1,391.99 | +1.27% |
| China AI | 600584 CN | 2026-04-28 | CNY54.63 | CNY31.20 | CNY45.10 | -2.63% |
| China AI | 002156 CN | 2026-04-27 | CNY59.20 | CNY22.90 | CNY51.20 | +5.74% |
| China AI | 002185 CN | 2026-04-29 | CNY16.00 | CNY8.60 | CNY12.85 | +1.58% |
| China AI | USD/CNH | 2026-04-29 | n/a | n/a | 6.8167 | +0.10% |
| Global AI Infrastructure | 2899 HK | 2026-04-29 | HK$46.98 | HK$16.70 | HK$36.38 | +2.88% |
| Global AI Infrastructure | SU FP | 2026-04-30 | EUR281.50 | EUR199.30 | EUR266.95 | -1.69% |
| Global AI Infrastructure | ENR GR | 2026-04-28 | EUR191.66 | EUR65.56 | EUR172.98 | -2.50% |
| Global AI Infrastructure | 6501 JP | 2026-05-01 | JPY6,039 | JPY2,590 | JPY4,815 | -5.01% |

## Watch-List Refresh Summary

- The required Asia-close table stayed populated instead of collapsing to `Needs refresh`.
- `6501 JP` was refreshed to the Friday, May 1, 2026 market-session close at JPY4,815, down 5.01%, with a 52-week range of JPY2,590 to JPY6,039.
- Hong Kong and mainland China were closed for Labour Day, so HK/CN symbol rows remain on their last verified market-session dates.
- Continental Europe was closed for Labour Day, so `SU FP` and `ENR GR` stay on prior verified rows until the next open-market refresh.

## US Snapshot

- The carried US close remains Thursday, April 30, 2026. The S&P 500 ended at 7,209.01, up 1.02%, which keeps the "hold near highs into Nvidia" leg fully alive.
- Treasury yields eased modestly rather than breaking lower. The 10Y Treasury finished at 4.40%, down 2 bps from Wednesday, April 29, 2026.
- VIX remains populated per runbook, but the official target row is still unresolved. The latest directly verifiable Cboe close remains April 28 at 17.83, while the April 30 official CSV row is still pending direct fetch.
- Friday's early US context was constructive but thin: AP reported S&P 500 futures up 0.1%, Dow futures up 0.2%, and Nasdaq futures down 0.1% on May 1.

## HK / China Snapshot

- Hong Kong cash equities were closed on Friday, May 1, 2026 for Labour Day, and HKEX says the cash market reopens on Monday, May 4, 2026.
- Mainland China was also closed for Labour Day, with SSE set to reopen on Wednesday, May 6, 2026.
- That means the latest cash-session carry remains Thursday, April 30, 2026: Hang Seng 25,776.53 and Shanghai Composite 4,112.16.
- The thesis implication is neutral-to-slightly fragile rather than outright bearish: there was no holiday-session damage, but also no new China beta confirmation.

## Japan Snapshot

- Japan was the only major local equity market that gave a fresh cash close. Xinhua reported the Nikkei 225 up 228.20 points, or 0.38%, to 59,513.12 on Friday, May 1, 2026.
- That stronger equity close does not remove the macro pressure. The 10Y JGB remained above 2.5% in delayed bond coverage, still near the highest area since the late 1990s.
- FX stress is still active. Xinhua cited Kyodo reporting that Japanese authorities intervened on Thursday, April 30, after USD/JPY had weakened into the upper-160 area before snapping back toward the mid-155s.
- The result is a familiar pattern for the thesis: equities can bounce, but the BOJ/JGB/yen channel still looks like a June-risk amplifier rather than a resolved problem.

## Europe Snapshot

- Most continental European markets were closed for Labour Day on Friday, May 1, 2026. Euronext lists May 1 as closed, and Deutsche Borse lists May 1 as a non-trading day for Xetra and Frankfurt.
- Because of that, the STOXX Europe 600, Euro Stoxx 50, and Germany 10Y Bund rows are correctly carried on their April 30 market-session date.
- The UK was open. Trading Economics said the 10Y gilt held just above 5%, still near the highest level since 2008, while AP said the FTSE 100 slipped slightly.
- Europe therefore did not add a fresh bullish offset to Japan's rates stress. The continental closure and still-elevated gilt yield keep the broader rates story heavy.

## Commodity / Crypto Snapshot

- Oil stayed calmer than Thursday's peak but still too high for comfort. AP showed Brent around $111.13 and WTI around $104.27 on Friday, May 1, 2026.
- Crypto remained softer than the equity tape. The latest verified Fortune prints from Thursday morning showed BTC at $76,316.44, down 1.09%, and ETH at $2,265.02, down 2.16%.
- Precious metals bounced in the latest verified pricing window: gold was $4,642 per ounce at 9:00 a.m. ET on April 30 and silver was $73.74 at 8:30 a.m. ET.
- The macro read remains mixed: oil is no longer screaming higher, but it is still high enough to keep CPI and central-bank risk live.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Supportive | Fresh US index highs are intact going into the new month. | Treasury refunding May 4-6; payrolls May 8 |
| Rates And Curve | Mixed | Treasuries improved, but JGBs and gilts still keep the global rates channel uncomfortable. | Treasury refunding; CPI May 12 |
| Credit Stress | Watch | Clean MOVE and same-session US spread prints still were not refreshed in this run. | Credit and rates-vol refresh |
| Consumer And Labor | Mixed | Growth held up, but oil-sensitive inflation risk remains live ahead of payrolls and CPI. | Payrolls May 8; CPI May 12 |
| Earnings And Breadth | Supportive | The market is still holding near highs into Nvidia. | Nvidia May 20 |
| China Credit Impulse | Watch | Holiday closures prevented a new cash read, and FX/liquidity cross-checks are still incomplete. | China reopen May 6; CPI/PPI May 11 |
| FX And Property Stress | Watch | USD/CNH, USDHKD, and HIBOR still need cleaner same-session refreshes. | CNH / HKD / HIBOR follow-up |
| BOJ And JGB | Stress | Japan's rates channel still looks like the clearest unresolved macro stress point. | BOJ Summary May 12; BOJ June 15-16 |
| JPY Carry Stress | Stress | Reported intervention underscores how unstable the yen channel still is. | USD/JPY follow-through |
| Crypto Liquidity | Mixed | BTC and ETH lagged the equity rebound in the latest verified prints. | ETF flow and cross-asset risk response |
| Oil And Metals | Watch | Oil cooled from panic highs, but it remains elevated enough to threaten headline inflation. | Treasury refunding; CPI; Middle East flow |

## Thesis Check

Confirming:

- US equities are still close enough to all-time highs that the tape can plausibly hold into Nvidia.
- Japan continues to validate the BOJ / JGB / yen leg of the June-risk thesis.
- Oil remains high enough that refunding, payrolls, and CPI can still re-tighten the macro narrative quickly.

Weakening:

- May 1 did not produce a fresh Asia-wide de-risking move; holiday closures contained visible damage.
- The Nikkei managed a positive close even with the rates and FX stress still active.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Probability | Base Case | Upside / Bull Case | Downside / Bear Case | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Treasury quarterly refunding financing estimates | 2026-05-04 | no major coupon shock expected | Feb. 2, 2026 financing estimates | term premium already elevated | Heavy but manageable borrowing need | Stable financing estimate lets the 10Y settle | Larger-than-feared borrowing need lifts long-end yields again | 10Y / 30Y UST, duration equities, USD | Confirmed by calm long-end reaction; invalidated by a fast term-premium jump | U.S. Treasury |
| Treasury quarterly refunding announcement | 2026-05-06 | coupon sizes broadly expected steady | Feb. 4, 2026 refunding statement | market remains sensitive to long-end supply | No duration surprise | Stable sizing helps equities absorb oil and inflation noise | Larger duration load re-tightens financial conditions | Long bonds, REITs, growth stocks | Confirmed by steady coupon mix; invalidated by heavier long-end issuance | U.S. Treasury |
| U.S. payrolls, April | 2026-05-08 | about 70K by TE model; heartbeat base case about 100K | Mar. payrolls +178K | market wants slower but still positive hiring | Cooling, not contraction | Payrolls slow with unemployment broadly stable | Hot jobs revive higher-for-longer; weak jobs revive hard-landing fear | Front end, USD, small caps, cyclicals | Confirmed by orderly cooling; invalidated by reacceleration or a labor crack | BLS; Trading Economics |
| Fed-chair transition / Warsh Senate vote window | 2026-05-11 | Senate cloture vote scheduled May 11; confirmation path still active | Banking Committee advanced Warsh on Apr. 29, 2026 | nomination still likely to proceed, but independence concerns remain a live risk | Process moves forward without immediate policy repricing | Warsh emphasizes Fed independence and term premium eases | Political fight or a less independent tone lifts macro risk premium | USTs, USD, bank stocks, long-duration tech | Confirmed by clean cloture path and independence messaging; invalidated by confirmation turmoil | Senate Democratic Caucus; Senate Banking Committee |
| China CPI / PPI, April | 2026-05-11 | inferred base case around CPI 1.0%-1.2% y/y and PPI around 0.5% y/y | Mar. CPI 1.0% y/y; Mar. PPI 0.5% y/y | no clean market-implied pricing source available | Benign CPI with still-firm producer inflation | Better domestic-demand mix helps CNH, HSI, and cyclicals | Softer CPI and PPI revive China-lag concerns | HSI, CNH, industrial metals | Confirmed by steady core and still-positive producer prices; invalidated by broad disinflation | NBS; Trading Economics |
| BOJ Summary of Opinions | 2026-05-12 | qualitative release, not point forecast | Apr. 27-28 BOJ hold at 0.75% | market is listening for how close the BOJ is to another hike | Still gradual tightening bias without a near-term move | Tone is less urgent and JGB pressure eases | Tone validates faster normalization and pushes JGBs / JPY higher | JGBs, JPY, Nikkei carry trades | Confirmed by measured language; invalidated by stronger inflation / FX urgency | BOJ |
| U.S. CPI, April | 2026-05-12 | TE consensus 3.3% y/y headline, 2.6% y/y core; market-implied headline near 3.8% | Mar. CPI 3.3% y/y; core 2.6% y/y | inflation fixings still lean higher because of energy | Headline stays firm; core cools only slowly | Core services ease enough to keep June FOMC balanced | Headline and core both re-accelerate | USTs, USD, Nasdaq, gold | Confirmed by softer core services; invalidated by broad inflation stickiness | BLS; Trading Economics; MarketWatch |
| Nvidia Q1 FY2027 earnings | 2026-05-20 | company reports after the close; Street still needs a cleaner same-session consensus pull | prior quarter revenue $68.1B; Q1 guide $78.0B +/- 2% | positioning still crowded | Beat-and-maintain is enough to keep the tape together | Beat-and-raise broadens leadership and extends the hold-near-highs thesis | Guide wobble or softer AI demand commentary hits crowded positioning hard | Nasdaq, SOX, S&P breadth | Confirmed by strong data-center demand and guide confidence; invalidated by growth or margin wobble | Nvidia IR |
| Japan CPI, April | 2026-05-22 | consensus needs refresh; market focus remains on whether inflation stays sticky enough to validate more BOJ pressure | prior national CPI still elevated | JGB market sensitivity remains high | Sticky inflation keeps BOJ normalization alive but gradual | Softer CPI cools JGB pressure and carry stress | Hot CPI validates another BOJ step sooner | JGBs, JPY, Nikkei | Confirmed by contained services and core; invalidated by hotter underlying inflation | Statistics Bureau of Japan |
| U.S. GDP second estimate and Personal Income / Outlays, April | 2026-05-28 | release date confirmed | Q1 GDP advance 2.0%; Mar. core PCE 0.3% m/m | market will use this to test whether April inflation cooled | Growth holds and inflation cools modestly | Softer monthly core PCE reopens easing hope | Sticky PCE with okay growth keeps yields elevated | USTs, USD, growth stocks | Confirmed by cooler monthly core PCE; invalidated by another sticky print | BEA |
| BOJ meeting | 2026-06-15 to 2026-06-16 | policy rate unchanged in base case | Apr. 27-28 hold at 0.75% | market still leans toward more pressure than less | Hold with tightening bias intact | Oil eases, yen stabilizes, BOJ waits | Inflation and FX pressure pull BOJ closer to another hike | JGBs, JPY, Nikkei, global carry | Confirmed by calmer JGBs and FX; invalidated by hotter CPI and renewed yen weakness | BOJ |
| FOMC meeting | 2026-06-16 to 2026-06-17 | no near-term move in base case | Apr. 28-29 hold | market will arrive focused on energy pass-through and core inflation | Hold with data dependence | Softer CPI/PCE and slower jobs allow a more balanced tone | Oil-plus-core persistence keeps the Fed more hawkish than equities want | USTs, USD, equities, gold, BTC | Confirmed by softer inflation and labor data; invalidated by persistent inflation pressure | Federal Reserve |

## Probability-Weighted Policy Scenarios

### Treasury Refunding on May 4-6, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Manageable financing mix with no big duration surprise | Long-end pressure eases a little but does not disappear |
| Bearish supply surprise | 25% | Heavier duration burden or worse borrowing signal | Term premium rises again and rate-sensitive equities lag |
| Supportive mix | 15% | Smaller burden or better demand support | 10Y and 30Y stabilize faster |

### Fed-Chair Transition / Warsh Vote Path

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Cloture and confirmation path continues, independence questions remain but do not explode | Mild policy-premium stays in long-end yields |
| Relief case | 15% | Warsh and Senate messaging reduce independence concerns | Long-end and dollar calm modestly |
| Stress case | 25% | Confirmation turns into a louder fight over Fed independence | Macro risk premium rises, especially for duration assets |

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

- 2026-05-04: HKEX cash market reopens; U.S. Treasury quarterly refunding financing estimates.
- 2026-05-05: U.S. JOLTS for March.
- 2026-05-06: Shanghai and Shenzhen cash markets reopen; U.S. Treasury quarterly refunding announcement.
- 2026-05-07: BOJ minutes for the March 18-19 meeting.
- 2026-05-08: U.S. payrolls for April.

## Follow-Up Tasks

- Expose durable storage for `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event`; the active local SQLite file remains empty.
- Backfill every required market snapshot line from `2026-01-01` forward once durable storage exists.
- Verify the official Cboe `VIX_History.csv` row for the April 30, 2026 US close; keep Apr. 30 marked pending official Cboe refresh until the file is directly fetchable.
- Refresh same-session close-plus-range rows for `0700 HK`, `002230 CN`, `0981 HK`, `688256 CN`, `600584 CN`, `002156 CN`, `002185 CN`, `2899 HK`, `SU FP`, and `ENR GR`.
- Refresh clean same-session values for `USD/CNH`, `USDHKD`, and `HIBOR`.
- Refresh clean same-session MOVE and US HY / IG spread prints.
- Refresh a cleaner same-session BTC, ETH, Brent, WTI, gold, and silver snapshot once a direct reliable source is reachable in-run.

## Backfill Status

- No durable `nj_agent_heartbeat_run` history was available because the active local database file is empty, so missed-window detection still could not be computed from stored rows.
- No durable `nj_agent_backfill_task` rows could be created for the same reason.
- The markdown note chain shows the expected `2026-05-01` US-close heartbeat exists, so no new missed-window gap was evident in the visible markdown fallback history before this run.
- Markdown-tracked pending backfills remain:
- `pending`: heartbeat history bootstrap for missed Asia-close and US-close windows from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: market snapshot historical backfill for required lines from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: official VIX verification for the `2026-04-30` US close, reason `official_source_not_yet_updated`.

## Source Links

- Prior Asia close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-04-30 Asia Close.md`
- Prior US close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-01.md`
- AP global markets May 1, 2026: https://apnews.com/article/906fc294e936b548ee3993af4664f8e8
- U.S. Treasury daily nominal yields: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_yield_curve
- Cboe VIX historical data landing page: https://www.cboe.com/tradable_products/vix/vix_historical_data
- Xinhua Tokyo close for Friday, May 1, 2026: https://english.news.cn/20260501/d15a30912bd14c5ba9ee46e8407847ea/c.html
- Xinhua global indices / holiday closure snapshot for Friday, May 1, 2026: https://english.news.cn/20260501/d3c26e5bcffa459280298db0dc17e23d/c.html
- Xinhua yen-intervention report for Friday, May 1, 2026: https://english.news.cn/20260501/e57fa1cc00dc42f5b27d932428a1d642/c.html
- HKEX holiday notice for May 1, 2026: https://www.hkex.com.hk/Services/Trading/Derivatives/Overview/Trading-Mechanism/Derivatives-Holiday-Trading?sc_lang=en
- Shanghai Stock Exchange Labour Day closure notice: https://www.sse.com.cn/disclosure/announcement/general/c/c_20260423_10816345.shtml
- Euronext trading calendar / May 1 closure: https://www.euronext.com/en/trading-calendars-hours
- Deutsche Borse trading calendar: https://www.cashmarket.deutsche-boerse.com/cash-en/trading/trading-calendar-and-trading-hours
- Trading Economics UK 10Y gilt update for May 1, 2026: https://tradingeconomics.com/united-kingdom/government-bond-yield/news/547008
- Fortune BTC price page for April 30, 2026: https://fortune.com/article/price-of-bitcoin-04-30-2026/
- Fortune ETH price page for April 30, 2026: https://fortune.com/article/price-of-ethereum-04-30-2026/
- Fortune gold price page for April 30, 2026: https://fortune.com/article/current-price-of-gold-04-30-2026/
- Fortune silver price page for April 30, 2026: https://fortune.com/article/current-price-of-silver-4-30-2026/
- BLS May 2026 release schedule: https://www.bls.gov/schedule/2026/05_sched.htm
- BLS Employment Situation schedule: https://www.bls.gov/schedule/news_release/empsit.htm
- Treasury quarterly refunding documents calendar: https://home.treasury.gov/policy-issues/financing-the-government/quarterly-refunding/most-recent-quarterly-refunding-documents
- Senate schedule for Monday, May 11, 2026: https://www.democrats.senate.gov/2026/04/30/schedule-for-pro-forma-sessions-and-monday-may-11-2026
- Senate Banking Committee Warsh hearing page: https://www.banking.senate.gov/hearings/04/14/2026/nomination-hearing
- BOJ monetary policy meeting schedule: https://www.boj.or.jp/en/mopo/mpmsche_minu/index.htm
- U.S. CPI home page / next release: https://www.bls.gov/cpi/
- Trading Economics U.S. inflation page: https://tradingeconomics.com/united-states/inflation-cpi
- MarketWatch CPI fixings note: https://www.marketwatch.com/livecoverage/stock-market-today-dow-s-p-500-nasdaq-fall-oil-rises-iran-war-energy-infrastructure-damaga/card/traders-expect-annual-headline-cpi-rate-to-move-up-to-near-4-for-april-and-may-FOgnFClaI1I6XEaKtEs6
- China CPI page / calendar timing: https://tradingeconomics.com/china/inflation-cpi
- China March 2026 PPI official release: https://www.stats.gov.cn/english/PressRelease/202604/t20260413_1963289.html
- Statistics Bureau of Japan CPI release schedule: https://www.stat.go.jp/english/data/cpi/1582.htm
- BEA release schedule: https://www.bea.gov/news/schedule
- Federal Reserve FOMC meeting calendar: https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm
- NVIDIA Q1 FY2027 earnings call notice: https://investor.nvidia.com/news/press-release-details/2026/NVIDIA-Sets-Conference-Call-for-First-Quarter-Financial-Results/default.aspx
