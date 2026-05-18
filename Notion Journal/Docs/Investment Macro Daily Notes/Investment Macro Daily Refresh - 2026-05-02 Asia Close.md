# Investment Macro Daily Refresh - 2026-05-02 Asia Close

Heartbeat: Asia close

As of: 2026-05-02 20:39 Asia/Shanghai

Asia market date carried in this note: 2026-05-02 market_closed

Fresh Asia cash-session dates available in this run: Japan 2026-05-01 close; Hong Kong and mainland China 2026-04-30 last-close because May 1 was a holiday and May 2 is a Saturday.

US market date carried in this note: 2026-05-01 last-close

Placement rule: Saturday, May 2, 2026 is only the heartbeat metadata date. US snapshot rows below belong to the Friday, May 1, 2026 US cash-session close. Japan rows belong to the Friday, May 1, 2026 Tokyo session. Hong Kong and mainland China rows stay on their Thursday, April 30, 2026 market-session date because those markets were closed on Friday, May 1 and Saturday, May 2.

Storage status: markdown fallback only. The active local database at `/Users/mac/Developer/Notion Journal/Notion Journal/db.sqlite3` is still 0 bytes, so durable write-back targets `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event` were not available in this run.

## Verdict

The tape is still holding near highs into Nvidia, but the Saturday, May 2, 2026 Asia-close heartbeat did not weaken the June-risk thesis: Friday's record U.S. close and softer oil help the near-term hold, while BOJ/JGB pressure, Fed-chair politics, and still-high energy-sensitive inflation risk remain the clearest June convergence threats.

## Top Changes Since Previous Heartbeat

1. Friday, May 1, 2026 added another record U.S. close: the S&P 500 rose to 7,230.12 and the Nasdaq to 25,114.44, extending the "hold into Nvidia" leg by one more session.
2. Oil backed off materially from Thursday's panic highs. Brent settled at $108.17 and WTI at $101.94 on Friday, May 1, 2026, reducing immediate stagflation stress without clearing it.
3. Weekend session logic now dominates the Asia-close handoff: Saturday, May 2, 2026 had no fresh Asia cash-session closes, so the note correctly carries Japan's Friday close and Hong Kong / China's Thursday close instead of misdating them onto May 2.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,230.12 | +21.11 / +0.29% | 2026-05-01 last-close | AP; Xinhua |
| US | 10Y Treasury yield | 4.39% | -1 bp vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | VIX | 17.83 | latest directly verifiable official Cboe close still 2026-04-28; 2026-05-01 official CSV row pending direct fetch | 2026-04-28 official close / 2026-05-01 pending official Cboe refresh | Cboe |
| HK / China | Hang Seng | 25,776.53 | market_closed on 2026-05-02; carry 2026-04-30 close after 2026-05-01 holiday | 2026-05-02 market_closed / 2026-04-30 last-close | HKEX; Xinhua |
| HK / China | Shanghai Composite | 4,112.16 | market_closed on 2026-05-02; carry 2026-04-30 close after 2026-05-01 holiday | 2026-05-02 market_closed / 2026-04-30 last-close | SSE; Xinhua |
| Japan | Nikkei 225 | 59,513.12 | +228.20 / +0.38% | 2026-05-01 close | Xinhua |
| Japan | 10Y JGB yield | above 2.5% | delayed; still near multi-decade highs | 2026-05-01 Asia session | Trading Economics |
| Europe | STOXX Europe 600 | prior verified row kept | market_closed on 2026-05-02; no cleaner same-session STOXX 600 close retrieved in this run | 2026-05-02 market_closed / prior verified last-close | Trading Economics follow-up |
| Europe | Euro Stoxx 50 | prior verified row kept | market_closed on 2026-05-02; euro-area rates still the main signal | 2026-05-02 market_closed / prior verified last-close | Trading Economics follow-up |
| Europe | Germany 10Y Bund | above 3.0% | elevated near multi-year highs | 2026-05-01 Europe session / carried into weekend | Trading Economics |
| Europe | UK 10Y Gilt | just above 5.0% | stabilized near 18-year highs | 2026-05-01 Europe session | Trading Economics |
| FX | EUR/USD | 1.1702 | +0.0022 vs 2026-04-28 ECB reference 1.1680 | 2026-04-30 official ECB reference / carried into weekend | ECB |
| Commodity / Crypto | BTC | 78,178.28 | +2.43% | 2026-05-01 09:15 ET | Fortune |
| Commodity / Crypto | ETH | 2,308.85 | +1.93% | 2026-05-01 09:15 ET | Fortune |
| Commodity / Crypto | Brent | 108.17 | -2.23 / -2.02% | 2026-05-01 settle | Reuters |
| Commodity / Crypto | WTI | 101.94 | -3.13 / -2.98% | 2026-05-01 settle | Reuters |
| Commodity / Crypto | Gold | 4,592 | -1.08% | 2026-05-01 08:55 ET | Fortune |
| Commodity / Crypto | Silver | 74.73 | +1.34% | 2026-05-01 08:45 ET | Fortune |

## Trade Thesis Watch List Refresh

Rule used here: Saturday, May 2, 2026 was a non-trading day across the required Asia-close watch symbols. Friday, May 1, 2026 was also a holiday in Hong Kong and mainland China. Prior verified rows remain visible instead of being blanked out, and symbol-level follow-ups remain open for any row without a fresh same-session verification. Japan was open on Friday, May 1, so `6501 JP` stays on the May 1 market-session date.

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

- The required Asia-close table stayed row-complete on the Saturday heartbeat instead of collapsing to `Needs refresh`.
- `6501 JP` remains aligned to the Friday, May 1, 2026 Tokyo market-session date, which is the latest valid Japan close.
- Hong Kong and mainland China rows remain on their prior market-session dates because Friday, May 1 was a holiday and Saturday, May 2 was not a trading day.
- `SU FP` and `ENR GR` remain visible on prior verified rows; exact same-session Europe quote refreshes still need a cleaner source pass.

## US Snapshot

- Friday, May 1, 2026 extended the U.S. risk-on tape rather than breaking it. The S&P 500 rose 21.11 points, or 0.29%, to 7,230.12, and the Nasdaq added 0.89% to 25,114.44.
- Official Treasury closes improved modestly again. The U.S. 10Y closed at 4.39% on Friday, May 1, 2026, down 1 bp from Thursday's 4.40%.
- Oil's pullback mattered. AP reported Brent settling at $108.17 and softer Treasury yields helping the Friday close.
- VIX remains populated per runbook, but the official Friday row is still unresolved in this environment. The latest directly verifiable official Cboe close remains April 28 at 17.83, and the May 1 row stays marked pending official Cboe refresh.

## HK / China Snapshot

- Saturday, May 2, 2026 was a non-trading day and Friday, May 1, 2026 was a holiday for both Hong Kong and mainland China.
- That leaves Thursday, April 30, 2026 as the correct carried cash-session date: Hang Seng 25,776.53 and Shanghai Composite 4,112.16.
- The China beta read is therefore unchanged from the prior heartbeat: no fresh damage, but still no fresh post-holiday upside confirmation either.

## Japan Snapshot

- Japan provided the latest valid Asia equity close in this weekend heartbeat. The Nikkei 225 ended Friday, May 1, 2026 at 59,513.12, up 0.38%.
- That cleaner equity close still does not clear the rates channel. Delayed bond coverage continues to show the 10Y JGB above 2.5%, near the highest zone in decades.
- The BOJ / JGB / yen axis therefore remains the clearest Asia-originated June-risk amplifier in the thesis.

## Europe Snapshot

- Saturday, May 2, 2026 was a non-trading day, so Europe rows are carried as weekend `market_closed`.
- The rates signal is still the main useful Europe input. Germany's 10Y Bund remained above 3% on May 1, while the UK 10Y gilt held just above 5%, near the highest level since 2008.
- EUR/USD also stayed firm: the latest official ECB reference available to this run was 1.1702 on April 30, 2026.

## Commodity / Crypto Snapshot

- Friday, May 1, 2026 was a better cross-asset day than the earlier Iran-spike panic implied. Reuters reported Brent settling at $108.17 and WTI at $101.94 after an Iranian negotiation proposal improved the peace-talk backdrop.
- Crypto bounced with risk appetite rather than diverging bearishly. BTC was $78,178.28 and ETH was $2,308.85 at 9:15 a.m. ET on May 1, both higher day over day.
- Precious metals stayed elevated even as oil eased. Gold was $4,592 at 8:55 a.m. ET and silver was $74.73 at 8:45 a.m. ET on May 1.
- The macro takeaway is better near-term balance, not a full all-clear: the oil shock moderated, but headline inflation sensitivity remains high into CPI, refunding, and the June policy window.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Supportive | Another record S&P close and lower yields preserved the hold-near-highs regime. | Treasury refunding May 4-6; payrolls May 8 |
| Rates And Curve | Mixed | U.S. yields eased, but JGBs, bunds, and gilts still keep the global rates channel restrictive. | Treasury refunding; CPI May 12 |
| Credit Stress | Watch | Clean same-session MOVE and spread refreshes remain incomplete. | Rates-vol and credit spread refresh |
| Consumer And Labor | Mixed | Growth held up, but energy-sensitive inflation risk is still live. | Payrolls May 8; CPI May 12 |
| Earnings And Breadth | Supportive | Records into Nvidia still support the near-term thesis leg. | Nvidia May 20 |
| China Credit Impulse | Watch | No fresh China cash session was available in this weekend run. | China CPI/PPI May 11; reopen flow |
| FX And Property Stress | Watch | CNH, HKD, and HIBOR still need a cleaner current-session source pass. | USD/CNH and HK liquidity refresh |
| BOJ And JGB | Stress | Japan's rates channel remains the clearest unresolved macro stress point. | BOJ Summary May 12; BOJ June 15-16 |
| JPY Carry Stress | Stress | Elevated JGB yields still keep the yen / carry unwind channel active. | USD/JPY follow-through |
| Crypto Liquidity | Mixed | Friday's crypto bounce improved tone, but it still has not broad-based risk leadership. | ETF flow and cross-asset follow-through |
| Oil And Metals | Watch | Oil backed off, but metals and inflation hedges still say the macro shock is not gone. | Treasury refunding; CPI; Middle East headlines |

## Thesis Check

Confirming:

- The market is still holding near all-time highs into Nvidia, and Friday's U.S. close strengthened that leg again.
- Japan still validates the BOJ / JGB / carry-stress side of the June-risk thesis.
- Rates are better than Thursday's stress levels, but they are not low enough to remove valuation and policy sensitivity.

Weakening:

- Oil's Friday retreat reduced the probability of an immediate stagflation-style de-risking wave.
- Weekend timing means there was no fresh Asia cash-session selloff to reinforce the bearish side of the thesis.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Probability | Base Case | Upside / Bull Case | Downside / Bear Case | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Treasury quarterly refunding financing estimates | 2026-05-04 | scheduled release; no major coupon shock expected | Feb. 2, 2026 financing estimates | term premium remains elevated | Heavy but manageable borrowing need | Stable financing estimate lets the 10Y keep easing | Larger-than-feared borrowing need lifts long-end yields again | 10Y / 30Y UST, duration equities, USD | Confirmed by calm long-end reaction; invalidated by a fast term-premium jump | U.S. Treasury |
| Treasury quarterly refunding announcement | 2026-05-06 | scheduled release; coupon sizes broadly expected steady | Feb. 4, 2026 refunding statement | long-end remains the key macro valve | No duration surprise | Stable sizing helps equities absorb oil and inflation noise | Larger duration load re-tightens financial conditions | Long bonds, REITs, growth stocks | Confirmed by steady coupon mix; invalidated by heavier long-end issuance | U.S. Treasury |
| U.S. payrolls, April | 2026-05-08 | consensus still needs a cleaner same-session refresh; slowing-but-positive is the broad market preference | Mar. payrolls +178K | market wants cooling without contraction | Around-trend cooling, not a break | Payrolls slow with unemployment broadly stable | Hot jobs revive higher-for-longer; weak jobs revive hard-landing fear | Front end, USD, small caps, cyclicals | Confirmed by orderly cooling; invalidated by reacceleration or labor crack | BLS |
| Fed-chair transition / Warsh Senate vote window | 2026-05-11 | Senate cloture vote window still active | Banking Committee advanced Warsh on 2026-04-29 | policy-independence risk remains a live premium | Process advances without immediate repricing shock | Independence messaging calms term premium | Political conflict raises macro risk premium | USTs, USD, bank stocks, long-duration tech | Confirmed by clean path and calmer rhetoric; invalidated by confirmation turmoil | Senate materials; Senate Banking Committee |
| China CPI / PPI, April | 2026-05-11 | TE calendar shows prior 1.0% CPI y/y; 0.5% PPI y/y, with consensus for CPI around 1.0% | Mar. CPI 1.0% y/y; Mar. PPI 0.5% y/y | no clean market-implied pricing source available | Benign CPI with still-firm producer inflation | Better domestic-demand mix helps CNH, HSI, and cyclicals | Softer CPI and PPI revive China-lag concerns | HSI, CNH, industrial metals | Confirmed by steady core and still-positive producer prices; invalidated by broader disinflation | NBS; Trading Economics |
| BOJ Summary of Opinions | 2026-05-12 | qualitative release at 8:50 a.m. JST | Apr. 27-28 BOJ hold at 0.75% | market is listening for how close the BOJ is to another hike | Still gradual tightening bias without a near-term move | Tone is less urgent and JGB pressure eases | Tone validates faster normalization and pushes JGBs / JPY higher | JGBs, JPY, Nikkei carry trades | Confirmed by measured language; invalidated by stronger inflation / FX urgency | BOJ |
| U.S. CPI, April | 2026-05-12 | consensus still needs a cleaner source refresh; core path matters more than headline | Mar. CPI 3.3% y/y; core 2.6% y/y | energy pass-through keeps upside risk alive | Headline firm; core only slowly easing | Core services soften enough to keep June FOMC balanced | Headline and core both re-accelerate | USTs, USD, Nasdaq, gold | Confirmed by softer core services; invalidated by broad inflation stickiness | BLS |
| Nvidia Q1 FY2027 earnings | 2026-05-20 | company reports after the close; prior Q4 revenue $68.1B and Q1 guide $78.0B +/- 2% | Q4 FY2026 revenue $68.1B | positioning remains crowded | Beat-and-maintain is enough to keep the tape together | Beat-and-raise broadens leadership and extends the hold-near-highs thesis | Guide wobble or softer AI demand commentary hits crowded positioning hard | Nasdaq, SOX, S&P breadth | Confirmed by strong data-center demand and guide confidence; invalidated by growth or margin wobble | Nvidia IR |
| Japan CPI, April | 2026-05-22 | release date confirmed; consensus still needs refresh | prior Japan CPI still elevated | JGB market sensitivity remains high | Sticky inflation keeps BOJ normalization alive but gradual | Softer CPI cools JGB pressure and carry stress | Hot CPI validates another BOJ step sooner | JGBs, JPY, Nikkei | Confirmed by contained services and core; invalidated by hotter underlying inflation | Statistics Bureau of Japan |
| U.S. GDP second estimate and Personal Income / Outlays, April | 2026-05-28 | scheduled release | Q1 GDP advance 2.0%; Mar. core PCE 0.3% m/m | market will use this to test whether April inflation cooled | Growth holds and inflation cools modestly | Softer monthly core PCE reopens easing hope | Sticky PCE with okay growth keeps yields elevated | USTs, USD, growth stocks | Confirmed by cooler monthly core PCE; invalidated by another sticky print | BEA |
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
| Relief case | 15% | Messaging reduces independence concerns | Long-end and dollar calm modestly |
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

- 2026-05-04: U.S. Treasury quarterly refunding financing estimates.
- 2026-05-06: U.S. Treasury quarterly refunding announcement.
- 2026-05-08: U.S. payrolls for April.
- 2026-05-11: China CPI / PPI for April; Fed-chair transition vote window.
- 2026-05-12: BOJ Summary of Opinions; U.S. CPI for April.

## Follow-Up Tasks

- Expose durable storage for `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event`; the active local SQLite file remains empty.
- Backfill every required market snapshot line from `2026-01-01` forward once durable storage exists.
- Verify the official Cboe `VIX_History.csv` row for the Friday, May 1, 2026 US close; keep May 1 marked pending official Cboe refresh until the file is directly fetchable.
- Refresh clean same-session rows for `0700 HK`, `002230 CN`, `0981 HK`, `688256 CN`, `600584 CN`, `002156 CN`, `002185 CN`, `2899 HK`, `SU FP`, and `ENR GR` on the next open-market heartbeat.
- Refresh exact same-session rows for `USD/CNH`, `USDHKD`, `HIBOR`, MOVE, and clean US HY / IG spread prints.
- Refresh exact consensus values for April payrolls and April CPI before the next U.S.-close or pre-event heartbeat.

## Backfill Status

- No durable `nj_agent_heartbeat_run` history was available because the active local database file is still empty, so missed-window detection still could not be computed from stored rows.
- No durable `nj_agent_backfill_task` rows could be created for the same reason.
- Visible markdown fallback history shows both the Thursday, May 1, 2026 Asia-close heartbeat and the Friday, May 1, 2026 U.S.-close context chain are present, so this Saturday run did not expose a new missed-window gap in the visible note sequence.
- Markdown-tracked pending backfills remain:
- `pending`: heartbeat history bootstrap for missed Asia-close and US-close windows from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: market snapshot historical backfill for required lines from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: official VIX verification for the `2026-05-01` US close, reason `official_source_not_yet_updated`.

## Source Links

- Prior Asia close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-01 Asia Close.md`
- AP Friday, May 1, 2026 U.S. close recap: https://apnews.com/article/ee0fd67a1f14608ef46165f6dd693592
- Xinhua Friday, May 1, 2026 U.S. close: https://english.news.cn/20260502/3130c23b5c3e481c9eee2129291f24da/c.html
- U.S. Treasury daily par yield curve rates: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_yield_curve
- U.S. Treasury daily real yield curve rates: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_real_yield_curve
- Cboe VIX historical-data page: https://www.cboe.com/tradable_products/vix/vix_historical_data
- Xinhua Friday, May 1, 2026 Tokyo close: https://english.news.cn/20260501/d15a30912bd14c5ba9ee46e8407847ea/c.html
- Xinhua Thursday, April 30, 2026 Hong Kong close: https://english.news.cn/20260430/09d4d449accf4b08b3ec4b08e960a73f/c.html
- Xinhua Thursday, April 30, 2026 Shanghai close: https://english.news.cn/20260430/84661e27316e44e58a2c09c1d4b33cbc/c.html
- ECB euro reference rates: https://www.ecb.europa.eu/stats/exchange/eurofxref/html/index.en.html
- Trading Economics Germany 10Y Bund update for May 1, 2026: https://tradingeconomics.com/germany/government-bond-yield/news/547017
- Trading Economics UK 10Y gilt update for May 1, 2026: https://tradingeconomics.com/united-kingdom/government-bond-yield/news/547008
- Trading Economics euro update for May 1, 2026: https://tradingeconomics.com/euro-area/currency/news/547016
- Reuters oil settlement wrap for Friday, May 1, 2026 via MarketScreener: https://ca.marketscreener.com/news/oil-rises-over-1-with-no-sign-of-iran-conflict-ending-ce7f58d9d989fe2d
- Fortune BTC price for May 1, 2026: https://fortune.com/article/price-of-bitcoin-05-01-2026/
- Fortune ETH price for May 1, 2026: https://fortune.com/article/price-of-ethereum-05-01-2026/
- Fortune gold price for May 1, 2026: https://fortune.com/article/current-price-of-gold-05-01-2026/
- Fortune silver price for May 1, 2026: https://fortune.com/article/current-price-of-silver-5-1-2026/
- U.S. Treasury quarterly refunding documents: https://home.treasury.gov/policy-issues/financing-the-government/quarterly-refunding/most-recent-quarterly-refunding-documents
- BOJ meeting schedule: https://www.boj.or.jp/en/mopo/mpmsche_minu/
- BOJ release calendar: https://www.boj.or.jp/en/about/calendar/
- Statistics Bureau of Japan CPI release schedule: https://www.stat.go.jp/english/data/cpi/1582.html
- China CPI March 2026 official release: https://www.stats.gov.cn/english/PressRelease/202604/t20260413_1963288.html
- China PPI March 2026 official release: https://www.stats.gov.cn/english/PressRelease/202604/t20260413_1963289.html
- Trading Economics China inflation calendar: https://tradingeconomics.com/china/inflation-cpi
- NVIDIA Q1 FY2027 earnings date: https://investor.nvidia.com/news/press-release-details/2026/NVIDIA-Sets-Conference-Call-for-First-Quarter-Financial-Results/default.aspx
