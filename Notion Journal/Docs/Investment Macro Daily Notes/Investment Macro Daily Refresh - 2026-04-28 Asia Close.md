# Investment Macro Daily Refresh - 2026-04-28 Asia Close

Heartbeat: Asia close

As of: 2026-04-28 20:32 Asia/Shanghai

Asia market date: 2026-04-28

US market date carried in this note: 2026-04-27 last-close

Placement rule: Asia rows below are stored on the April 28, 2026 local market-session date. US snapshot rows remain on the Monday, April 27, 2026 US cash-session date even though this heartbeat ran on Tuesday evening in Asia/Shanghai.

Storage status: markdown fallback only. The active local database at `/Users/mac/Developer/Notion Journal/Notion Journal/db.sqlite3` is still 0 bytes, so durable write-back targets `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event` were not available in this run.

## Verdict

The tape is still holding near highs, but the Asia close made the June-risk side of the thesis stronger: BOJ delivered a hawkish hold, JGB pressure stayed hot, China cash equities softened, and oil stayed above the comfort zone before the Fed.

## Top Changes Since Previous Heartbeat

1. BOJ held at 0.75% but the split turned notably hawkish, with three board members favoring a hike to 1.0%, which keeps June tightening pressure live instead of theoretical.
2. Japan lost momentum after Monday's record breakout: Nikkei slipped back from 60,000 while the 10Y JGB still probed 2.48% before easing.
3. China's mainland close weakened on Tuesday and US pre-market context deteriorated, with WTI near $100, Brent above $111, S&P futures lower, and the US 10Y back near 4.36% pre-open.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,173.91 | +8.83 / +0.12% | 2026-04-27 last-close | AP / Xinhua |
| US | 10Y Treasury yield | 4.32% | about +1 bp | 2026-04-27 last-close | Barron's / MarketWatch |
| US | VIX | 18.71 | -0.60 / -3.11% | 2026-04-24 official Cboe close; 2026-04-27 still pending official Cboe verification in this run | Cboe daily history requirement; prior verified row |
| HK / China | Hang Seng | 25,925.65 | carry prior close; 2026-04-28 exact close needs refresh | 2026-04-27 last-close | Xinhua |
| HK / China | Shanghai Composite | 4,078.64 | -0.19% | 2026-04-28 close | Xinhua |
| Japan | Nikkei 225 | 60,072.43 | -0.8% | 2026-04-28 close | Reuters mirror |
| Japan | 10Y JGB yield | 2.46% | about flat vs prior close after touching 2.48% intraday | 2026-04-28 Asia close | Reuters mirror |
| Europe | STOXX Europe 600 | 608.84 | -0.3% intraday today; last cash close was 608.84 on Apr 27 | 2026-04-28 intraday / 2026-04-27 last-close | Barron's / prior Yahoo snapshot |
| Europe | Euro Stoxx 50 | 5,860.32 | carry prior close; today exact intraday level needs refresh | 2026-04-27 last-close | prior Yahoo snapshot |
| Europe | Germany 10Y Bund | 3.05% | above prior 3.036%; inflation pressure up | 2026-04-28 intraday | Trading Economics |
| Europe | UK 10Y Gilt | 5.00% | near flat at 5% handle | 2026-04-28 intraday | WSJ market wrap |
| FX | EUR/USD | 1.1749 | ECB reference carry | 2026-04-27 reference | ECB reference via xrates.eu |
| FX | USD/CNH | 6.83 | reference only; Apr 28 exact spot close needs refresh | 2026-04-27 derived reference / Apr contract context | ECB reference cross / HKEX futures context |
| Commodity / Crypto | BTC | 76,200 | lower vs Monday high near 79,500 | 2026-04-28 US pre-market context | Investopedia |
| Commodity / Crypto | ETH | about 2,280 | intraday band only; exact spot print needs refresh | 2026-04-28 early US session context | Robinhood prediction market band / follow-up required |
| Commodity / Crypto | Brent | 111.57 | +2.6% to +3% intraday | 2026-04-28 intraday | Trading Economics / MarketWatch |
| Commodity / Crypto | WTI | 98.95 | nearly +3% intraday | 2026-04-28 intraday | MarketWatch |
| Commodity / Crypto | Gold | about 4,575 | about -2.5% intraday | 2026-04-28 intraday | Investopedia |
| Commodity / Crypto | Silver | above 67 | exact front-month settlement needs refresh | 2026-04-28 intraday band | Robinhood prediction market band / follow-up required |

## Trade Thesis Watch List Refresh

Rule used here: if a clean April 28 close was not retrievable in this environment, the prior visible market-session value is preserved with its own monitor date and a symbol-level follow-up task is listed below.

| Thesis | Symbol | Monitor Date | 52H | 52W Low | Today Price | % |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| SaaS Overshoot | DDOG | 2026-04-27 | $201.69 | $98.01 | $132.66 | +2.46% |
| SaaS Overshoot | MDB | 2026-04-27 | $444.72 | $167.19 | $264.38 | +4.25% |
| SaaS Overshoot | TEAM | 2026-04-27 | $242.00 | $56.01 | $69.22 | -3.26% |
| SaaS Overshoot | NET | 2026-04-27 | $260.00 | $117.07 | $212.36 | +2.55% |
| SaaS Overshoot | SNOW | 2026-04-27 | $280.67 | $118.30 | $144.25 | +2.80% |
| China AI | BIDU | 2026-04-27 | $165.30 | $81.17 | $128.01 | -0.54% |
| China AI | BABA | 2026-04-27 | $192.67 | $103.71 | $132.52 | -2.43% |
| China AI | 0700 HK | 2026-04-27 | HK$683.00 | HK$469.00 | HK$478.60 | -3.00% |
| China AI | 002230 CN | 2026-04-15 | CNY67.50 | CNY43.45 | CNY47.54 | -1.63% |
| China AI | 0981 HK | 2026-04-27 | HK$93.50 | HK$38.65 | HK$68.25 | +6.14% |
| China AI | 688256 CN | 2026-04-15 | CNY1,595.88 | CNY520.67 | CNY1,274.00 | +2.58% |
| China AI | 600584 CN | 2026-04-15 | CNY54.63 | CNY31.20 | CNY43.59 | -1.69% |
| China AI | 002156 CN | 2026-04-17 | CNY59.20 | CNY21.50 | CNY48.18 | +0.33% |
| China AI | 002185 CN | 2026-04-20 | CNY16.00 | CNY8.60 | CNY12.76 | +0.16% |
| China AI | USD/CNH | 2026-04-27 | n/a | n/a | 6.83 | reference only |
| Global AI Infrastructure | 2899 HK | 2026-04-15 | HK$46.98 | HK$16.70 | HK$37.98 | +0.74% |
| Global AI Infrastructure | SU FP | 2026-04-15 | EUR280.05 | EUR196.54 | EUR266.20 | -0.50% |
| Global AI Infrastructure | ENR GR | 2026-04-15 | EUR171.94 | EUR56.04 | EUR169.32 | -0.96% |
| Global AI Infrastructure | 6501 JP | 2026-04-28 | JPY6,039 | JPY2,590 | JPY5,220 | +5.31% |
| Global AI Infrastructure | VRT | 2026-04-27 | $330.30 | $80.51 | $322.43 | -0.32% |
| Global AI Infrastructure | ETN | 2026-04-27 | $432.34 | $283.00 | $416.77 | -1.69% |

## Watch-List Refresh Summary

- US-listed watch symbols were carried from the April 27 US close note because the next US cash session had not opened yet.
- Japan got a same-session refresh for `6501 JP`, while the broader Nikkei read turned softer after the BOJ hold.
- Several China, Hong Kong, and Europe watch rows were refreshed only to their latest clean visible source date between March 12 and April 20 because exact April 28 close quotes were not cleanly retrievable in this environment.
- The table stays populated instead of collapsing to `Needs refresh`; symbol-level follow-up tasks are listed below for the rows that still need an April 28 session update.

## US Snapshot

- Monday's US cash close is still the latest completed US session: the S&P 500 closed at 7,173.91 and the 10Y Treasury finished around 4.32%.
- Tuesday pre-market context was less friendly by the Asia close. S&P futures were lower, the US 10Y was back up to 4.357% by 09:52 GMT, and oil was re-tightening the inflation narrative.
- VIX remains a known control point. In this run I could not directly verify that the official Cboe CSV had advanced beyond the April 24 row, so the latest verified official value remains 18.71 from April 24 and the April 27 official-close backfill stays open.

## HK / China Snapshot

- Shanghai Composite closed at 4,078.64, down 0.19% on Tuesday, while Shenzhen fell 1.1%, which leans more toward digestion than renewed China impulse.
- Hong Kong exact Tuesday cash close did not surface cleanly in indexed primary coverage during this run, so Hang Seng remains carried at Monday's 25,925.65 with an explicit refresh task rather than a guessed print.
- USD/CNH stayed around the 6.83 handle in the latest clean reference context, but the heartbeat still needs a proper Apr 28 spot close and Hong Kong liquidity channels such as HIBOR.

## Japan Snapshot

- BOJ held its short rate at 0.75%, but the tone was decisively hawkish: three of nine board members favored a hike to 1.0%.
- Nikkei faded after Monday's record breakout and closed at 60,072.43, down 0.8%, while the 10Y JGB touched 2.48% before easing back near 2.46%.
- That keeps the June-risk leg of the thesis alive. Japan is no longer just a background rates story; it is a live trigger path for carry stress and AI-positioning derisking.

## Europe Snapshot

- Europe was still in session at the Asia close. The STOXX 600 was down about 0.3% intraday with Brent back above $110, so I kept exact cash-close rows on the prior April 27 session date where needed.
- Germany's 10Y Bund pushed above 3.05% intraday and the UK 10Y Gilt stayed near 5.00%, reinforcing the global rates-pressure read rather than easing it.
- Schneider Electric and Siemens Energy remain close to their 52-week highs in the watch list, which says the AI-power / electrification trade is still crowded even as macro pressure rises.

## Commodity / Crypto Snapshot

- Oil is still the cleanest thesis-confirming input. Brent was around $111.57 and WTI around $98.95 by the Asia-close read.
- Gold fell back toward $4,575 intraday despite the geopolitical backdrop, which suggests real-rate pressure is counteracting the hedge bid.
- BTC slipped to roughly $76.2k from Monday's highs near $79.5k. ETH looked to be around the $2.28k area, but I could only verify a price band rather than a clean spot print in this environment.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Mixed | Index levels still hold, but pre-market rates and oil are moving the wrong way ahead of the Fed. | FOMC Apr 29 |
| Rates And Curve | Watch | 10Y UST pre-open drift back toward 4.36% keeps valuation relief limited. | FOMC; GDP and core PCE Apr 30 |
| Credit Stress | Watch | No clean HY/OAS update was retrieved in this run. | US credit spread refresh |
| Consumer And Labor | Mixed | Soft landing still possible, but oil is turning into a renewed tax. | GDP/PCE Apr 30; payrolls May 8 |
| Earnings And Breadth | Supportive | US records are intact, but leadership is still narrow and AI remains crowded. | Mega-cap earnings; Nvidia timing refresh |
| China Credit Impulse | Watch | Mainland weakened on Tuesday and Hong Kong close remained incomplete. | China PMIs Apr 30; credit data follow-up |
| FX And Property Stress | Watch | CNH is stable enough for now, but HK liquidity and property channels were not cleanly refreshed. | Asia FX / HIBOR refresh |
| BOJ And JGB | Stress | Hawkish hold plus 2.48% intraday in the 10Y JGB keeps June pressure live. | Ueda briefing fallout; Japan CPI May 22 |
| JPY Carry Stress | Stress | Hawkish BOJ split increases the odds that a June move becomes a broader cross-asset problem. | USD/JPY reaction; June BOJ pricing |
| Crypto Liquidity | Mixed | BTC is still elevated, but the risk appetite bid softened versus Monday highs. | ETF flow updates; ETH spot refresh |
| Oil And Metals | Stress | Oil is again the clearest inflation and policy-risk transmission channel. | EIA / OPEC flow; Hormuz headlines |

## Thesis Check

Confirming:

- US equities are still sitting near record highs, so the "hold near all-time highs into Nvidia" leg remains alive.
- BOJ pressure has become more concrete, not less. A 6-3 split and 10Y JGB stress materially strengthen the June pullback-risk side.
- Oil above $110 Brent is the cleanest external shock channel pushing the macro toward higher-for-longer again.

Weakening:

- China did not add support on Tuesday; Shanghai fell and the Hang Seng close was not cleanly retrievable, so the Asia growth impulse is not helping.
- Gold softened while rates rose, which is more consistent with tighter financial conditions than clean risk-on.
- If the Fed manages a calm hold on April 29 and oil cools quickly, the June-risk timing could still slip.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Scenario Frame | Base Case | Upside | Downside | Markets Most Exposed | Confirmation / Invalidation | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FOMC decision | 2026-04-29 | No change expected | 3.50%-3.75% | Hold remains the dominant market expectation | Hold with patient tone and no near-term cut signal | Softer growth emphasis lowers real yields | Hawkish inflation emphasis lifts 10Y and compresses AI multiples | USTs, USD, Nasdaq, gold, BTC | Confirmed by balanced statement; invalidated by a clear hawkish pivot | Fed calendar; market press |
| US Q1 GDP advance | 2026-04-30 | about 0.5% SAAR | 0.5% prior quarter third estimate | Market treating growth as slower but still positive | Soft but positive growth | Growth cools without inflation scare | Flat / negative GDP with sticky prices | UST curve, USD, cyclicals | Confirmed by positive print and tame inflation mix | BEA schedule; market coverage |
| US core PCE, March | 2026-04-30 | forecast not cleanly retrievable in this run; prior was 2.7% y/y | 2.7% y/y | Market focus is on whether oil spillover prevents easing | Sticky but not re-accelerating | 0.2% m/m type relief | 0.3%+ m/m rekindles higher-for-longer | Real yields, Nasdaq, gold | Confirmed by contained services inflation | BEA schedule; Finobird prior/previous context |
| ECB decision | 2026-04-30 | Hold expected | prior hold | Markets still price 2026 tightening risk because of oil | Hold with hawkish inflation concern | Growth concern dominates and Bunds ease | Oil shock hardens stance further | EUR, Bunds, Europe equities | Confirmed by inflation-first language | ECB calendar; IMF Reuters context |
| BOE decision | 2026-04-30 | Hold expected | prior hold | Gilt market already at 5% makes tone critical | Hold with hawkish bias | Growth caution eases gilts | Oil / inflation tone pushes gilt yields higher | Gilts, GBP, UK equities | Confirmed by inflation emphasis | BOE calendar; WSJ rates wrap |
| Treasury refunding estimates and announcement | 2026-05-04 to 2026-05-06 | No major coupon shock expected | February refunding | Duration supply remains a live term-premium risk | Heavy but manageable supply | Softer mix stabilizes long end | Larger duration burden re-steepens long end | 10Y / 30Y UST, REITs, duration trades | Confirmed by stable sizing language | Treasury official refunding page |
| US payrolls, April | 2026-05-08 | consensus needs refresh | +178K; unemployment 4.3% | Rates market still sensitive after oil shock | Slower but positive payrolls | Cooling labor without unemployment jump | Hot print extends rates fear or weak print revives recession fear | Front end, USD, equities | Confirmed by moderation with steady jobless rate | BLS schedule |
| US CPI, April | 2026-05-12 | consensus needs refresh | March CPI 3.3% y/y in prior coverage | Energy pass-through is the main risk | Headline sticky, core only gradual easing | Clear cooling reopens cut debate | Upside surprise pushes real yields up again | USTs, USD, growth stocks, gold | Confirmed by subdued core services | BLS schedule |
| Japan CPI | 2026-05-22 | consensus needs refresh | prior inflation elevated | BOJ June pricing now more sensitive to this print | Keeps June hike live | Softer CPI cools JGB stress | Hot CPI hardens June tightening odds | JGBs, JPY, Nikkei | Confirmed by sticky core inflation | Japan Statistics Bureau |
| Nvidia earnings | late May 2026; exact date still needs refresh | Street focus remains on another beat and guide sustain | prior quarter revenue $68.1B; next-quarter outlook $78B +/- 2% | Options / positioning remain crowded into the print | Beat and maintain enough to hold index highs | Beat-and-raise broadens leadership | Guidance wobble triggers crowded AI de-risking | Nasdaq, SOX, SPX breadth | Confirmed by data-center strength and capex continuity | Nvidia IR |
| China PMIs | 2026-04-30 and 2026-05-31 | consensus needs refresh | prior mix was range-bound | Market wants proof that China growth is not rolling over | Range-bound activity, no broad re-rating | Upside helps HSI and cyclicals | Weak PMIs deepen China lag | HSI, CNH, industrial metals | Confirmed by better new orders / manufacturing mix | Follow-up required |

## Probability-Weighted Policy Scenarios

### FOMC April 29, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 75% | Hold with patient tone | US equities can stay elevated, but yields stay sticky |
| Dovish hold | 10% | Hold and lean softer on growth | Duration and growth outperform; BTC benefits |
| Hawkish hold | 15% | Hold with stronger inflation credibility emphasis | 10Y up, AI multiples tighten, June pullback risk moves forward |

### Treasury Refunding May 4-6, 2026

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Manageable supply profile | Long-end pressure persists but does not break markets |
| Bearish supply surprise | 25% | Heavier long-end burden | Term premium rises; rate-sensitive equities lag |
| Supportive mix | 15% | Smaller burden or stronger buyback support | Long end stabilizes and valuation pressure eases |

## Next 7 Days

- 2026-04-29: FOMC decision and Powell press conference.
- 2026-04-30: US Q1 GDP advance.
- 2026-04-30: US personal income and outlays, including core PCE.
- 2026-04-30: ECB decision.
- 2026-04-30: BOE decision.
- 2026-04-30: China PMIs.
- 2026-05-04: Treasury quarterly refunding financing estimates.

## Follow-Up Tasks

- Expose durable storage for `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event`; the active local SQLite file remains empty.
- Backfill every required market snapshot line from `2026-01-01` forward once durable storage exists.
- Refresh the official Cboe VIX row for the April 27, 2026 US close and keep the VIX backfill task open until the official file is verified.
- Refresh the exact April 28 Hang Seng close.
- Refresh exact April 28 watch-list closes for `0700 HK`, `0981 HK`, `002230 CN`, `688256 CN`, `600584 CN`, `002156 CN`, `002185 CN`, `2899 HK`, `SU FP`, and `ENR GR`.
- Refresh exact April 28 spot values for `USD/CNH`, `ETH`, and silver.
- Refresh exact consensus values for core PCE, payrolls, CPI, Japan CPI, China PMIs, and Nvidia earnings timing.

## Backfill Status

- No durable `nj_agent_heartbeat_run` history was available because the active local database file was empty, so missed-window detection still could not be computed from stored rows.
- No durable `nj_agent_backfill_task` rows could be created for the same reason.
- Markdown-tracked pending backfills remain:
- `pending`: heartbeat history bootstrap for missed Asia-close and US-close windows from 2026-01-01 forward, reason `automation_not_run`.
- `pending`: market snapshot historical backfill for required lines from 2026-01-01 forward, reason `automation_not_run`.
- `pending`: official VIX verification for the 2026-04-27 US close, reason `official_source_not_yet_verified`.

## Source Links

- Prior US close note for carried US rows: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-04-28.md`
- Cboe VIX daily history: https://cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv
- AP US close recap: https://apnews.com/article/fae9ccf404e6cb4a50360e32c2f9b930
- Xinhua US close summary: https://www.china.org.cn/world/Off_the_Wire/2026-04/28/content_118466502.shtml
- Xinhua Shanghai close Apr 28: https://www.china.org.cn/china/Off_the_Wire/2026-04/28/content_118467650.shtml
- Xinhua Hang Seng last verified close Apr 27: https://www.china.org.cn/china/Off_the_Wire/2026-04/27/content_118465935.shtml
- Reuters BOJ / Nikkei / JGB mirror: https://www.brecorder.com/news/40418614/nikkei-slips-from-record-high-jgbs-wobble-on-bojs-hawkish-hold
- Reuters BOJ decision mirror: https://wtaq.com/2026/04/27/investors-react-to-bojs-decision-to-hold-rates-3/
- Barron's Europe intraday wrap: https://www.barrons.com/livecoverage/stock-market-news-today-042826/card/stock-indexes-mixed-on-higher-oil-earnings-PzWo37cDbt3640Tu8Rdr
- Trading Economics Bund intraday: https://tradingeconomics.com/germany/government-bond-yield/news/545489
- WSJ rates wrap: https://www.wsj.com/finance/investing/jgb-futures-edge-lower-ahead-of-boj-decision-6a0a4e35
- Investopedia premarket wrap Apr 28: https://www.investopedia.com/5-things-to-know-before-the-stock-market-opens-april-28-2026-11959884
- MarketWatch oil wrap Apr 28: https://www.marketwatch.com/story/global-oil-contract-tops-110-after-reports-that-trump-unhappy-with-proposal-from-iran-to-end-war-0708b8ec
- Trading Economics Brent intraday: https://tradingeconomics.com/commodity/brent-crude-oil/news/545475
- ECB reference exchange-rate page: https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/eurofxref-graph-usd.en.html
- ECB reference mirror Apr 27: https://www.xrates.eu/exchange-rate-27-april-2026
- Tencent 0700 prior visible quote: https://0700.hk/
- StockAnalysis 002230: https://stockanalysis.com/quote/she/002230/
- StockAnalysis 0981: https://stockanalysis.com/quote/hkg/0981/
- StockAnalysis 688256: https://stockanalysis.com/quote/sha/688256/
- StockAnalysis 600584: https://stockanalysis.com/quote/sha/600584/
- StockAnalysis 002156: https://stockanalysis.com/quote/she/002156/
- StockAnalysis 002185: https://stockanalysis.com/quote/she/002185/
- StockAnalysis 2899: https://stockanalysis.com/quote/hkg/2899/
- StockAnalysis SU: https://stockanalysis.com/quote/epa/SU/
- StockAnalysis ENR: https://stockanalysis.com/quote/etr/ENR/
- StockAnalysis 6501: https://stockanalysis.com/quote/tyo/6501/
- Federal Reserve calendar: https://www.federalreserve.gov/newsevents/calendar.htm
- BEA schedule: https://www.bea.gov/news/schedule
- Treasury refunding page: https://home.treasury.gov/policy-issues/financing-the-government/quarterly-refunding/most-recent-quarterly-refunding-documents
- BLS May 2026 release calendar: https://www.bls.gov/schedule/2026/05_sched_list.htm
- BOJ calendar: https://www.boj.or.jp/en/about/calendar/
- Japan CPI schedule: https://www.stat.go.jp/english/data/cpi/1582.htm
- Nvidia IR results and outlook context: https://investor.nvidia.com/news/press-release-details/2026/NVIDIA-Announces-Financial-Results-for-Fourth-Quarter-and-Fiscal-2026/
