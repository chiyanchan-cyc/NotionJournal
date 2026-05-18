# Investment Macro Daily Refresh - 2026-05-03

Heartbeat: US close backfill

As of: 2026-05-03 05:31 Asia/Shanghai

US market date: 2026-05-01

Backfill label: this run backfills the missed `2026-05-02 05:30 Asia/Shanghai` US-close heartbeat window and writes the market snapshot against the Friday, May 1, 2026 US cash-session date.

Placement rule: Sunday, May 3, 2026 in Asia/Shanghai is only the local heartbeat timestamp. US snapshot rows below belong to the Friday, May 1, 2026 US cash close. The latest valid Japan rows belong to Friday, May 1, 2026. Hong Kong and mainland China remain on Thursday, April 30, 2026 because Friday, May 1 was a holiday and Saturday, May 2 was not a trading day.

Storage status: markdown fallback only. The active local database at `/Users/mac/Developer/Notion Journal/Notion Journal/db.sqlite3` is still 0 bytes, so durable targets `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event` were not available for write-back in this run.

## Verdict

The tape still held near record highs into Nvidia on the Friday, May 1, 2026 US close, so the near-term thesis leg remains intact, but this backfill did not weaken the June-risk side: BOJ/JGB pressure, the Warsh Fed-chair transition, and crowded AI positioning still look like the main convergence risks once the post-earnings hold stops doing the work.

## Top Changes Since Previous Heartbeat

1. This run closes the missed US-close window rather than adding a newer US session: the relevant market date is still Friday, May 1, 2026, because the heartbeat ran on Sunday, May 3, 2026 Asia time and no later US cash close exists yet.
2. VIX handling improved but is still not fully complete. The latest verifiable official Cboe-source close available through the accessible source chain is `16.89` for Thursday, April 30, 2026, while the Friday, May 1, 2026 official Cboe row is still pending direct CSV confirmation.
3. The required post-US-close SaaS and US-trade watch lists are now row-complete in the markdown fallback using the app’s latest May 1 close references for `DDOG`, `MDB`, `TEAM`, `NET`, `SNOW`, and the core `QQQ` / semis / Mag 7 / broad-market symbols.

## Market Snapshot

| Market | Metric | Value | Change | As Of | Source |
| --- | --- | ---: | ---: | --- | --- |
| US | S&P 500 | 7,230.12 | +21.11 / +0.29% | 2026-05-01 last-close | AP |
| US | 2Y Treasury yield | 3.88% | unchanged vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | 10Y Treasury yield | 4.39% | -1 bp vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | 30Y Treasury yield | 4.97% | -1 bp vs 2026-04-30 | 2026-05-01 official close | U.S. Treasury |
| US | VIX | 16.89 latest verifiable official close; 2026-05-01 pending official Cboe refresh | -1.92 / -10.21% vs 2026-04-29 on latest official close chain | 2026-04-30 official close / 2026-05-01 pending | Cboe via FRED source chain; direct Cboe CSV still pending |
| HK / China | Hang Seng | 25,776.53 | market_closed on 2026-05-01 and 2026-05-02; carry 2026-04-30 close | 2026-04-30 last-close | Xinhua |
| HK / China | Shanghai Composite | 4,112.16 | market_closed on 2026-05-01 and 2026-05-02; carry 2026-04-30 close | 2026-04-30 last-close | Xinhua |
| Japan | Nikkei 225 | 59,513.12 | +228.20 / +0.38% | 2026-05-01 close | Xinhua |
| Japan | 10Y JGB yield | above 2.5% | delayed; still near multi-decade highs | 2026-05-01 Asia session | Trading Economics |
| Europe | STOXX Europe 600 | market_closed for May Day; prior verified close carried | no fresh May 1 continental cash close | 2026-05-01 market_closed | calendar / prior verified row |
| Europe | Euro Stoxx 50 | market_closed for May Day; prior verified close carried | no fresh May 1 euro-area cash close | 2026-05-01 market_closed | calendar / prior verified row |
| Europe | Germany 10Y Bund | above 3.0% | elevated near multi-year highs | 2026-05-01 Europe session / carried into weekend | Trading Economics |
| Europe | UK 10Y Gilt | just above 5.0% | stabilized near 18-year highs | 2026-05-01 Europe session | Trading Economics |
| FX | EUR/USD | 1.1702 | +0.0022 vs 2026-04-28 ECB reference 1.1680 | 2026-04-30 official ECB reference / weekend carry | ECB |
| Commodity / Crypto | BTC | 78,178.28 | +2.43% | 2026-05-01 09:15 ET | Fortune |
| Commodity / Crypto | ETH | 2,308.85 | +1.93% | 2026-05-01 09:15 ET | Fortune |
| Commodity / Crypto | Brent | 108.17 | -2.23 / -2.02% settle | 2026-05-01 settle | Reuters |
| Commodity / Crypto | WTI | 101.94 | -3.13 / -2.98% settle | 2026-05-01 settle | Reuters |
| Commodity / Crypto | Gold | 4,592 | -1.08% | 2026-05-01 08:55 ET | Fortune |
| Commodity / Crypto | Silver | 74.73 | +1.34% | 2026-05-01 08:45 ET | Fortune |

## Trade Thesis Watch List Refresh

Rule used here: because this is a US-close backfill for the Friday, May 1, 2026 US session, all US-listed required rows are written against the May 1 US market date where the current note or app state had a reliable close. HK / China rows remain on their last valid April 30 or April 29 market-session dates because May 1 was a holiday and May 2 was a Saturday. Europe carry rows and unresolved symbols remain visible on prior verified values instead of being blanked out.

### 2026 Q1 SaaS overshoot

| Symbol | Monitor Date | Result Date | T+1 | T+2 | T+3 | Today Price | Change / State | High / Low Reference |
| --- | --- | --- | --- | --- | --- | ---: | --- | --- |
| DDOG | 2026-05-01 | 2026-05-07 BMO | Pending | Pending | Pending | $140.53 | +6.31% | 52H $201.69 / 52W low $98.01 |
| MDB | 2026-05-01 | Est. 2026-06-03 | Pending | Pending | Pending | $263.46 | +5.04% | 52H $444.72 / 52W low $169.26 |
| TEAM | 2026-05-01 | 2026-04-30 AMC | $88.88 +29.58% | Pending May 4 | Pending May 5 | $88.88 | +29.58% | 52H $232.36 / 52W low $56.01 |
| NET | 2026-05-01 | 2026-05-07 AMC | Pending | Pending | Pending | $217.50 | +6.11% | 52H $260.00 / 52W low $120.46 |
| SNOW | 2026-05-01 | Est. 2026-05-27 | Pending | Pending | Pending | $141.00 | +3.32% | 52H $280.67 / 52W low $118.30 |

### 2026 Q1 US Trade required list

| Symbol | Monitor Date | Result Date | Today Price | Change / State | High / Low Reference |
| --- | --- | --- | ---: | --- | --- |
| QQQ | 2026-05-01 | Apple / AMD window | $674.13 | +1.0%; no index fade | prior session H/L ref $668.90 / $657.56 |
| SMH | 2026-05-01 | AMD T+1/T+2 | $509.70 | +0.6%; semis stayed bid | prior session H/L ref $507.79 / $495.02 |
| SPY | 2026-05-01 | Broad fade check | $720.75 | +0.3%; broad market held | prior session H/L ref $719.79 / $710.45 |
| SOXX | 2026-05-01 | AMD T+1/T+2 | $465.75 | +0.9%; close near high | prior session H/L ref $462.14 / $449.34 |
| AAPL | 2026-05-01 | 2026-04-30 AMC | May 1 close +3.3% | relief bid held | prior session H/L ref $275.94 / $268.14 |
| AMD | 2026-05-01 | 2026-05-05 AMC | May 1 close +1.7% | primary add trigger still pending the print | prior session H/L ref $354.95 / $332.64 |
| NVDA | 2026-05-01 | 2026-05-20 est. | May 1 close -0.6% | below 200; isolated weakness | prior session H/L ref $210.30 / $198.70 |
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

### HK/China Tech AI and HK/China High Yield carry rows

| Trade | Symbol Set | Latest Market Session | State |
| --- | --- | --- | --- |
| HK/China Tech AI | `0700 HK`, `002230 CN`, `0981 HK`, `688256 CN`, `600584 CN`, `002156 CN`, `002185 CN`, `USD/CNH` | 2026-04-29 to 2026-04-30 depending on venue | prior verified rows kept because Friday was a holiday and Saturday was not a trading day |
| HK/China High Yield - banks | `0005 HK`, `2388 HK`, `2888 HK`, `1398 HK`, `0939 HK`, `1288 HK`, `3988 HK` | 2026-04-30 | prior verified rows kept; next live refresh belongs to the next HK close |
| HK/China High Yield - dividends | `0941 HK`, `0728 HK`, `0883 HK`, `1088 HK`, `0002 HK`, `0006 HK`, `6823 HK`, `1044 HK`, `1378 HK` | 2026-04-30 | prior verified rows kept; no table-wide stale reset |

### 2026 Global AI Infrastructure required list

| Symbol | Monitor Date | Today Price | Change / State | High / Low Reference |
| --- | --- | ---: | --- | --- |
| URI | 2026-04-22 | $959.84 | Apr30 close carried; no clean May 1 refresh retrieved in this pass | session H/L $959.84 / $945.66 |
| HRI | 2026-04-30 | $126.92 | Apr30 close carried | session H/L $126.92 / $124.17 |
| FCX | 2026-04-28 | $58.21 | prior verified row kept | 52H $70.97 / 52W low $34.45 |
| SCCO | 2026-04-30 | $171.69 | Apr30 close carried | 52H $218.85 / 52W low $84.13 |
| 2899 HK | 2026-04-29 | HK$36.38 | +2.88%; prior verified HK row kept | 52H HK$46.98 / 52W low HK$16.70 |
| GEV | 2026-04-30 | $1,083.46 | Apr30 close carried | session H/L $1,094.00 / $1,066.61 |
| NEE | 2026-04-30 | $97.88 | Apr30 close carried | session H/L $98.03 / $94.44 |
| DUK | 2026-04-30 | $129.55 | Apr30 close carried | session H/L $129.84 / $126.11 |
| VST | 2026-04-30 | $157.84 | Apr30 close carried | session H/L $159.63 / $155.73 |
| ETN | 2026-04-27 | $416.77 | prior verified row kept | 52H $432.34 / 52W low $283.00 |
| SU FP | 2026-04-30 | EUR266.95 | prior verified Europe row kept | 52H EUR281.50 / 52W low EUR199.30 |
| ENR GR | 2026-04-28 | EUR172.98 | prior verified Europe row kept | 52H EUR191.66 / 52W low EUR65.56 |
| 6501 JP | 2026-05-01 | JPY4,815 | -5.01% | 52H JPY6,039 / 52W low JPY2,590 |
| VRT | 2026-04-27 | $322.43 | prior verified row kept | 52H $330.30 / 52W low $80.51 |
| JCI | 2026-04-28 | $141.59 | prior verified row kept | 52H $146.49 / 52W low $80.19 |
| TT | 2026-04-28 | $425.47 | prior verified row kept | 52H $471.46 / 52W low $346.45 |
| ANET | 2026-04-30 | $172.71 | Apr30 close carried | session H/L $173.58 / $167.76 |
| CSCO | 2026-04-30 | $91.47 | Apr30 close carried | session H/L $91.67 / $89.32 |
| CIEN | 2026-04-30 | $527.58 | Apr30 close carried | session H/L $529.89 / $486.25 |
| 0763 HK | 2026-04-30 | HK$24.94 | Apr30 close carried | session H/L HK$25.20 / HK$24.22 |

## Watch-List Refresh Summary

- `2026 Q1 SaaS overshoot` is fully refreshed to the Friday, May 1, 2026 US-close session across `DDOG`, `MDB`, `TEAM`, `NET`, and `SNOW`.
- `2026 Q1 US Trade` required symbols are refreshed to the May 1 close state using the latest in-app theme rows; the read-through is still "no clean pop-and-fade confirmation yet."
- `2026 Japan Trade` keeps the latest valid April 30 carry rows for the expression instruments while the broader Japan macro read uses the May 1 Nikkei close and elevated JGB signal.
- `HK/China Tech AI` and `HK/China High Yield` correctly remain on prior verified HK / mainland session dates because the relevant markets were closed on May 1 and May 2.
- `2026 Global AI Infrastructure` remains mixed: `6501 JP` uses the May 1 Japan close, several U.S. and Europe rows carry verified April 27 to April 30 values, and any symbol without a clean newer source kept its prior row rather than reverting to `Needs refresh`.

## US Snapshot

- Friday, May 1, 2026 still extended the hold-near-highs regime. AP reported the S&P 500 closing at `7,230.12`, up `0.29%`, while the Nasdaq finished at a fresh record `25,114.44`, up `0.89%`.
- Treasury yields eased modestly again. Treasury’s published curve showed `2Y 3.88%`, `10Y 4.39%`, and `30Y 4.97%`, leaving the U.S. curve less stressed than late April but still restrictive rather than easy.
- Oil helped rather than hurt on the day. Reuters’ Friday wrap pointed to Brent settling at `108.17` and WTI at `101.94`, a meaningful retreat from the prior day’s panic spike.
- Breadth still looks less convincing than the headline records. The equal-weight and financial/payment reads in the US Trade tab remain weaker than the QQQ / Mag 7 headline tape, so the market is holding but not broadening cleanly.
- VIX is populated per runbook and not invented. The latest verifiable official Cboe-source close available in this environment is `16.89` for Thursday, April 30, 2026, while Friday, May 1 remains marked `pending official Cboe refresh`.

## HK / China Snapshot

- No fresh Hong Kong or mainland China cash session existed for this backfill. Friday, May 1 was a holiday and Saturday, May 2 was not a trading day, so the correct carried session is Thursday, April 30, 2026.
- That leaves the China beta read unchanged from the prior heartbeat: no fresh breakdown, but also no fresh post-holiday upside confirmation.
- `USD/CNH`, `USDHKD`, and `HIBOR` still need a cleaner source pass before the next HK close heartbeat.

## Japan Snapshot

- Japan remains the main spillover channel into the next Asia open. The Nikkei 225 closed Friday, May 1, 2026 at `59,513.12`, up `0.38%`, but the rates signal remains more important than the equity index level.
- Delayed bond coverage still shows the `10Y JGB` above `2.5%`, which keeps the BOJ / carry / valuation stress channel active even without a fresh equity breakdown.
- Tokyo CPI also weakened the easy-dovish read. Reuters reported Tokyo April core CPI at `1.5% y/y`, below the `1.8%` median estimate, but the BOJ’s own risk scenario still sees inflation around `3%` if oil and yen weakness persist.

## Europe Snapshot

- Continental Europe was effectively a May Day `market_closed` carry for this window, so the useful Europe signal remains rates rather than fresh equity closes.
- Germany’s 10Y Bund stayed above `3%`, and the UK 10Y gilt remained just above `5%`, which says the global duration regime still has pressure even after Friday’s softer U.S. close.
- Europe therefore remains neutral-to-slightly-unhelpful for the June-risk thesis: it is not adding new stress, but it is not delivering a clean global rates relief signal either.

## Commodity / Crypto Snapshot

- Oil’s retreat remains the cleanest cross-asset relief factor in the May 1 U.S. close. Brent at `108.17` and WTI at `101.94` matter because they reduced immediate stagflation pressure without fully removing the energy-risk tail.
- Crypto bounced with the risk tape instead of leading it. BTC at `78,178.28` and ETH at `2,308.85` improved tone but do not yet amount to a new speculative-liquidity impulse.
- Gold and silver stayed elevated enough to say macro hedging demand still exists. That supports a "better near term, still fragile into June" interpretation rather than a full all-clear.

## Scorecard

| Signal | Status | Note | Next Catalyst |
| --- | --- | --- | --- |
| US Liquidity | Supportive | Another record S&P / Nasdaq close preserved the hold-near-highs regime. | Treasury refunding May 4-6; payrolls May 8 |
| Rates And Curve | Mixed | U.S. yields eased, but JGBs, bunds, and gilts still keep the global rates channel restrictive. | Treasury refunding; CPI May 12 |
| Credit Stress | Watch | Clean MOVE and same-session HY / IG spread refreshes are still incomplete. | Rates-vol and credit-spread refresh |
| Consumer And Labor | Mixed | Softer oil helps, but the market still needs orderly labor cooling rather than a break. | Payrolls May 8; CPI May 12 |
| Earnings And Breadth | Supportive | Index highs held, but breadth still lags headline tech strength. | Nvidia May 20; AMD May 5 |
| China Credit Impulse | Watch | No new China cash session was available in this backfill. | China CPI/PPI May 11; reopen flow |
| FX And Property Stress | Watch | CNH, HKD, and HK liquidity still need a cleaner same-session pass. | USD/CNH; USDHKD; HIBOR |
| BOJ And JGB | Stress | Japan’s rates channel remains the clearest unresolved macro stress point. | BOJ Summary May 12; BOJ June 15-16 |
| JPY Carry Stress | Stress | Elevated JGB yields still keep the yen / carry unwind risk active. | USD/JPY and JGB follow-through |
| Crypto Liquidity | Mixed | Crypto improved with risk appetite, but it is not leading. | ETF flow and cross-asset follow-through |
| Oil And Metals | Watch | Oil backed off, but precious metals still signal persistent macro hedging demand. | Treasury refunding; CPI; Middle East headlines |

## Thesis Check

Confirming:

- The market can still hold near all-time highs into Nvidia, and Friday’s close continued that pattern.
- Japan still validates the BOJ / JGB / carry-stress side of the June-risk thesis.
- AI leadership remains crowded enough that one failed post-earnings hold could still matter disproportionately.

Weakening:

- Oil’s Friday retreat lowered the odds of an immediate stagflation-style de-risking wave.
- Big-cap tech still absorbed good earnings rather than selling them hard enough to validate the US pop-and-fade short setup.

## Forecast Updates

| Event | Date | Consensus / Expected | Prior | Market-Implied / Probability | Base Case | Upside / Bull Case | Downside / Bear Case | Markets Most Exposed | Confirm / Invalidate | Source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Treasury quarterly refunding financing estimates | 2026-05-04 | scheduled; no major coupon shock expected | Feb. 2, 2026 financing estimates | term premium remains elevated | Heavy but manageable borrowing need | Stable financing estimate lets the 10Y keep easing | Larger-than-feared borrowing need lifts long-end yields again | 10Y / 30Y UST, duration equities, USD | Confirmed by calm long-end reaction; invalidated by a fresh term-premium jump | U.S. Treasury |
| ISM services and JOLTS follow-through | 2026-05-05 | labor and activity should cool without cracking | last labor print +178K payrolls, unemployment 4.3% | market wants slower but still positive demand | Softer but still stable labor / activity mix | Cooling activity eases rate pressure | Sticky demand or inflation-sensitive activity re-tightens policy fears | Front end, small caps, cyclicals | Confirmed by orderly cooling; invalidated by reacceleration or a hard break | BLS / ISM |
| Treasury quarterly refunding announcement | 2026-05-06 | coupon sizes broadly expected steady | Feb. 4, 2026 statement | long-end remains the key macro valve | No duration surprise | Stable sizing helps equities absorb oil and inflation noise | Heavier duration load re-tightens financial conditions | Long bonds, REITs, growth stocks | Confirmed by steady coupon mix; invalidated by heavier long-end issuance | U.S. Treasury |
| Datadog and Cloudflare earnings | 2026-05-07 | key SaaS watch window | TEAM T+1 already passed | market is now testing whether good SaaS numbers are still paid for | At least one clean reward signal keeps the SaaS overshoot trade alive | Beat-and-hold broadens the SaaS rebound beyond TEAM | Beat-but-fade would damage the overshoot thesis quickly | DDOG, NET, IGV, software beta | Confirmed by strong T+1/T+2 holds; invalidated by good numbers sold on impact | company IR calendars |
| U.S. payrolls, April | 2026-05-08 | broad market preference is slower-but-positive; one preview points to about 90K with unemployment 4.2% and AHE +0.3% m/m | Mar. payrolls +178K; unemployment 4.3% | market wants cooling without contraction | Around-trend cooling, not a break | Payrolls slow with stable unemployment and softer wages | Hot jobs revive higher-for-longer; weak jobs revive hard-landing fear | Front end, USD, small caps, cyclicals | Confirmed by orderly cooling; invalidated by reacceleration or labor crack | BLS; Continuum preview |
| Fed-chair transition / Warsh full Senate vote window | week of 2026-05-11 | Reuters says full Senate is expected to vote the week of May 11 after the 13-11 committee advance on Apr. 29 | committee advanced nomination on 2026-04-29 | policy-independence risk remains a live premium | Process advances without immediate repricing shock | Confirmation is orderly and independence concerns cool | Confirmation turns into a louder fight over Fed independence | USTs, USD, banks, long-duration tech | Confirmed by calm rhetoric and pricing; invalidated by Senate conflict or policy signaling shock | Reuters |
| China CPI / PPI, April | 2026-05-11 | prior Reuters baseline was CPI around 1.0% and PPI around 0.5% y/y in the March print regime; updated exact consensus still needs refresh | Mar. CPI 1.0% y/y; Mar. PPI 0.5% y/y | no clean market-implied pricing source available | Benign CPI with still-firm producer inflation | Better domestic-demand mix helps CNH, HSI, and cyclicals | Softer CPI and PPI revive China-lag concerns | HSI, CNH, industrial metals | Confirmed by steady core and still-positive producer prices; invalidated by broader disinflation | NBS; Reuters |
| BOJ Summary of Opinions | 2026-05-12 | qualitative release | Apr. 27-28 BOJ hold at 0.75% | market is listening for how close the BOJ is to another hike | Still gradual tightening bias without a near-term move | Tone is less urgent and JGB pressure eases | Tone validates faster normalization and pushes JGBs / JPY higher | JGBs, JPY, Nikkei carry trades | Confirmed by measured language; invalidated by stronger inflation / FX urgency | BOJ |
| U.S. CPI, April | 2026-05-12 | exact consensus still needs a cleaner source refresh; market focus is core services and energy pass-through | Mar. CPI 3.3% y/y; core 2.6% y/y | energy pass-through keeps upside risk live | Headline firm; core only slowly easing | Core services soften enough to keep June FOMC balanced | Headline and core both re-accelerate | USTs, USD, Nasdaq, gold | Confirmed by softer core services; invalidated by broad inflation stickiness | BLS |
| Nvidia Q1 FY2027 earnings | 2026-05-20 | company reports after the close; prior quarter revenue $68.1B and Q1 guide $78.0B +/- 2% | Q4 FY2026 revenue $68.1B | positioning remains crowded | Beat-and-maintain is enough to keep the tape together | Beat-and-raise broadens leadership and extends the hold-near-highs thesis | Guide wobble or softer AI demand commentary hits crowded positioning hard | Nasdaq, SOX, S&P breadth | Confirmed by strong data-center demand and guide confidence; invalidated by growth or margin wobble | Nvidia IR |
| Japan CPI, April | 2026-05-22 | Tokyo April core CPI already printed 1.5% y/y versus 1.8% expected; national April consensus still needs refresh | Mar. nationwide core CPI 1.8% y/y | JGB market sensitivity remains high | Sticky-enough inflation keeps BOJ normalization alive but gradual | Softer CPI cools JGB pressure and carry stress | Hot CPI validates another BOJ step sooner | JGBs, JPY, Nikkei | Confirmed by contained services and core; invalidated by hotter underlying inflation | Reuters; Statistics Bureau of Japan |
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
| Base case | 60% | Full Senate confirms Warsh on time or close enough that transition stays orderly | Mild policy-premium stays in long-end yields |
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
- 2026-05-05: ISM services and JOLTS follow-through.
- 2026-05-06: U.S. Treasury quarterly refunding announcement.
- 2026-05-07: DDOG and NET earnings.
- 2026-05-08: U.S. payrolls for April.
- 2026-05-11: China CPI / PPI for April; Warsh full Senate vote window.
- 2026-05-12: BOJ Summary of Opinions; U.S. CPI for April.

## Follow-Up Tasks

- Expose durable storage for `nj_agent_heartbeat_run`, `nj_agent_backfill_task`, and `nj_finance_macro_event`; the active local SQLite file remains empty.
- Backfill every required market snapshot line from `2026-01-01` forward once durable storage exists.
- Keep `2026-05-01` VIX marked pending official Cboe refresh until the direct `VIX_History.csv` row is fetchable.
- Refresh clean same-session May 1 close rows for the carried U.S. global-infrastructure names that still rely on April 27 to April 30 values.
- Refresh exact same-session rows for `USD/CNH`, `USDHKD`, `HIBOR`, MOVE, and clean US HY / IG spread prints.
- Refresh exact consensus values for April payrolls, April CPI, April China CPI/PPI, and April Japan CPI before the next pre-event heartbeat.

## Backfill Status

- No durable `nj_agent_heartbeat_run` history was available because the active local database file is still empty, so missed-window detection still could not be computed from stored rows.
- No durable `nj_agent_backfill_task` rows could be created for the same reason.
- Visible markdown fallback history shows a gap after `Investment Macro Daily Refresh - 2026-05-02 Asia Close.md`: there was no `2026-05-02` US-close note for the Friday, May 1, 2026 session.
- This file backfills that missed window and should be treated as the coverage note for the original `2026-05-02 05:30 Asia/Shanghai` US-close heartbeat.
- Markdown-tracked pending backfills remain:
- `pending`: heartbeat history bootstrap for missed Asia-close and US-close windows from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: market snapshot historical backfill for required lines from `2026-01-01` forward, reason `automation_not_run`.
- `pending`: direct official Cboe CSV verification for the `2026-05-01` VIX close, reason `official_source_not_yet_updated`.

## Source Links

- Prior Asia close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-02 Asia Close.md`
- Prior US close note: `/Users/mac/Developer/Notion Journal/Notion Journal/Docs/Investment Macro Daily Notes/Investment Macro Daily Refresh - 2026-05-01.md`
- AP Friday, May 1, 2026 U.S. close recap: https://apnews.com/article/ee0fd67a1f14608ef46165f6dd693592
- U.S. Treasury daily par yield curve rates: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?field_tdr_date_value=2026&type=daily_treasury_yield_curve
- Cboe VIX historical-data page: https://www.cboe.com/tradable_products/vix/vix_historical_data
- FRED VIX series sourced from Cboe: https://fred.stlouisfed.org/series/VIXCLS
- SPX Stats page carrying FRED-backed VIX close context: https://www.spxstats.com/
- Xinhua Friday, May 1, 2026 Tokyo close: https://english.news.cn/20260501/d15a30912bd14c5ba9ee46e8407847ea/c.html
- Xinhua Thursday, April 30, 2026 Hong Kong close: https://english.news.cn/20260430/09d4d449accf4b08b3ec4b08e960a73f/c.html
- Xinhua Thursday, April 30, 2026 Shanghai close: https://english.news.cn/20260430/84661e27316e44e58a2c09c1d4b33cbc/c.html
- ECB euro reference rates: https://www.ecb.europa.eu/stats/exchange/eurofxref/html/index.en.html
- Reuters oil settlement wrap for Friday, May 1, 2026 via MarketScreener: https://ca.marketscreener.com/news/oil-rises-over-1-with-no-sign-of-iran-conflict-ending-ce7f58d9d989fe2d
- Fortune BTC price for May 1, 2026: https://fortune.com/article/price-of-bitcoin-05-01-2026/
- Fortune ETH price for May 1, 2026: https://fortune.com/article/price-of-ethereum-05-01-2026/
- Fortune gold price for May 1, 2026: https://fortune.com/article/current-price-of-gold-05-01-2026/
- Fortune silver price for May 1, 2026: https://fortune.com/article/current-price-of-silver-5-1-2026/
- U.S. Treasury quarterly refunding documents: https://home.treasury.gov/policy-issues/financing-the-government/quarterly-refunding/most-recent-quarterly-refunding-documents
- Reuters on Warsh committee advance and expected full-Senate vote week of May 11: https://www.marketscreener.com/news/fed-chief-nominee-warsh-set-to-clear-key-hurdle-toward-senate-confirmation-vote-ce7f59d3de8df522
- Reuters Tokyo April core CPI report: https://www.investing.com/news/economic-indicators/tokyo-april-core-cpi-rises-15-yryr-4651777
- BOJ meeting schedule: https://www.boj.or.jp/en/mopo/mpmsche_minu/
- BOJ release calendar: https://www.boj.or.jp/en/about/calendar/
- Statistics Bureau of Japan CPI release schedule: https://www.stat.go.jp/english/data/cpi/1582.html
- China March CPI official release: https://www.stats.gov.cn/english/PressRelease/202604/t20260413_1963288.html
- China March PPI official release: https://www.stats.gov.cn/english/PressRelease/202604/t20260413_1963289.html
- Reuters China PMI preview: https://www.investing.com/news/economic-indicators/chinas-factory-activity-set-to-expand-at-a-slower-clip-in-april-reuters-poll-4643455
- NVIDIA Q1 FY2027 earnings date: https://investor.nvidia.com/news/press-release-details/2026/NVIDIA-Sets-Conference-Call-for-First-Quarter-Financial-Results/default.aspx
