# Commuta Hero Score

The Home screen's centrepiece — a single number, 0–100 (higher is cleaner), plus a plain-English descriptor. It condenses a live sensor reading into an at-a-glance answer to "how bad is the air right now?".

## The idea

Rather than averaging or weighting pollutants — a choice that would need literature-sourced weights we don't have — Commuta uses **worst-metric-drives-the-score**. Whichever pollutant is furthest into its own pollution scale sets the overall band. This is the same principle behind the UK DAQI and the US EPA AQI: take the max sub-index, not the average.

Each metric's sub-score is aligned with its DAQI band structure so the overall descriptor stays consistent with what any single metric would say in isolation: a metric in its DAQI "Low" band always produces a "Good" contribution, a metric in "Moderate" always produces a "Moderate Pollution" contribution, and so on.

## The formula

For each metric with DAQI band boundaries `vLow`, `vMod`, `vHigh` (upper bounds of the Low, Moderate and High bands respectively), the sub-score is a piecewise-linear map:

```
value ≤ 0        → score = 100
value ≤ vLow     → score = 100 − 25 × (value / vLow)              // 75–100  (Good)
value ≤ vMod     → score = 75  − 25 × (value − vLow) / (vMod − vLow)  // 50–75   (Moderate Pollution)
value ≤ vHigh    → score = 50  − 25 × (value − vMod) / (vHigh − vMod) // 25–50   (High Pollution)
value > vHigh    → score = 25  − 25 × (value − vHigh) / (vHigh − vMod), clamped to [0, 25]  // Severe Pollution
```

The overall Hero Score is the minimum across all available sub-scores, floored to the nearest integer:

```
Hero Score = floor(min across available metrics of sub-score)
```

Flooring rather than rounding matters at band boundaries: a metric that has just crossed into a worse DAQI band should read as the worse-band descriptor. For example, PM2.5 at 53.2 µg/m³ sits 0.2 µg/m³ into the High band and produces a raw sub-score of 49.7. Rounding to 50 would flip the descriptor back to "Moderate Pollution"; flooring to 49 keeps it aligned with the actual DAQI band as "High Pollution".

Descriptor cutoffs land exactly at the band boundaries:

| Score      | Descriptor           |
|------------|----------------------|
| 75–100     | Good                 |
| 50–74      | Moderate Pollution   |
| 25–49      | High Pollution       |
| 0–24       | Severe Pollution     |

## Band boundaries

| Metric | Low band top | Moderate top | High top | Reference |
|---|---|---|---|---|
| PM2.5 | 35 µg/m³ | 53 µg/m³ | 70 µg/m³ | DEFRA DAQI |
| PM10 | 50 µg/m³ | 75 µg/m³ | 100 µg/m³ | DEFRA DAQI |
| CO₂ | 800 ppm | 1500 ppm | — | Indoor ventilation guidance |
| NOx index | 30 | 150 | 300 | Sensirion SGP41 |
| VOC index | 150 | 250 | 400 | Sensirion SGP41 |

CO₂ has only three DAQI bands (Good ventilation, Adequate, Poor). Its sub-score therefore floors at 25 — CO₂ alone can never push the card into "Severe Pollution".

## Worked examples

All three examples use real device readings.

**Ambient office air.** PM2.5 = 7.6, PM10 = 7.6, CO₂ = 525 ppm, NOx = 1, VOC = 100. Sub-scores work out to 95, 96, 84, 99 and 83 respectively; VOC's 83 is the minimum. Hero: **83, "Good"**, sage green.

**Poor ventilation.** Same PM and SGP41 values, but CO₂ climbs to 1000 ppm — now in the Adequate band. CO₂'s sub-score drops to `75 − 25 × (200 / 700) ≈ 68`, which is now the minimum. Hero: **68, "Moderate Pollution"**, olive-yellow.

**A vape puff.** PM2.5 spikes to 4153 µg/m³ — deep into Very High territory. Its sub-score is `25 − 25 × (4083 / 17)`, which is far below zero and clamps to **0**. Hero: **0, "Severe Pollution"**, deep coral-red.

## Visualising the score

The Home card renders the score on a 20-segment semicircular arc:

- All 20 segments take the score's own colour (one of ten palette entries, one per 10-point range).
- Leftmost `round(score / 5)` segments render at full opacity; the rest at 50%. Score 0 keeps the leftmost segment at full opacity as a "worst end" marker.
- The number and descriptor pill both use a darker shade of the same palette colour, so the whole card speaks one colour language driven purely by the score.

## Excluded from the score

- **PM1** — no official DAQI band exists for it. It's still shown in the metric grid but doesn't participate in scoring.
- **NOx and VOC indices** — dropped from the calculation while the SGP41 is conditioning (roughly the first minute after power-on). The remaining PM and CO₂ metrics still drive the score during that window.

## Why not a weighted sum?

A weighted sum (`a·PM2.5 + b·PM10 + …`) is the obvious alternative but runs into three problems: the metrics have different units (µg/m³, ppm, dimensionless indices), the weights would need commuter-exposure literature that isn't readily available, and one severely elevated pollutant can be masked by clean readings on the others. The worst-metric approach sidesteps all three, and matches how established outdoor AQIs actually work.

Swapping to a weighted-sum formula later is a single-function replacement in [`hero_score_service.dart`](../commuta_app/lib/services/hero_score_service.dart) — the widget doesn't care where the number comes from.