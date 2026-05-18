# Investment Macro Daily Refresh - 2026-04-29 Asia Close

Heartbeat: Asia close

As of: 2026-04-29 20:30 Asia/Shanghai

Asia market date: 2026-04-29

US market date carried in this note: 2026-04-28 last-close

Placement rule: Asia rows below are stored on the April 29, 2026 local market-session date. US snapshot rows remain on the Tuesday, April 28, 2026 US cash-session date even though this heartbeat ran on Wednesday evening in Asia/Shanghai.

Storage status: markdown fallback only. The active local database at `/Users/mac/Developer/Notion Journal/Notion Journal/db.sqlite3` is still 0 bytes, so durable write-back targets `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event` were not available in this run.

## Verdict

The market can still hold near highs into Nvidia, but the Asia close did not disprove the June-risk thesis: China rebounded, yet oil stayed hot, Europe stayed under rates pressure, and Japan gave no fresh relief signal because cash equities were shut for Showa Day.

## Top Changes Since Previous Heartbeat

1. China improved on the day: the Shanghai Composite rose 0.71% to 4,107.51, and Hong Kong screens showed the Hang Seng running about 1.4% higher late in the session rather than extending Tuesday's weakness.
2. Japan did not provide a reset. April 29 was Showa Day, so the last cash-equity and watch-list readings still point back to the April 28 post-BOJ stress session.
3. Cross-asset pressure remained skewed toward the June-risk side: Europe stayed softer, Bund and gilt yields remained elevated, BTC hovered around $77k into the Fed, and VIX still lacked an official April 28 Cboe file update.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,138.80 | -35.11 / -0.49% | 2026-04-28 last-close | AP; Xinhua |
| US | 10Y Treasury yield | 4.35% | about +3 bps | 2026-04-28 last-close area | WSJ; Barron's |
| US | VIX | 18.02 | latest official Cboe close is still 2026-04-27; 2026-04-28 pending official refresh | 2026-04-27 official / 2026-04-28 pending | Cboe history requirement; Stocknear history |
| HK / China | Hang Seng | 26,047.33 | +1.43% | 2026-04-29 delayed 14:52 HKT; exact official close needs refresh | MarketScreener |
| HK / China | Shanghai Composite | 4,107.51 | +0.71% | 2026-04-29 close | Xinhua |
| Japan | Nikkei 225 | 59,917.46 | -619.90 / -1.02%; market closed on 2026-04-29 | 2026-04-28 last-close / 2026-04-29 market_closed | Xinhua; Showa Day holiday context |
| Japan | 10Y JGB yield | 2.465% | carry prior close; no fresh cash-session update on holiday | 2026-04-28 last-close / 2026-04-29 market_closed | Reuters recap; Japan holiday context |
| Europe | STOXX Europe 600 | about 605 to 606 | about -0.3% intraday | 2026-04-29 Europe intraday | Trading Economics |
| Europe | Euro Stoxx 50 | 5,819.08 | -0.29% | 2026-04-29 11:20 CEST delayed estimate | MarketScreener |
| Europe | Germany 10Y Bund | about 3.10% | higher on the day; inflation pressure still building | 2026-04-29 Europe session | Trading Economics; Finobird auction context |
| Europe | UK 10Y Gilt | about 5.23% | still near 2008 highs | 2026-04-29 delayed OTC midday | MarketScreener / Reuters mirror |
| FX | EUR/USD | 1.1749 | last clean official reference carry | 2026-04-27 reference / 2026-04-29 live follow-up pending | ECB reference |
| Commodity / Crypto | BTC | 77,159 | around +1.1% vs prior Asia-close reference band | 2026-04-29 intraday | Economic Times |
| Commodity / Crypto | ETH | about 2,330 | live band only; exact spot needs refresh | 2026-04-29 intraday | Robinhood CF Benchmarks prediction-market ladder |
| Commodity / Crypto | Brent | above 115 | still rising; exact Asia-close settle not available in this run | 2026-04-29 Europe session | Guardian business live |
| Commodity / Crypto | WTI | above 100 | upside close strongly favored intraday; exact official settle pending | 2026-04-29 US-linked intraday | Investopedia; Lines market context |
| Commodity / Crypto | Gold | around 4,600 | near flat to firmer around Fed decision | 2026-04-29 intraday band | Robinhood prediction-market ladder |
| Commodity / Crypto | Silver | about 74.5 | higher on the day | 2026-04-29 00:34 EDT spot | Natural Resource Stocks |

## Trade Thesis Watch List Refresh

Rule used here: if a clean April 29 official close was not retrievable in this environment, the prior visible market-session value is preserved with its own monitor date and a symbol-level follow-up task remains open.

| Thesis | Symbol | Monitor Date | 52H | 52W Low | Today Price | % |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| China AI | BIDU | 2026-04-28 | $165.30 | $81.17 | $125.76 | -1.76% |
| China AI | BABA | 2026-04-28 | $192.67 | $103.71 | $130.85 | -1.26% |
| China AI | 0700 HK | 2026-04-29 | HK$683.00 | HK$469.00 | HK$479.20 | +1.14% |
| China AI | 002230 CN | 2026-04-28 | CNY67.50 | CNY44.98 | CNY49.17 | -1.28% |
| China AI | 0981 HK | 2026-04-29 | HK$93.50 | HK$38.65 | HK$65.80 | -0.38% |
| China AI | 688256 CN | 2026-04-29 | CNY1,595.88 | CNY520.67 | CNY1,391.99 | +1.27% |
| China AI | 600584 CN | 2026-04-28 | CNY54.63 | CNY31.20 | CNY45.10 | -2.63% |
| China AI | 002156 CN | 2026-04-27 | CNY59.20 | CNY22.90 | CNY51.20 | +5.74% |
| China AI | 002185 CN | 2026-04-29 | CNY16.00 | CNY8.60 | CNY12.85 | +1.58% |
| China AI | USD/CNH | 2026-04-29 | n/a | n/a | 6.8167 | +0.10% |
| Global AI Infrastructure | 2899 HK | 2026-04-29 | HK$46.98 | HK$16.70 | HK$36.38 | +2.88% |
| Global AI Infrastructure | SU FP | 2026-04-29 | EUR281.50 | EUR199.30 | EUR270.35 | -0.17% |
| Global AI Infrastructure | ENR GR | 2026-04-28 | EUR191.66 | EUR65.56 | EUR172.98 | -2.50% |
| Global AI Infrastructure | 6501 JP | 2026-04-28 | JPY6,039 | JPY3,516 | JPY5,047 | -5.77% |

## Watch-List Refresh Summary

- The required Asia-close symbol set was refreshed row by row rather than as one blanket table status.
- Hong Kong names `0700 HK`, `0981 HK`, and `2899 HK` now carry April 29 session-date rows from delayed close-time quote pages.
- China A-share names are mixed: `688256 CN` and `002185 CN` had April 29 delayed readings, while `002230 CN`, `600584 CN`, and `002156 CN` still only exposed older visible session rows in this environment and remain open follow-ups.
- Japan's `6501 JP` properly stayed on the April 28 market-session date because April 29 was Showa Day.
- Latest relevant US-listed China ADR closes were carried forward on their April 28 US market date for `BIDU` and `BABA`.

## US Snapshot

- The carried US close remains Tuesday, April 28. The S&P 500 finished at 7,138.80, down 0.49%, and the Nasdaq also pulled back, which keeps the "hold near highs" thesis alive but less comfortable.
- The 10Y Treasury stayed around 4.35% into the Fed window instead of giving equity multiples fresh relief.
- VIX remains populated per runbook. The latest official Cboe-verified close visible in this run is still 18.02 for April 27. The April 28 US close should remain marked `pending official Cboe refresh` until the history file advances.
- By the Asia close on April 29, US futures context looked steadier than Tuesday's cash-session drop, but not enough to erase the combination of high oil plus sticky yields.

## HK / China Snapshot

- China's cash close improved materially versus Tuesday: the Shanghai Composite rose 0.71% to 4,107.51.
- Hong Kong screens showed the Hang Seng up about 1.4% late in the session, which is directionally better, but I still did not verify the exact official 16:00 close from a primary close bulletin in this run.
- The micro read inside the watch list was mixed rather than euphoric. Tencent bounced, SMIC was slightly lower, and Cambricon was still strong on a delayed print.
- USD/CNH stayed controlled around 6.82, so the FX side of China stress did not worsen at this heartbeat.

## Japan Snapshot

- April 29 was Showa Day, so Japan cash equities were closed.
- The correct carry row therefore remains the April 28 close: Nikkei 225 at 59,917.46 and the 10Y JGB around 2.465% after the BOJ hawkish-hold shock.
- That means the BOJ/JGB part of the thesis is unchanged rather than improved. There was no new Japanese cash-session evidence that the April 28 pressure was fading.

## Europe Snapshot

- Europe remained the weak link at the Asia-close handoff. Trading Economics had both the STOXX 50 and STOXX 600 down about 0.3% intraday on April 29.
- MarketScreener showed the Euro Stoxx 50 around 5,819.08, down 0.29%, in delayed trade.
- Bund pressure also stayed elevated. Trading Economics had Germany's 10Y yield around the 3.1% area, while a same-day German 10Y auction printed 3.08% versus 2.92% previously.
- UK gilts were still the most visibly stressed major sovereign market, with delayed market data around the 5.23% area after Tuesday's push toward the highest closes since 2008.

## Commodity / Crypto Snapshot

- Oil stayed the cleanest thesis-confirming macro problem. Reporting in this run still had Brent above $115 and WTI above $100 on April 29.
- BTC consolidated near $77k into the Fed rather than breaking lower, which keeps crypto-liquidity conditions mixed instead of outright stressed.
- ETH looked to be around the low-$2.3k area from the live contract ladders I could retrieve, but I still do not have a clean exact spot print for a session note.
- Gold and silver both stabilized to firmer in the run-up to the Fed, but the key macro signal remains oil rather than metals.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Mixed | US indices are still near highs, but Tuesday's stumble showed less tolerance for sticky yields. | FOMC Apr 29; Treasury refunding May 4-6 |
| Rates And Curve | Watch | USTs remain too high for a clean multiple re-expansion. | FOMC; GDP and core PCE Apr 30 |
| Credit Stress | Watch | Same-day clean HY/OAS and breadth still were not retrieved in this run. | US credit and breadth refresh |
| Consumer And Labor | Mixed | Oil is acting like the bigger macro tax ahead of payrolls and CPI. | GDP/PCE Apr 30; payrolls May 8 |
| Earnings And Breadth | Watch | AI leadership is no longer one-way higher, and breadth still needs confirmation. | Big Tech results; Nvidia timing refresh |
| China Credit Impulse | Mixed | China cash equities improved on Apr 29, but it still does not look like a broad China re-rating. | China PMIs Apr 30; China CPI/PPI May 9 |
| FX And Property Stress | Watch | USD/CNH stayed controlled, but Hong Kong liquidity channels still need a fresh HIBOR read. | CNH and HIBOR refresh |
| BOJ And JGB | Watch | No fresh relief after the hawkish BOJ hold; Japan was closed. | Japan cash reopen Apr 30; Japan CPI May 22 |
| JPY Carry Stress | Watch | The trigger is still dormant rather than gone. | USD/JPY and JGB follow-through |
| Crypto Liquidity | Mixed | BTC held near 77k into the Fed, which is stable but not risk-on. | FOMC; ETF flow and risk-appetite follow-through |
| Oil And Metals | Stress | Oil remains the strongest thesis-confirming macro headwind. | EIA flow; Hormuz headlines; OPEC supply path |

## Thesis Check

Confirming:

- US equities are still close enough to highs that the "hold into Nvidia" leg is not yet broken.
- BOJ/JGB stress was not resolved; the Japan channel remains a live June-risk input.
- Oil staying above the comfort zone keeps inflation and duration pressure alive even without a new equity breakdown.

Weakening:

- China's April 29 cash rebound pushed back against the most bearish immediate Asia read from the prior heartbeat.
- If the Fed leans patient and oil cools quickly, the June-risk timeline gets pushed out again instead of accelerating now.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Probability | Base Case | Upside / Bull Case | Downside / Bear Case | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FOMC decision | 2026-04-29 | No rate change expected | 3.50%-3.75% target range | Market still heavily priced for hold | Hold with patient but not dovish language | Growth-sensitive tone pulls yields lower and extends the index hold | Inflation-credibility emphasis sends yields higher and tightens AI multiples | USTs, USD, Nasdaq, gold, BTC | Confirmed by patient hold; invalidated by a clear hawkish pivot | Fed calendar; market coverage |
| US Q1 GDP advance | 2026-04-30 | about 0.5% SAAR | prior quarter 0.5% third estimate | Market leaning to soft-but-positive growth | Soft but positive growth with no recession shock | Growth cools while inflation mix behaves | Flat or negative growth with sticky inflation revives stagflation fear | UST curve, USD, cyclicals, small caps | Confirmed by positive print and contained inflation mix | BEA schedule |
| US core PCE, March | 2026-04-30 | roughly 0.24%-0.28% m/m; about 3.1% y/y | prior release still firm | Market focus is whether oil pass-through delays easing | Sticky but not re-accelerating | 0.2% area restores some duration relief | 0.3%+ m/m hardens higher-for-longer | Real yields, Nasdaq, gold | Confirmed by contained services inflation; invalidated by reacceleration | BEA schedule |
| ECB decision | 2026-04-30 | Hold expected | prior hold | Market still prices some tightening risk this year | Hold with inflation concern still elevated | Growth concern softens the tone and eases Bunds | Oil shock keeps the stance hawkish | EUR, Bunds, Europe equities | Confirmed by inflation-first language; invalidated by a growth-heavy pivot | ECB calendar; Reuters / market coverage |
| BOE decision | 2026-04-30 | Hold expected | prior hold | Gilt market already behaving as if inflation risk dominates | Hold with hawkish bias | Growth caution cools gilts | Oil/inflation language extends gilt stress | Gilts, GBP, UK equities | Confirmed by inflation emphasis; invalidated by softer guidance | BOE calendar; Reuters / market coverage |
| China PMIs | 2026-04-30 | consensus not cleanly retrievable in this run | prior range-bound mix | Market wants proof that Apr 29 equity rebound is real | Range-bound activity, no broad China re-rating | Clear manufacturing upside helps HSI, CNH, cyclicals | Weak PMIs reopen the China-lag story fast | HSI, CNH, industrial metals | Confirmed by better new orders / manufacturing mix | Follow-up required |
| Treasury refunding estimates and announcement | 2026-05-04 to 2026-05-06 | No major coupon shock expected | February refunding cycle | Long-end risk premium still elevated | Heavy but manageable supply | Supportive mix stabilizes duration | Larger duration burden lifts term premium further | 10Y / 30Y UST, REITs, duration trades | Confirmed by stable sizing; invalidated by larger long-end load | Treasury refunding page |
| US payrolls, April | 2026-05-08 | consensus needs refresh in this run | +178K; unemployment 4.3% | Market sensitive to any labor print that changes Fed-tone expectations | Slower but positive job growth | Cooling without labor breakage helps duration | Hot payrolls or rising unemployment both hurt in different ways | Front end, USD, equities | Confirmed by moderation with stable unemployment | BLS schedule |
| US CPI, April | 2026-05-12 | consensus needs refresh in this run | March CPI 3.3% y/y in prior coverage | Oil makes headline upside the key risk | Headline firm, core only slowly easing | Clear cooling reopens cut debate | Upside surprise extends higher-for-longer | USTs, USD, growth stocks, gold | Confirmed by subdued core services | BLS schedule |
| Nvidia earnings | late May 2026; exact date still needs refresh | Street still wants another beat-and-maintain quarter | prior quarter revenue $68.1B; outlook $78.0B +/- 2% | Positioning still looks crowded | Beat-and-maintain is enough to hold the tape together | Beat-and-raise broadens leadership | Guidance wobble hits crowded AI positioning | Nasdaq, SOX, S&P breadth | Confirmed by data-center strength; invalidated by guide wobble | Nvidia IR |

## Probability-Weighted Policy Scenarios

### FOMC April 29, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 75% | Hold with patient tone | Equities can stay elevated, but yields stay sticky |
| Dovish hold | 10% | Hold and lean softer on growth | Duration and growth outperform; BTC benefits |
| Hawkish hold | 15% | Hold with stronger inflation-credibility emphasis | 10Y up, AI multiples tighten, June pullback risk moves forward |

### ECB April 30, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 70% | Hold with cautious inflation tone | Bunds stay elevated and Europe lags |
| Softer-growth hold | 15% | Hold but emphasize growth risk | Bunds ease and EUR softens |
| Hawkish hold | 15% | Hold with stronger inflation concern | Bund yields push higher and Europe underperforms |

### Treasury Refunding May 4-6, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Manageable supply profile | Long-end pressure persists but does not break markets |
| Bearish supply surprise | 25% | Heavier long-end burden | Term premium rises; rate-sensitive equities lag |
| Supportive mix | 15% | Smaller burden or stronger buyback support | Long end stabilizes and valuation pressure eases |

## Next 7 Days

- 2026-04-29: FOMC decision and Powell press conference.
- 2026-04-30: US Q1 GDP advance estimate.
- 2026-04-30: US personal income and outlays, including core PCE.
- 2026-04-30: ECB decision.
- 2026-04-30: BOE decision.
- 2026-04-30: China PMIs.
- 2026-05-04: Treasury quarterly refunding financing estimates.

## Follow-Up Tasks

- Expose durable storage for `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event`; the active local SQLite file remains empty.
- Backfill every required market snapshot line from `2026-01-01` forward once durable storage exists.
- Verify the official Cboe `VIX_History.csv` row for the 2026-04-28 US close; keep the VIX backfill task open until the file advances.
- Refresh the exact official 2026-04-29 Hang Seng close from a clean close bulletin.
- Refresh exact Apr 29 close rows for `002230 CN`, `600584 CN`, `002156 CN`, `ENR GR`, and any delayed China/Europe watch rows still showing older session dates.
- Refresh clean close-time values for `EUR/USD`, `ETH`, `Brent`, `WTI`, `gold`, `silver`, `USDHKD`, and `HIBOR`.
- Refresh exact consensus values for China PMIs, April payrolls, April CPI, and Nvidia's exact late-May earnings date.

## Backfill Status

- No durable `nj_agent_heartbeat_run` history was available because the active local database file was empty, so missed-window detection still could not be computed from stored rows.
- No durable `nj_agent_backfill_task` rows could be created for the same reason.
- Markdown-tracked pending backfills remain:
- `pending`: heartbeat history bootstrap for missed Asia-close and US-close windows from 2026-01-01 forward, reason `automation_not_run`.
- `pending`: market snapshot historical backfill for required lines from 2026-01-01 forward, reason `automation_not_run`.
- `pending`: official VIX verification for the 2026-04-28 US close, reason `official_source_not_yet_updated`.

## Source Links

- Prior Asia close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-04-28 Asia Close.md`
- Prior US close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-04-29.md`
- Cboe VIX daily history requirement: https://cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv
- Stocknear VIX history snapshot: https://stocknear.com/index/%5EVIX/history
- AP US close recap Apr 28: https://apnews.com/article/b147717d731d3f7cfaf27a9625715c21
- Xinhua US close summary Apr 29: https://www.china.org.cn/world/Off_the_Wire/2026-04/29/content_118468467.shtml
- Xinhua Shanghai close Apr 29: https://english.news.cn/20260429/293485b2527a41408c106a9c5eb21920/c.html
- Xinhua Tokyo close Apr 28: https://english.news.cn/20260428/12c3f1b5fe3f4ebcbf0109646de3ee09/c.html
- MarketScreener Hang Seng quote page: https://in.marketscreener.com/quote/index/HONG-KONG-HANG-SENG-101835/
- Trading Economics Europe stocks Apr 29: https://tradingeconomics.com/euro-area/stock-market/news/546005
- MarketScreener Euro Stoxx 50 quote page: https://www.marketscreener.com/quote/index/EURO-STOXX-50-INDEX-7396/news-components/?p=3026
- Trading Economics Bund yield Apr 29: https://tradingeconomics.com/germany/government-bond-yield/news/545925
- Finobird Germany 10Y auction Apr 29: https://finobird.com/calendar/economic/de-germany-10-year-bund-auction-2026-04-29/
- MarketScreener UK 10Y gilt quote page: https://in.marketscreener.com/news/uk-10-year-gilt-yields-head-for-highest-close-since-2008-ce7f59d2de88f626/
- Economic Times BTC update Apr 29: https://m.economictimes.com/markets/cryptocurrency/crypto-news/bitcoin-consolidates-near-77k-ahead-of-fed-decision-80k-breakout-could-trigger-1-2b-short-squeeze/articleshow/130597043.cms
- Robinhood ETH ladder: https://robinhood.com/us/en/prediction-markets/crypto/events/ethereum-price-on-apr-29-2026-at-7am-edt-apr-29-2026/
- Guardian business live Apr 29 oil context: https://www.theguardian.com/business/live/2026/apr/29/uk-exports-middle-east-iran-war-economy-oil-stock-markets-government-live-updates
- Investopedia Apr 29 pre-open note: https://www.investopedia.com/5-things-to-know-before-the-stock-market-opens-april-29-2026-11960922
- Natural Resource Stocks silver spot page: https://naturalresourcestocks.net/silver-price-today-april-29-2026/
- StockAnalysis `0700 HK`: https://stockanalysis.com/quote/hkg/0700/
- StockAnalysis `002230 CN`: https://stockanalysis.com/quote/she/002230/
- StockAnalysis `0981 HK`: https://stockanalysis.com/quote/hkg/0981/
- StockAnalysis `688256 CN`: https://stockanalysis.com/quote/sha/688256/
- StockAnalysis `600584 CN`: https://stockanalysis.com/quote/sha/600584/
- StockAnalysis `002156 CN`: https://stockanalysis.com/quote/she/002156/
- StockAnalysis `002185 CN`: https://stockanalysis.com/quote/she/002185/
- StockAnalysis `2899 HK`: https://stockanalysis.com/quote/hkg/2899/
- StockAnalysis `SU FP`: https://stockanalysis.com/quote/epa/SU/
- StockAnalysis `ENR GR`: https://stockanalysis.com/quote/etr/ENR/
- StockAnalysis `6501 JP`: https://stockanalysis.com/quote/tyo/6501/
- StockAnalysis `BIDU`: https://stockanalysis.com/stocks/bidu/
- StockAnalysis `BABA`: https://stockanalysis.com/stocks/baba/
- Investing.com USD/CNH quote snapshot: https://www.investing.com/currencies/usd-cnh-historical-data
- Federal Reserve calendar: https://www.federalreserve.gov/newsevents/calendar.htm
- BEA schedule: https://www.bea.gov/news/schedule
- ECB calendar: https://www.ecb.europa.eu/press/calendars/mgcgcc/html/index.en.html
- BOE calendar: https://www.bankofengland.co.uk/news-and-events/calendar
- Treasury refunding page: https://home.treasury.gov/policy-issues/financing-the-government/quarterly-refunding/most-recent-quarterly-refunding-documents
- BLS May 2026 release calendar: https://www.bls.gov/schedule/2026/05_sched_list.htm
- Nvidia FY2026 Q4 press release: https://nvidianews.nvidia.com/news/nvidia-announces-financial-results-for-fourth-quarter-and-fiscal-2026
