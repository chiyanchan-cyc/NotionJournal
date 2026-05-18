# Investment Macro Daily Refresh - 2026-05-04 Asia Close

Heartbeat: Asia close

As of: 2026-05-04 20:37 Asia/Shanghai

Asia market dates carried in this note:

- Hong Kong: 2026-05-04 close
- Mainland China: 2026-05-04 market_closed; latest cash close still 2026-04-30
- Japan: 2026-05-04 market_closed; latest cash close still 2026-05-01
- Europe: 2026-05-04 intraday overlap for STOXX 600 / rates; Euro Stoxx 50 cash line remains on the latest verified 2026-04-30 close where same-session cash data was not cleanly retrieved

US market date carried in this note: 2026-05-01 last-close, plus 2026-05-04 U.S. pre-market / rates context where explicitly labeled.

Placement rule: Monday, May 4, 2026 in Asia/Shanghai is only the local heartbeat timestamp. U.S. snapshot rows still belong to the Friday, May 1, 2026 U.S. cash-session close. Hong Kong rows belong to Monday, May 4, 2026. Mainland China rows stay on Thursday, April 30, 2026 because Labour Day closures continue through Tuesday, May 5, 2026. Japan rows stay on Friday, May 1, 2026 because Monday, May 4, 2026 was Greenery Day.

Backfill status at start: no new visible missed-window gap was found in the markdown chain before this run. Durable `nj_agent_heartbeat_run` / `nj_agent_backfill_task` inspection still could not run because the active local database remains unavailable.

Storage status: markdown fallback only. The active local database at `/Users/mac/Developer/Notion Journal/Notion Journal/db.sqlite3` is still 0 bytes, so durable targets `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event` were not available for write-back in this run.

## Verdict

The market is still holding together into Nvidia, but today’s Asia-close read is narrower than broad: Hong Kong rotated back into tech, China cash is still shut, Japan was closed, and the live macro pressure point remains higher oil plus a firmer global-rates tape rather than any fresh collapse in equity risk appetite.

## Top Changes Since Previous Heartbeat

1. Hong Kong delivered the first real post-holiday Asia cash session: the Hang Seng closed up 1.24% at 26,095.88, with IT up 2.3% while energy fell 1.7%, giving a clean “into tech, out of energy” rotation signal.
2. Mainland China stayed closed and Japan was shut for Greenery Day, so today still was not a full Asia confirmation tape; the Shanghai Composite remains on the 2026-04-30 close and Tokyo’s latest cash session remains 2026-05-01.
3. U.S. pre-market context turned more cautious even as the Friday U.S. close still anchors the bullish side of the thesis: S&P futures were roughly flat to slightly positive, but the U.S. 10Y was back around 4.40% intraday and Brent was back above $112.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,230.12 | +21.11 / +0.29% | 2026-05-01 last-close | AP |
| US | 2Y Treasury yield | 3.88% | unchanged vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | 10Y Treasury yield | 4.39% | -1 bp vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | 30Y Treasury yield | 4.97% | -1 bp vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | VIX | 16.89 latest accessible official Cboe close; 2026-05-01 still pending official Cboe refresh | -1.92 / -10.21% vs 2026-04-29 on latest official chain | 2026-04-30 official close / 2026-05-01 pending | Cboe / FRED mirror |
| HK / China | Hang Seng | 26,095.88 | +319.35 / +1.24% | 2026-05-04 close | Xinhua; Reuters |
| HK / China | Shanghai Composite | 4,112.16 | market_closed; carry 2026-04-30 close during Labour Day holiday | 2026-05-04 market_closed / 2026-04-30 last-close | Xinhua |
| Japan | Nikkei 225 | 59,513.12 | market_closed; carry 2026-05-01 close for Greenery Day | 2026-05-04 market_closed / 2026-05-01 last-close | Xinhua; JPX |
| Japan | 10Y JGB yield | 2.5%+ zone | market_closed; elevated near multi-decade highs | 2026-05-04 market_closed / 2026-05-01 latest context | BOJ / market context |
| Europe | STOXX Europe 600 | 608.40 | -2.88 / -0.47% intraday | 2026-05-04 Europe intraday | Investing.com |
| Europe | Euro Stoxx 50 | 5,881.51 | +65.03 / +1.12% cash last-close; Europe open | 2026-04-30 last-close / 2026-05-04 carry | Investing.com |
| Europe | Germany 10Y Bund | 3.056% | +1.9 bps intraday | 2026-05-04 Europe intraday | WSJ / Tradeweb context |
| Europe | UK 10Y Gilt | 5.237% | elevated; still near highest levels since 2008 | 2026-05-04 Europe intraday | MarketScreener |
| FX | EUR/USD | 1.1702 | carry of latest verified ECB reference | 2026-04-30 official ECB reference | ECB |
| FX | USD/CNH | 6.8225 | -0.11% | 2026-05-04 close | Investing.com |
| Commodity / Crypto | BTC | 79,753.73 | +1.7% / 24h | 2026-05-04 Asia run | CoinGecko |
| Commodity / Crypto | ETH | 2,361.86 | +2.3% / 24h | 2026-05-04 Asia run | CoinGecko |
| Commodity / Crypto | Brent | 112.14 | +3.7% intraday | 2026-05-04 Europe / Asia overlap | WSJ |
| Commodity / Crypto | WTI | 105.62 | +3.6% intraday | 2026-05-04 Europe / Asia overlap | WSJ |
| Commodity / Crypto | Gold | 4,597.70 | -1.0% intraday in New York futures | 2026-05-04 06:51 GMT | WSJ |
| Commodity / Crypto | Silver | 75.33 | -1.4% futures | 2026-05-04 06:51 GMT | WSJ |

## Trade Thesis Watch List Refresh

Rule used here: the Asia-close heartbeat refreshed all required rows to the latest clean market-session date by venue. Hong Kong rows were updated to 2026-05-04 where a same-session quote was retrievable. Mainland China rows stay on 2026-04-30 because the cash market remains closed through 2026-05-05. Japan stays on the 2026-05-01 close because 2026-05-04 was Greenery Day. Europe rows keep prior visible values where a same-session symbol quote was still not cleanly retrievable in this run.

| Thesis | Symbol | Monitor Date | 52H | 52W Low | Today Price | Daily % |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| China AI | 0700 HK | 2026-05-04 | HK$683.00 | HK$469.00 | HK$473.20 | +1.15% |
| China AI | 002230 CN | 2026-04-30 | CNY67.50 | CNY43.45 | CNY47.79 | -0.56% |
| China AI | 0981 HK | 2026-04-15 | HK$93.50 | HK$38.65 | HK$59.30 | +2.33% |
| China AI | 688256 CN | 2026-04-30 | CNY1,595.88 | CNY520.67 | CNY1,699.96 | +20.00% |
| China AI | 600584 CN | 2026-04-30 | CNY54.63 | CNY31.20 | CNY45.56 | +2.71% |
| China AI | 002156 CN | 2026-04-30 | CNY59.20 | CNY21.50 | CNY51.77 | +4.59% |
| China AI | 002185 CN | 2026-04-30 | CNY16.00 | CNY8.60 | CNY13.11 | +2.66% |
| China AI | USD/CNH | 2026-05-04 | n/a | n/a | 6.8225 | -0.11% |
| Global AI Infrastructure | 2899 HK | 2026-04-15 | HK$46.98 | HK$16.70 | HK$37.98 | +0.74% |
| Global AI Infrastructure | SU FP | 2026-04-15 | EUR280.05 | EUR196.54 | EUR266.20 | -0.50% |
| Global AI Infrastructure | ENR GR | 2026-04-15 | EUR171.94 | EUR56.04 | EUR169.32 | -0.96% |
| Global AI Infrastructure | 6501 JP | 2026-05-01 | JPY6,039 | JPY2,590 | JPY4,815 | -5.01% |

## Watch-List Refresh Summary

- The required table stayed row-complete without any row collapsing to `Needs refresh`.
- `0700 HK` was refreshed to the 2026-05-04 Hong Kong session, but the practical read is still “participated, not locally rerated” because Tencent remained below the latest accessible ADR-implied reference.
- Mainland China AI rows were upgraded from older April dates to the 2026-04-30 last cash session where cleaner StockAnalysis rows were available.
- `2899 HK`, `SU FP`, and `ENR GR` still need a cleaner same-session refresh; prior verified values were kept visible and are now explicit follow-up work instead of hidden staleness.

## US Snapshot

- Friday, May 1, 2026 remains the latest valid U.S. cash close. The S&P 500 finished at 7,230.12 and still anchors the “hold into Nvidia” part of the thesis.
- Treasury closes from May 1 still read 2Y 3.88%, 10Y 4.39%, and 30Y 4.97%, but by Monday Europe-hours the U.S. 10Y had already edged back to 4.400%, which matters more than the unchanged Friday snapshot.
- U.S. pre-market tone was cautious rather than broken. Reuters/Marketscreener showed S&P 500 e-minis up 0.08%, Dow futures down 0.17%, and Nasdaq 100 futures up 0.24%.
- VIX remains populated per runbook. The direct Cboe history file was still not cleanly retrievable in this environment, so the note keeps the latest accessible official Cboe close and leaves 2026-05-01 marked pending official Cboe refresh.

## HK / China Snapshot

- Hong Kong finally printed a fresh post-holiday session. Hang Seng closed at 26,095.88, up 1.24%, while Hang Seng Tech gained 2.16%.
- Mainland China is still closed for Labour Day and reopens on Wednesday, May 6, 2026. That means today’s Hong Kong move is constructive, but it is not full HK-China confirmation yet.
- Money rotation was clear: Reuters said the Hang Seng IT sub-index rose 2.3% while the energy sub-index fell 1.7%.
- `USD/CNH` at 6.8225 tightened modestly, so the FX side of the China-stress read improved rather than worsened.
- `HIBOR` still lacks a same-session May 4 pull in this run; the latest visible one-month HIBOR remains 2.44238% on 2026-04-30.

## Japan Snapshot

- Japan cash equities were closed for Greenery Day on Monday, May 4, 2026. JPX also shows May 5 and the May 6 observed holiday inside the Golden Week sequence.
- The latest valid Japan cash close therefore remains Friday, May 1, 2026: Nikkei 225 at 59,513.12, up 0.38%.
- The unresolved macro issue remains rates, not the holiday-closed equity tape. The 10Y JGB is still in the 2.5%+ zone and keeps BOJ normalization plus carry-stress risk alive.

## Europe Snapshot

- Europe was still trading during the Asia-close overlap. The best clean same-session read retrieved here was the STOXX Europe 600 at 608.40, down 0.47% intraday.
- The Euro Stoxx 50 cash line remains on the latest verified 2026-04-30 close at 5,881.51, while front futures were modestly positive around 5,856.
- Rates were the more important message: Germany’s 10Y Bund rose to about 3.056%, and the UK 10Y gilt stayed elevated around 5.237%.

## Commodity / Crypto Snapshot

- Oil re-tightened. WSJ reported Brent up 3.7% to $112.14 and WTI up 3.6% to $105.62 as the market kept pricing prolonged Strait of Hormuz disruption risk.
- Crypto stayed firm: BTC was about $79.8K and ETH about $2.36K, both up on a 24-hour basis.
- Precious metals slipped with higher-for-longer rate pressure still in the mix. Gold futures were near $4,597.70 and silver futures near $75.33 in the latest cited pass.

## Money Rotation

- HK / China: money rotated into internet / AI beta and out of energy. Xiaomi, Alibaba, and Xinyi Solar led; PetroChina and CNOOC lagged.
- Japan: no cash-session rotation signal today because Tokyo was closed. The live Japan read is still rates / FX, not sector rotation.
- US / Europe spillover: U.S. index-futures resilience kept the Hong Kong tech bid alive, but Europe’s live session was softer because higher oil and higher rates still matter more there than in the U.S. megacap-led tape.

## Abnormal Movers / Blue-Chip Alerts

- `0700 HK` / Tencent: stock participated in the risk-on session but still traded below the latest accessible ADR-implied Hong Kong reference. Why it matters: today looked like basket beta, not a clean Tencent-specific rerating. Follow-up: keep focus on the 2026-05-13 Q1 result.
- `9988 HK` / Alibaba: one of the stronger H-share leaders on the day, up more than 4% in Reuters and above ADR-implied parity in the local checkpoint note. Why it matters: platform AI / cloud monetization anticipation is concentrating into the May 13 result window. Follow-up: watch for T+1 gap-hold behavior rather than chasing the first pop.
- `1810 HK` / Xiaomi: strongest major Hong Kong blue-chip move in Reuters’ wrap at +6.75%. Why it matters: it confirms money came into higher-beta consumer-tech / AI-linked names, not just defensives. Follow-up: check whether the gain survives once mainland China reopens.
- `00883 HK` / CNOOC and `00857 HK` / PetroChina: both were among the day’s notable losers despite higher crude. Why it matters: local equity investors used the session to rotate away from energy even with oil re-bidding globally. Follow-up: if oil stays high but HK energy keeps lagging, treat that as positioning fatigue rather than an all-clear on inflation risk.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Supportive | Friday’s U.S. close still sits at record highs, and futures did not break materially by Asia close. | Treasury financing estimates; payrolls |
| Rates And Curve | Mixed | Friday’s close was benign, but Monday Europe-hours put the U.S. 10Y back around 4.40% and Bunds/Gilts higher. | Treasury refunding; U.S. CPI |
| Credit Stress | Watch | Clean HY / IG spread and MOVE refreshes are still incomplete. | U.S. credit-spread pass; rates-vol check |
| Consumer And Labor | Mixed | No fresh labor data yet; higher oil keeps inflation-sensitive downside scenarios alive. | JOLTS; payrolls; CPI |
| Earnings And Breadth | Supportive | Index highs still hold, but the global tape is still narrower than broad. | AMD; DDOG; NET; Nvidia |
| China Credit Impulse | Watch | Hong Kong rallied, but mainland cash is still closed and China property / credit stress is not disproved. | China reopen May 6; China CPI/PPI |
| FX And Property Stress | Watch | `USD/CNH` improved, but HK liquidity channels still need a cleaner same-session `HIBOR` pass. | CNH / HKD / HIBOR refresh |
| BOJ And JGB | Stress | Japan was closed, but the rates problem did not disappear with the holiday. | BOJ Summary May 12; Japan CPI May 22 |
| JPY Carry Stress | Stress | Elevated JGB yields still keep yen-strength / carry unwind risk active. | USD/JPY and JGB follow-through |
| Crypto Liquidity | Mixed | Crypto is firm, but still secondary to oil and rates in the macro stack. | ETF flows; cross-asset follow-through |
| Oil And Metals | Stress | Oil is back above $112 Brent while metals are still behaving like hedges, not like disinflation confirmation. | EIA; payrolls; CPI; OPEC+ June 7 |

## Thesis Check

Confirming:

- Friday’s U.S. cash close still supports the idea that the market can hold near all-time highs into Nvidia.
- Today’s Hong Kong tape showed risk appetite is still willing to rotate back into platform / AI beta when U.S. tech stays stable.
- Japan’s rates channel still validates the BOJ / carry-stress side of the June-risk thesis even on a holiday session.

Weakening:

- Today was not a full Asia confirmation because mainland China was still closed and Japan cash was shut.
- Oil moving back above $112 Brent tightens the inflation / rates risk that could start to crowd out the “hold near highs” scenario sooner than planned.
- Tencent still lagging ADR parity weakens the idea that all major China-platform names are already being embraced ahead of earnings.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Probability | Base Case | Upside / Bull Case | Downside / Bear Case | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| U.S. Treasury financing estimates | 2026-05-04 | release due 3:00 p.m. ET | Feb. 2 estimates | no clean public probability series; rates already elevated | Borrowing need rises, but no immediate coupon-size shock signal | Manageable estimate lets long yields stabilize near 4.40% | Bigger borrowing estimate restarts the long-end selloff | USTs, growth stocks, USD | Confirmed by calm long-end reaction; invalidated by a term-premium jump | U.S. Treasury; WSJ |
| AMD earnings | 2026-05-05 | AI and data-center demand should still be solid | prior strong AI setup | semis remain priced for good demand, not perfect guidance | Good print keeps semis bid into Nvidia | Strong AI commentary broadens AI leadership again | Any guide wobble damages the “hold into Nvidia” thesis quickly | SOXX, SMH, QQQ, NVDA sympathy | Confirmed by strong DC / AI commentary; invalidated by guide wobble | company IR; market setup |
| Treasury refunding announcement | 2026-05-06 | coupon sizes broadly expected steady | Feb. 4 steady sizing | Reuters preview still leans steady | No duration surprise | Steady sizing calms duration risk | Heavier long-end load re-tightens conditions | 10Y/30Y, REITs, growth | Confirmed by steady sizing; invalidated by heavier supply | U.S. Treasury; Reuters |
| Datadog and Cloudflare earnings | 2026-05-07 | key SaaS overshoot check | TEAM already printed a strong first proof point | software beta still wants beat-and-hold follow-through | At least one clean reward signal keeps the SaaS overshoot trade alive | Beat-and-hold broadens the software rebound | Beat-but-fade damages the overshoot thesis fast | DDOG, NET, IGV | Confirmed by T+1/T+2 holds; invalidated by good numbers sold on impact | company IR calendars |
| U.S. payrolls, April | 2026-05-08 | 178K consensus; unemployment 4.3% | Mar. +178K, 4.3% | no clean prediction-market series used in this run | Slower but still healthy labor data | Cooling payrolls ease rate pressure without macro damage | Hot payrolls revive higher-for-longer fears; weak payrolls revive hard-landing fears | front end, USD, small caps, cyclicals | Confirmed by orderly cooling; invalidated by reacceleration or a crack | BLS; Trading Economics |
| China CPI / PPI, April | 2026-05-11 | CPI 1.0% y/y; PPI 0.5% y/y consensus | Mar. CPI 1.0%; PPI 0.5% | no clean market-implied series | Benign inflation with producer prices still marginally positive | Stable inflation mix helps HSI, CNH, and cyclicals | Softer CPI/PPI revives China-lag concerns | HSI, CNH, metals | Confirmed by stable core and non-negative PPI; invalidated by renewed disinflation | NBS; Trading Economics |
| Fed-chair transition / Warsh Senate vote window | week of 2026-05-11 | vote timing still points to the week of May 11 | committee advanced nomination on 2026-04-29 | no clean public probability series; policy premium remains in long bonds | Process advances without immediate repricing shock | Confirmation is orderly and the policy premium eases | Confirmation turns into a louder Fed-independence fight | USTs, USD, banks, long-duration tech | Confirmed by calm rhetoric; invalidated by Senate conflict | Reuters |
| BOJ Summary of Opinions | 2026-05-12 | qualitative release around 8:50 a.m. JST | Apr. 27-28 BOJ hold at 0.75% | rates market still biased toward eventual further tightening | Still gradual tightening bias without immediate action | Tone is less urgent and JGB pressure eases | Tone validates faster normalization and pushes JGBs / JPY higher | JGBs, JPY, Nikkei carry trades | Confirmed by measured language; invalidated by stronger inflation / FX urgency | BOJ |
| U.S. CPI, April | 2026-05-12 | headline 3.3% y/y consensus | Mar. 3.3% y/y; core 2.6% | June FOMC hold still dominant | Headline stays firm while core only eases slowly | Softer core services balance the Fed outlook | Headline and core both re-accelerate | USTs, USD, Nasdaq, gold | Confirmed by softer core services; invalidated by broad stickiness | BLS; Trading Economics |
| Nvidia Q1 FY2027 earnings | 2026-05-20 | reports after the close; prior quarter revenue $68.1B and Q1 guide $78.0B +/- 2% | Q4 FY2026 revenue $68.1B | positioning remains crowded | Beat-and-maintain is enough to keep the tape together | Beat-and-raise broadens leadership and extends the rally | Guide wobble hits crowded AI positioning hard | Nasdaq, SOX, S&P breadth | Confirmed by strong DC demand and guide confidence; invalidated by growth or margin wobble | Nvidia IR |
| Japan CPI, April | 2026-05-22 | nationwide April CPI due May 22 | Mar. nationwide core CPI 1.8% y/y | no clean market-implied series retrieved | Sticky-enough inflation keeps BOJ normalization alive but gradual | Softer CPI cools JGB pressure and carry stress | Hot CPI validates another BOJ step sooner | JGBs, JPY, Nikkei | Confirmed by contained services and core; invalidated by hotter underlying inflation | Statistics Bureau of Japan |
| OPEC+ follow-up meeting | 2026-06-07 | seven countries review market conditions after the June adjustment | May 3 decision set a 188 kbpd June adjustment | monthly review keeps policy flexible | Incremental supply remains data-dependent | Added barrels cap upside in crude | Geopolitics or weak compliance keep oil elevated | Brent, WTI, inflation breakevens, EM FX | Confirmed by stable crude; invalidated by renewed squeeze | OPEC |
| BOJ meeting | 2026-06-15 to 2026-06-16 | hold in base case | Apr. 27-28 hold at 0.75% | rates pressure still skews hawkish | Hold with tightening bias intact | Calmer inflation / FX lets BOJ wait | Inflation and FX pressure pull BOJ closer to another hike | JGBs, JPY, Nikkei, carry | Confirmed by calmer JGBs and FX; invalidated by hotter CPI and renewed yen weakness | BOJ |
| FOMC meeting | 2026-06-16 to 2026-06-17 | hold in base case | Apr. 28-29 hold | June hold remains dominant | Hold with data dependence | Softer CPI/PCE and slower jobs allow a more balanced tone | Oil-plus-core persistence keeps the Fed more hawkish than equities want | USTs, USD, equities, gold, BTC | Confirmed by softer inflation and labor; invalidated by persistent inflation pressure | Federal Reserve |

## Probability-Weighted Policy Scenarios

### Treasury Refunding / Financing Mix

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 60% | Financing estimates rise, coupon sizes stay unchanged | Long-end pressure stays elevated but contained |
| Bearish supply surprise | 25% | Borrowing estimate or guidance signals earlier coupon-size increases | Term premium rises and duration-sensitive equities lag |
| Supportive mix | 15% | Manageable estimate and calm language | 10Y/30Y stabilize further |

### BOJ on 2026-06-15 to 2026-06-16

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 55% | Hold at 0.75% with tightening bias intact | JGBs stay pressured and carry remains fragile |
| Calmer hold | 15% | Hold and downplay urgency | JGB yields ease and Nikkei pressure fades |
| More hawkish hold | 30% | Hold but validate another hike soon | JGB yields and JPY jump; risk assets wobble |

### FOMC on 2026-06-16 to 2026-06-17

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 65% | Hold with data dependence and no clean easing signal | Highs can hold, but rates stay a valuation headwind |
| Dovish hold | 15% | Hold and lean toward softer labor / inflation conditions | Duration and quality growth outperform |
| Hawkish hold | 20% | Hold with stronger inflation concern after energy pass-through | 10Y rises again and June pullback risk increases |

## Next 7 Days

- 2026-05-04: U.S. Treasury financing estimates.
- 2026-05-05: HSBC result / dividend window in Hong Kong; U.S. JOLTS; AMD earnings after the U.S. close.
- 2026-05-06: Mainland China cash market reopens; U.S. Treasury refunding announcement.
- 2026-05-07: Datadog and Cloudflare earnings; BOJ March minutes.
- 2026-05-08: U.S. payrolls for April.
- 2026-05-11: China CPI / PPI for April; Warsh Senate vote window.
- 2026-05-12: BOJ Summary of Opinions; U.S. CPI for April.

## Follow-Up Tasks

- Expose durable storage for `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event`; the active local SQLite file remains empty.
- Backfill every required market snapshot line from `2026-01-01` forward once durable storage exists.
- Verify the official Cboe `VIX_History.csv` row for the Friday, May 1, 2026 U.S. close; keep that row marked pending official Cboe refresh until the file is directly fetchable.
- Refresh same-session `2899 HK`, `0981 HK`, `SU FP`, and `ENR GR` quote rows on the next open-market heartbeat if cleaner venue data is accessible.
- Refresh same-session `USDHKD`, `HIBOR`, MOVE, and clean U.S. HY / IG spread prints.

## Backfill Status

- No durable `nj_agent_heartbeat_run` history was available because the active local database file is still empty, so missed-window detection still could not be computed from stored rows.
- No durable `nj_agent_backfill_task` rows could be created for the same reason.
- Visible markdown fallback history shows the 2026-05-03 Asia-close heartbeat and the 2026-05-04 U.S.-close carry note are already present, so this run did not expose a new visible missed-window gap.
- Markdown-tracked pending backfills remain:
- `pending`: heartbeat history bootstrap for missed Asia-close and U.S.-close windows from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: market snapshot historical backfill for required lines from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: official VIX verification for the `2026-05-01` U.S. close, reason `official_source_not_yet_updated`.

## Source Links

- Prior Asia-close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-03 Asia Close.md`
- Prior U.S.-close carry note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-04.md`
- AP Friday, May 1, 2026 U.S. close recap: https://apnews.com/article/ee0fd67a1f14608ef46165f6dd693592
- U.S. Treasury daily par yield curve rates: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_yield_curve
- Hong Kong close: https://english.news.cn/20260504/85dfd58e25584d70b3093b2b1be69e75/c.html
- Reuters Hong Kong close wrap: https://www.indopremier.com/ipotnews/newsDetail.php?group_news=IPOTNEWS&halaman=1&jdl=Hong_Kong_shares_track_firmer_Asia__tech_stocks_lead&name=&news_id=217340&q=hong+kong+stocks%2C+hang+seng%2C&search=y_general&taging_subtype=MARKETOVERVIEW
- JPX market holidays: https://www.jpx.co.jp/english/corporate/about-jpx/calendar/
- SSE Labour Day closure notice: https://www.sse.com.cn/disclosure/announcement/general/c/c_20260423_10816345.shtml
- ECB euro reference rates: https://www.ecb.europa.eu/stats/policy_and_exchange_rates/euro_reference_exchange_rates/html/index.en.html
- USD/CNH historical data: https://hk.investing.com/currencies/usd-cnh-historical-data
- STOXX 600 historical / live page: https://kr.investing.com/indices/stoxx-600-historical-data
- Euro Stoxx 50 historical page: https://fi.investing.com/indices/eu-stoxx50-historical-data
- Euro Stoxx 50 futures page: https://fi.investing.com/indices/eu-stocks-50-futures-historical-data
- UK 10Y cash page: https://ca.marketscreener.com/quote/interest/UK-10Y-CASH-146043546/
- U.S. / eurozone yields context: https://www.wsj.com/articles/treasury-yields-steady-as-oil-trades-well-below-thursdays-peak-99a78de1
- Gold / silver intraday context: https://www.wsj.com/finance/commodities-futures/gold-edges-higher-amid-signs-of-resilience-627248e3
- BTC page: https://www.coingecko.com/en/coins/bitcoin
- ETH page: https://www.coingecko.com/en/coins/ethereum
- Tencent local quote context: https://www.etnet.com.hk/www/sc/stocks/realtime/quote.php?code=981
- Reuters U.S. pre-market futures snapshot: https://www.marketscreener.com/news/us-s-p-500-e-mini-futures-up-0-08-dow-futures-down-0-17-nasdaq-100-futures-up-0-24-ce7f58dedc8bf323
