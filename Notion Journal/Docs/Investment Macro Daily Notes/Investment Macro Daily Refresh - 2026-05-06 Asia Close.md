# Investment Macro Daily Refresh - 2026-05-06 Asia Close

Heartbeat: Asia close

As of: 2026-05-06 20:36 Asia/Shanghai

Asia market dates carried in this note:

- Hong Kong: 2026-05-06 close
- Mainland China: 2026-05-06 close
- Japan: 2026-05-06 market_closed; latest cash close still 2026-05-01
- Europe: 2026-05-06 intraday overlap; cash close was not yet complete at write-back time, so Europe rows remain clearly labeled intraday or last-close

US market date carried in this note: 2026-05-05 last-close, plus 2026-05-06 U.S. pre-market context where explicitly labeled.

Placement rule: Wednesday, May 6, 2026 in Asia/Shanghai is only the local heartbeat timestamp. U.S. snapshot rows in this run belong to the Tuesday, May 5, 2026 U.S. cash-session close. Hong Kong and mainland China rows belong to Wednesday, May 6, 2026. Japan rows stay on Friday, May 1, 2026 because Tokyo cash equities were closed on Wednesday, May 6, 2026.

Backfill status at start: durable storage remained available in `/Users/mac/Developer/Notion Journal/device-db-snapshots/iphone17pm-current-prefs/notion_journal.sqlite`. No new missed heartbeat window was inferred from the visible durable sequence between the 2026-05-05 Asia-close run and the current run. Pending VIX backfill for the 2026-05-04 U.S. close was checked first and remains pending because the accessible official Cboe / FRED chain still stops at 2026-05-01. A second pending VIX backfill task was created for the 2026-05-05 U.S. close for the same reason.

Storage status: markdown note written. Durable heartbeat and backfill rows were updated in `/Users/mac/Developer/Notion Journal/device-db-snapshots/iphone17pm-current-prefs/notion_journal.sqlite`. The current snapshot schema for `nj_finance_macro_event` does not yet expose the runbook analysis fields, so forecast-analysis write-back remains markdown-only in this run.

## Verdict

The market can still hold near all-time highs into Nvidia, but today’s Asia-close read shifted the balance back toward the June-risk thesis: mainland China finally reopened with a semiconductor-led squeeze, Hong Kong bounced but tech lagged the benchmark, Japan stayed shut while intervention chatter hit USD/JPY, and the U.S. risk bid is still relying on falling oil rather than a clean policy reset.

## Top 3 Changes Since Previous Heartbeat

1. Mainland China reopened with a strong risk-on catch-up. The Shanghai Composite rose `1.17%` to `4,160.17`, and Xinhua said storage chip, semiconductor, and computing-power leasing shares led while oil, tourism, banks, and liquor lagged.
2. Hong Kong recovered Tuesday’s loss, but the internals were less clean than the headline. The Hang Seng rose `1.22%` to `26,213.78`, while the Hang Seng Tech Index gained only `0.80%`, and `0700 HK` fell `1.91%` even as `2899 HK` jumped `4.11%`.
3. The U.S. last-close backdrop improved on lower oil. The S&P 500 finished Tuesday, May 5, 2026 at `7,259.22`, up `0.81%`, the U.S. 10Y eased to `4.43%`, but the latest accessible official VIX close still remained `16.99` for `2026-05-01` even though secondary historical pages show newer values.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,259.22 | +58.47 / +0.81% | 2026-05-05 last-close | AP |
| US | 2Y Treasury yield | 3.93% | -2 bps vs 2026-05-04 | 2026-05-05 official close | U.S. Treasury |
| US | 10Y Treasury yield | 4.43% | -2 bps vs 2026-05-04 | 2026-05-05 official close | U.S. Treasury |
| US | 30Y Treasury yield | 4.98% | -4 bps vs 2026-05-04 | 2026-05-05 official close | U.S. Treasury |
| US | VIX | 16.99 latest accessible official Cboe-source close; 2026-05-04 and 2026-05-05 pending official refresh | official accessible chain still ends at 2026-05-01 | 2026-05-01 official close / 2026-05-05 pending | FRED `VIXCLS` sourced from Cboe |
| HK / China | Hang Seng | 26,213.78 | +315.17 / +1.22% | 2026-05-06 close | Xinhua |
| HK / China | Shanghai Composite | 4,160.17 | +48.01 / +1.17% | 2026-05-06 close | Xinhua |
| Japan | Nikkei 225 | 59,513.12 | market_closed; carry 2026-05-01 close | 2026-05-06 market_closed / 2026-05-01 last-close | JPX; prior verified snapshot |
| Japan | 10Y JGB | 2.47% last verified | 0 bp vs latest verified row | 2026-04-28 last verified / 2026-05-06 carry | prior verified snapshot |
| Europe | STOXX Europe 600 | 618.89 | +1.5% intraday | 2026-05-06 Europe intraday overlap | Reuters |
| Europe | Euro Stoxx 50 | 5,753.36 cash last-close; Europe risk tone sharply firmer intraday | 2026-05-05 cash last-close carried | 2026-05-05 last-close / 2026-05-06 overlap | Investing.com; Reuters |
| Europe | Germany 10Y Bund | 2.99% | down from prior-session highs | 2026-05-06 Europe intraday | WSJ |
| Europe | UK 10Y Gilt | about 5.00% | about -6 to -7 bps intraday after Tuesday spike | 2026-05-06 Europe intraday | Reuters |
| FX | EUR/USD | 1.1728 | about +0.25% vs 2026-05-04 last verified 1.1692 | 2026-05-05 daily close / 2026-05-06 live context | Investing.com historical / BiznesRadar |
| FX | USD/CNH | 6.82 | flat to slightly softer on the day | 2026-05-06 Asia close context | CoinCodex |
| FX | USD/JPY | about 155.0 intraday low after intervention chatter | yen strengthened as much as 1.8% from around 157.8 | 2026-05-06 holiday-thinned Asia trade | Reuters |
| Commodity / Crypto | BTC | 82,022.00 high in-session; prior verified 81,286.38 | about +0.9% vs prior verified print | 2026-05-06 live Asia/Europe overlap | Barron's / Fortune |
| Commodity / Crypto | ETH | 2,388.49 last verified | +2.06% / 24h on latest verified quote | 2026-05-05 08:45 ET verified quote | Fortune |
| Commodity / Crypto | Brent | 109.87 settle; around 108.18 intraday Asia/Europe | -4.0% settle on 2026-05-05; about -1.5% further intraday early 2026-05-06 | 2026-05-05 settle / 2026-05-06 live | Reuters |
| Commodity / Crypto | WTI | 102.27 settle; around 100.60 intraday Asia/Europe | -3.9% settle on 2026-05-05; about -1.6% further intraday early 2026-05-06 | 2026-05-05 settle / 2026-05-06 live | Reuters |
| Commodity / Crypto | Gold | 4,647.09 spot | +2.0% intraday | 2026-05-06 04:15 GMT | Reuters |
| Commodity / Crypto | Silver | 77.82 futures | +5.8% intraday | 2026-05-06 U.S. pre-market context | MarketWatch |

## Trade Thesis Watch-List Refresh

Rule used here: the Asia-close heartbeat refreshed all required rows to the latest clean market-session date by venue. Hong Kong rows were refreshed where a same-session quote was retrievable. Mainland China rows were refreshed where a same-session quote was retrievable; if the source did not expose a clean May 6 close before write-back, the prior verified value stayed visible and the symbol was pushed to follow-up instead of being blanked. Japan stayed on the 2026-05-01 close because the market was closed. Europe rows kept prior verified values where a same-session symbol quote was not cleanly retrievable in this run.

| Thesis | Symbol | Monitor Date | 52H | 52W Low | Today Price | Daily % |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| China AI | 0700 HK | 2026-05-06 | HK$683.00 | HK$469.00 | HK$463.20 | -1.91% |
| China AI | 002230 CN | 2026-05-06 | CNY67.50 | CNY43.45 | CNY49.48 | +3.54% |
| China AI | 0981 HK | 2026-05-05 | HK$93.50 | HK$37.00 | HK$70.80 | -1.87% |
| China AI | 688256 CN | 2026-04-30 | CNY1,595.88 | CNY520.67 | CNY1,699.96 | +20.00% |
| China AI | 600584 CN | 2026-04-30 | CNY54.63 | CNY31.20 | CNY45.56 | +2.71% |
| China AI | 002156 CN | 2026-05-06 | CNY59.20 | CNY21.50 | CNY47.40 | +4.75% |
| China AI | 002185 CN | 2026-04-30 | CNY16.00 | CNY8.60 | CNY13.11 | +2.66% |
| China AI | USD/CNH | 2026-05-06 | n/a | n/a | 6.82 | flat / slightly softer |
| Global AI Infrastructure | 2899 HK | 2026-05-06 | HK$46.98 | HK$16.70 | HK$36.96 | +4.11% |
| Global AI Infrastructure | SU FP | 2026-04-15 | EUR280.05 | EUR196.54 | EUR266.20 | -0.50% |
| Global AI Infrastructure | ENR GR | 2026-04-15 | EUR171.94 | EUR56.04 | EUR169.32 | -0.96% |
| Global AI Infrastructure | 6501 JP | 2026-05-01 | JPY6,039 | JPY2,590 | JPY4,795 | -1.78% |

## Watch-List Refresh Summary

- The required table stayed row-complete without blanking any row to `Needs refresh`.
- `0700 HK` and `2899 HK` were refreshed to the 2026-05-06 local close, and their divergence mattered: Tencent underperformed a strong HSI tape while Zijin outperformed sharply.
- `002230 CN` and `002156 CN` were refreshed to the 2026-05-06 mainland close and confirmed the semiconductor / AI-compute catch-up in the first post-holiday mainland session.
- `0981 HK`, `688256 CN`, `600584 CN`, `002185 CN`, `SU FP`, and `ENR GR` kept the latest clean verified values because a clean same-session quote was not retrievable before note write-back. Those symbols stay visible and become explicit follow-up items rather than generic pending rows.

## US Snapshot

- Tuesday, May 5, 2026 is now the latest valid U.S. cash close. The S&P 500 finished at `7,259.22`, up `0.81%` and back at a record close, according to AP.
- Official Treasury rows eased modestly from Monday’s stress levels: the 2Y closed at `3.93%`, the 10Y at `4.43%`, and the 30Y at `4.98%`.
- VIX remains populated per runbook. The latest accessible official Cboe / FRED close was still `16.99` for `2026-05-01`, so both the May 4 and May 5 U.S. closes remain pending official refresh. Secondary historical pages show `18.29` for May 4 and `17.34` for May 5, but those are not treated as official replacements.
- The U.S. pre-market / global spillover tone improved because oil kept falling on Iran-de-escalation headlines and AMD results helped the AI complex.

## HK / China Snapshot

- Hong Kong rebounded. The Hang Seng rose `1.22%` to `26,213.78`, but the Hang Seng Tech Index gained only `0.80%`, which means today’s leadership was not pure platform / AI beta.
- Mainland China finally reopened after the holiday and delivered the stronger message. The Shanghai Composite rose `1.17%` to `4,160.17`, and Xinhua said storage chip, semiconductor, and computing-power leasing sectors led gains while oil and gas, tourism, banks, and liquor lagged.
- Midday versus close: no clean same-day Hong Kong midday Xinhua row was retrieved in this run, so no midday-versus-close claim is made for May 6.
- Money rotation read: mainland money rotated into semiconductor and AI-compute proxies and rotated out of energy, banks, and defensive reopening laggards. For Hong Kong, the inference from index internals is that resources / old economy outperformed tech because HSI beat HSTECH and `2899 HK` materially outperformed while `0700 HK` fell.

## Japan Snapshot

- Japan cash equities were closed on Wednesday, May 6, 2026, so the latest valid Japan cash close remains Friday, May 1, 2026.
- The more important live Japan read came from FX, not equities. Reuters said the dollar slid from around `157.8` to as low as `155` against the yen in holiday-thinned trading, reviving intervention speculation.
- JGB stress is unresolved even though the live cash market was shut. The BOJ / yen / carry channel remains a live June-risk input.

## Europe Snapshot

- Europe was in overlap trading during the Asia-close heartbeat, and the tone was decisively risk-on. Reuters said the STOXX 600 was up `1.5%` to `618.89`.
- Lower oil also fed through rates. WSJ reported the 10Y U.S. Treasury near `4.351%` in live trade and the 10Y Bund at `2.991%`, while Reuters said gilt yields were down around `6-7 bps` after Tuesday’s stress spike.
- The clean cash close for Euro Stoxx 50 still remains the previous session in this run, so the structured row stays labeled last-close rather than mixing it with intraday overlap.

## Commodity / Crypto Snapshot

- Oil continued to retrace the Monday shock. Reuters said Brent settled Tuesday at `109.87`, down `4.0%`, and WTI settled at `102.27`, down `3.9%`; Wednesday intraday trade extended the decline toward roughly `108.18` for Brent and `100.60` for WTI.
- Gold and silver snapped back hard as the dollar weakened and the market leaned into de-escalation plus lower-yield relief. Reuters put spot gold at `4,647.09`, up `2.0%`, and MarketWatch showed silver futures near `77.82`, up `5.8%`.
- Crypto stayed constructive. Barron’s reported bitcoin hit a fresh three-month high around `$82,022`, while the latest verified Fortune quote still had ETH at `$2,388.49`, up `2.06%` over 24 hours.

## Money Rotation

- HK / China: money rotated into mainland semiconductors and AI-compute infrastructure, while oil, banks, liquor, and tourism lagged. In Hong Kong, index leadership broadened beyond tech, which is better for the benchmark than for the pure China-AI expression.
- Japan: no cash-session rotation signal exists for today because Tokyo was closed. The actionable Japan signal was yen strength on intervention chatter.
- Europe overlap: money rotated back into risk as oil fell and yields eased. This looked like macro-relief rather than a fresh structural growth repricing.
- US carry context: the record U.S. close was supported by lower oil and slightly lower yields. That helps the "hold near highs into Nvidia" leg, but it is still relief-driven rather than broad, policy-clean strength.

## Abnormal Movers / Blue-Chip Alerts

- `0700 HK` / Tencent: closed at `HK$463.20`, down `1.91%`, badly lagging the `+1.22%` Hang Seng day. Why it matters: Hong Kong’s benchmark rebound was not being led by the flagship platform / AI proxy.
- `2899 HK` / Zijin Mining: closed at `HK$36.96`, up `4.11%`. Why it matters: benchmark leadership leaned toward materials / commodity beta instead of pure growth.
- Mainland semiconductor complex: Xinhua explicitly said storage chip and semiconductor sectors led the mainland rebound. Why it matters: today’s China reopen did confirm AI / compute appetite domestically even without fresh closes for every thesis-linked name.
- `USD/JPY`: plunged toward `155` in Reuters trade. Why it matters: intervention-style FX moves keep the BOJ / carry-stress June-risk channel very much alive.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Supportive | The U.S. tape returned to a record close as oil cooled and yields eased. | Treasury refunding details; payrolls `2026-05-08` |
| Rates And Curve | Watch | Treasury yields backed off Tuesday, but the level is still restrictive and relief is oil-driven. | payrolls; U.S. CPI `2026-05-12` |
| Credit Stress | Watch | HSBC remains a live stress marker, but same-session U.S. spread and MOVE confirmation still needs a cleaner pass. | credit-spread / MOVE follow-up |
| Consumer And Labor | Mixed | The market is still waiting for payrolls; no decisive labor reset yet. | payrolls |
| Earnings And Breadth | Mixed | The index made a new high, but Hong Kong tech lagged its own rebound and breadth is still not uniformly clean. | Tencent `2026-05-13`; Nvidia `2026-05-27` |
| China Credit Impulse | Supportive | Mainland reopened with a strong tech / chip-led advance. | China CPI/PPI `2026-05-11`; China activity `2026-05-19` |
| FX And Property Stress | Watch | CNH was contained, but yen intervention chatter and Hong Kong financial stress keep the region on watch. | USD/JPY; HK liquidity follow-up |
| BOJ And JGB | Stress | Japan was closed, but FX action reinforced unresolved BOJ / JGB pressure. | BOJ Summary `2026-05-12`; BOJ `2026-06-16` |
| JPY Carry Stress | Stress | A sudden USD/JPY drop toward `155` is exactly the kind of move that can destabilize carry positioning. | next Japan open; MOF / BOJ signaling |
| Crypto Liquidity | Supportive | BTC stayed firm above `$82K` even as cross-asset leadership shifted. | ETF flow and weekly crypto scan |
| Oil And Metals | Mixed | Oil relief helped risk; metals ripped higher as the dollar fell. | ceasefire durability; EIA; CPI |

## Thesis Check

Confirming:

- The market can still hold near highs into Nvidia because the U.S. last-close returned to a record and oil finally backed off.
- Mainland China’s reopen gave a cleaner AI / compute demand signal than Tuesday’s Hong Kong session.
- The BOJ / yen / carry channel remains a live June-risk factor because intervention chatter is back before Japan even reopens cash equities.

Weakening:

- Hong Kong’s rebound was not led by Tencent or the tech complex.
- The U.S. relief trade still depends heavily on oil falling rather than on a full policy or growth reset.
- Official VIX publication is still lagging badly enough that the clean U.S. volatility read remains incomplete.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Probability | Base Case | Upside / Bull Case | Downside / Bear Case | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| U.S. Treasury quarterly refunding watch | 2026-05-06 | steady coupon sizes remain the working expectation | Q2 borrowing estimate raised to `$189B`; Q3 estimate `$671B` | market still centered on "no fresh supply shock" | Treasury avoids a new duration surprise and the long end stays contained after Tuesday's yield pullback | calm sizing lets the 10Y / 30Y retrace further and preserves the ATH-hold tape | heavier duration burden or poor auction optics lifts term premium again | UST 10Y/30Y, USD, duration equities | Confirmed by steady sizing and calmer long-end trade; invalidated by another bond selloff | U.S. Treasury |
| U.S. payrolls, April | 2026-05-08 | slower but still positive jobs growth | Mar. payrolls `+178K`; unemployment `4.3%` | June Fed hold still dominates | orderly cooling without a labor crack | softer wages and stable unemployment ease rates pressure | hot jobs revive higher-for-longer fears; weak jobs revive hard-landing fears | UST front end, USD, cyclicals, small caps | Confirmed by orderly cooling; invalidated by reacceleration or a crack | BLS |
| China CPI / PPI | 2026-05-11 | CPI near `1.0%` y/y and PPI near `0.5%` y/y remain the working consensus | Mar. CPI `1.0%`; PPI `0.5%` | no clean market-implied series used in this run | benign CPI with producer prices still non-negative | firmer PPI would validate today’s semiconductor-led reopen | softer CPI/PPI would undercut the China catch-up narrative quickly | HSI, CNH, industrial metals, China cyclicals | Confirmed by resilient producer prices; invalidated by renewed disinflation | NBS China |
| U.S. CPI, April | 2026-05-12 | headline still sticky; core services remain the key | Mar. CPI `3.3%`; core `2.6%` | June hold remains dominant | headline firm but core only slowly easing | softer core services stabilizes rates and helps the AI-led tape stay near highs | broad stickiness plus energy pass-through pushes yields back up | USTs, USD, Nasdaq, gold | Confirmed by softer core services; invalidated by broad reacceleration | BLS |
| BOJ Summary of Opinions | 2026-05-12 | hawkish bias without a formal move | Apr. BOJ hold at `0.75%` | intervention chatter raises sensitivity to tone | gradual tightening bias stays intact without an immediate escalation | measured tone plus calmer yen reduces JGB stress | stronger hawkish language hardens expectations for another hike | JGBs, JPY, Nikkei, global carry | Confirmed by measured tone; invalidated by sharply hawkish language | BOJ |
| Tencent earnings | 2026-05-13 | AI monetization, ad strength, and margin discipline stay central | prior result supported platform resilience | current tape implies caution after 2026-05-06 price lag | solid result keeps China platform leadership alive into late May | better AI monetization plus margin beat re-rates Hong Kong tech | weak guide confirms Hong Kong tech is not leading this rebound | Tencent, HSI Tech, Hang Seng, China internet peers | Confirmed by post-print outperformance; invalidated by another relative lag | company schedule |
| Fed-chair transition watch | 2026-05-15 window | policy-premium noise remains high | Powell Chair term scheduled through `2026-05-15` per current journal event row | probability still favors a noisy but orderly transition window | rhetoric stays messy but does not trigger a full independence repricing | calm process trims term premium | louder independence conflict raises duration risk premium | USTs, USD, banks, long-duration tech | Confirmed by calm rhetoric; invalidated by sharp term-premium repricing | Federal Reserve / journal event row |
| China activity data | 2026-05-19 | retail sales / industrial production / FAI remain the key post-holiday reset | prior monthly activity releases were stable enough to avoid a new scare | no public market-implied series used | moderate reopening follow-through after the holiday distortion | activity upside broadens today’s mainland rebound into a fuller China confirmation | weak activity reopens the China-lag trade | HSI, CNH, industrial metals | Confirmed by retail / IP resilience; invalidated by broad miss | NBS China |
| NVIDIA earnings | 2026-05-27 | beat-and-maintain still enough in base case | prior quarterly revenue `$68.1B`; Q1 guide `$78.0B +/-2%` | positioning remains crowded | beat and maintain keeps the tape near highs into late May | beat-and-raise broadens leadership and extends AI momentum | guide wobble hits crowded AI positioning hard | Nasdaq, SOX, S&P breadth, global AI infra | Confirmed by guide confidence; invalidated by growth or margin wobble | NVIDIA IR |
| U.S. PCE | 2026-05-29 | modest core cooling still needed | prior PCE path remains sticky | Fed still anchored to hold | core drifts lower without growth break | softer core reinforces a June hold-with-balance read | sticky core plus oil residuals argue for a more hawkish hold | USTs, USD, growth equities | Confirmed by softer core; invalidated by reacceleration | BEA |
| ECB meeting | 2026-06-04 | hold remains the base case | prior ECB settings unchanged | market still leans toward later tightening bias if inflation risk persists | ECB stays steady and cautious | calmer energy keeps the ECB patient | renewed energy shock re-hardens Europe tightening expectations | EUR, Bunds, STOXX, banks | Confirmed by steady rates and cautious tone; invalidated by stronger tightening signal | ECB |
| BOJ meeting | 2026-06-16 | hold at current settings in base case | Apr. hold | probability still centered on hold-with-bias | hold with tightening bias intact | calmer CPI / FX lets BOJ wait | hot CPI and renewed yen weakness pull BOJ toward the next hike faster | JGBs, JPY, Nikkei, global carry | Confirmed by calmer JGBs / FX; invalidated by hotter inflation and yen stress | BOJ |
| FOMC meeting | 2026-06-17 | no move in base case | Apr. hold | June hold remains dominant | hold with data dependence | softer CPI / PCE / jobs lets the Fed balance its tone | sticky inflation and term-premium noise keep the Fed more hawkish than equities want | USTs, USD, equities, gold, BTC | Confirmed by softer inflation and labor; invalidated by persistent inflation pressure | Federal Reserve |

## Probability-Weighted Policy Scenarios

### U.S. Treasury Refunding, 2026-05-06

| Scenario | Probability | Outcome | Market Read-Through |
| --- | ---: | --- | --- |
| Base case | 55% | Coupon sizes steady; no new duration shock | Long-end stays elevated but avoids another lurch higher |
| Bearish supply surprise | 30% | Heavier duration burden or poor financing optics | 10Y / 30Y rise again; growth-multiple pressure returns |
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

- 2026-05-06: U.S. Treasury refunding statement; Europe / U.S. digest of oil de-escalation.
- 2026-05-08: U.S. payrolls for April.
- 2026-05-11: China CPI / PPI; crypto weekly catalyst scan.
- 2026-05-12: U.S. CPI; BOJ Summary / interpretation window.
- 2026-05-13: Tencent earnings.

## Follow-Up Tasks

- Keep `backfill.vix.official.2026-05-04` pending until the official Cboe / FRED chain prints the May 4 close.
- Create and keep `backfill.vix.official.2026-05-05` pending until the official Cboe / FRED chain prints the May 5 close.
- Refresh same-session symbol rows for `0981 HK`, `688256 CN`, `600584 CN`, `002185 CN`, `SU FP`, and `ENR GR`; prior verified values were preserved instead of being blanked.
- Refresh `HIBOR`, `USDHKD`, and a cleaner U.S. credit-spread / MOVE pass.
- Continue the historical market-snapshot backfill program from `2026-01-01` for required lines wherever durable rows are still absent or malformed.

## Backfill Tasks Created Or Completed

- Kept `pending`: official VIX backfill for the `2026-05-04` U.S. close because the latest accessible official chain still ends at `2026-05-01`.
- Created `pending`: official VIX backfill for the `2026-05-05` U.S. close because the latest accessible official chain still ends at `2026-05-01`.
- No new missed heartbeat window was created in this run.

## Source Links

- Prior Asia-close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-05 Asia Close.md`
- Prior U.S.-close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-05.md`
- Hang Seng close, 2026-05-06: https://english.news.cn/20260506/20e1e7e86b8e40389e830c9750ba1189/c.html
- Shanghai close, 2026-05-06: https://english.news.cn/20260506/ddeaa916a9bc4df59e7eee0ff059685b/c.html
- U.S. close recap, 2026-05-05: https://apnews.com/article/91988a57e184ec1538ecbe94fc1af022
- U.S. Treasury daily par yield curve: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_yield_curve
- FRED VIXCLS: https://fred.stlouisfed.org/series/VIXCLS
- Secondary VIX history reference, 2026-05-05 row visible: https://fi.investing.com/indices/volatility-s-p-500-historical-data
- Reuters Europe equities wrap: https://www.brecorder.com/news/amp/40419887
- Reuters gilt update: https://www.marketscreener.com/news/uk-borrowing-costs-fall-on-hopes-of-possible-us-iran-peace-deal-ce7f58dddf8af327
- WSJ global bond / bund context: https://www.wsj.com/finance/investing/u-s-treasury-yields-seen-vulnerable-to-break-out-from-range-trading-bb2b1ff5
- Reuters USD/JPY intervention chatter: https://ca.investing.com/news/economy-news/dollar-tumbles-against-yen-as-intervention-chatter-swirls-optimism-grows-for-usiran-deal-4611933
- Reuters oil settlement / live follow-through: https://www.moneycontrol.com/news/business/markets/oil-prices-fall-4-as-fragile-us-iran-ceasefire-holds-two-ships-pass-through-strait-of-hormuz-13909777.html
- Reuters Wednesday oil continuation: https://ca.marketscreener.com/news/oil-prices-fall-a-second-day-as-trump-indicates-possible-iran-peace-deal-ce7f58dddb8bf22c
- Reuters gold, 2026-05-06: https://www.brecorder.com/news/40419864/gold-jumps-on-weaker-dollar-middle-east-peace-hopes
- MarketWatch silver futures jump: https://www.marketwatch.com/livecoverage/stock-market-today-dow-s-p-500-and-nasdaq-set-to-rise-as-trump-pause-boosts-sentiment/card/gold-and-silver-surge-as-dollar-slips-on-hopes-for-peace-deal-UVl5ITXFK3kopR7b7PTI
- Fortune BTC, 2026-05-05 verified quote: https://fortune.com/article/price-of-bitcoin-05-05-2026/
- Fortune ETH, 2026-05-05 verified quote: https://fortune.com/article/price-of-ethereum-05-05-2026/
- Barron's BTC high, 2026-05-06: https://www.barrons.com/livecoverage/stock-market-news-today-050626/card/bitcoin-hits-fresh-3-month-high-on-u-s-iran-peace-deal-hopes-NJme7hOsaqPbzmRsLo6w
- Tencent same-session quote: https://nl.investing.com/equities/tencent-holdings-hk-historical-data
- SMIC latest clean verified quote: https://kr.investing.com/equities/smic-historical-data
- Zijin same-session quote: https://th.investing.com/equities/zijin-mining-group-historical-data
- Iflytek same-session quote context: https://ca.investing.com/equities/iflytek-a-technical
- Tongfu same-session quote context: https://www.investing.com/equities/nt-microelectron-a-dividends
- Cambricon latest clean verified quote: https://stockanalysis.com/quote/sha/688256/market-cap/
- JCET latest clean verified quote: https://hk.investing.com/equities/changjiang-ele-historical-data
- Tianshui Huatian latest clean verified quote: https://stockanalysis.com/quote/she/002185/history/
- JPX holiday calendar: https://www.jpx.co.jp/english/corporate/about-jpx/calendar/
