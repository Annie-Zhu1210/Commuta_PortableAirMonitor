# Commuta Hero Score

The Home screen's centrepiece — a single number, 0–100 (higher is cleaner), plus a plain-English descriptor. It condenses a live sensor reading into an at-a-glance answer to "how bad is the air right now?".

<p align="center">
  <em>Score 51, "Good" (sage) → 46, "Moderate Pollution" (amber) → 0, "Severe Pollution" (deep red)</em>
</p>

## The idea

Rather than averaging or weighting pollutants — a choice that would need literature-sourced weights we don't have — Commuta uses **worst-metric-drives-the-score**. Whichever pollutant is furthest into its own pollution scale sets the overall band. This is the same principle behind the UK DAQI and the US EPA AQI: take the max sub-index, not the average.

## The formula

For each pollutant *p* with live reading *v* and its "Very High" starting boundary *a*:

```
score_p = 100 × max(0, 1 − v / a)
```

Higher pollution → smaller ratio → lower score. The overall Hero Score is:

```
Hero Score = min across available metrics of score_p
```

## Anchors

The "Very High" boundary is the value at which each metric's contribution drops to zero.

| Metric      | Very-High start (score = 0) | Reference                     |
|-------------|-----------------------------|-------------------------------|
| PM2.5       | 70 µg/m³                    | DEFRA DAQI                    |
| PM10        | 100 µg/m³                   | DEFRA DAQI                    |
| CO₂         | 1500 ppm                    | Indoor ventilation guidance   |
| NOx index   | 300                         | Sensirion SGP41               |
| VOC index   | 400                         | Sensirion SGP41               |

## Score → descriptor

The descriptor and colour come from the DAQI band of the worst-scoring metric, keeping the hero card visually consistent with the metric grid below it.

| Worst-metric band | Descriptor          | Colour        |
|-------------------|---------------------|---------------|
| Low               | Good                | Sage green    |
| Moderate          | Moderate Pollution  | Amber         |
| High              | High Pollution      | Coral         |
| Very High         | Severe Pollution    | Deep coral-red|

## Worked examples

The three screenshots at the top were captured during real device testing.

**Ambient office air.** PM2.5 = 9.6, PM10 = 9.6, CO₂ = 742 ppm. Per-metric scores: 86, 90, 51. CO₂'s 51 wins the min, and CO₂ at 742 ppm sits in the Low ("Good ventilation") band. Hero: **51, "Good"**, sage green.

**Someone exhales toward the device.** CO₂ climbs to 803 ppm. Score = 100 × (1 − 803 / 1500) = 46. CO₂ has crossed 800 into the Moderate band ("Adequate ventilation"). Hero: **46, "Moderate Pollution"**, amber.

**A vape puff.** PM2.5 spikes to 4153 µg/m³. Its score is 100 × (1 − 4153 / 70) = far below zero and clamps to **0**. PM2.5's band is now Very High. Hero flips instantly to **0, "Severe Pollution"**, deep red.

|  |  |  |
|---|---|---|
| <img src="herocard_green.PNG" width="200"> | <img src="herocard_yellow.PNG" width="200"> | <img src="herocard_red.PNG" width="200"> |

## Excluded from the score

- **PM1** — no official DAQI band exists for it. It's still shown in the metric grid but doesn't participate in scoring.
- **NOx and VOC indices** — dropped from the calculation while the SGP41 sensor is conditioning (roughly the first minute after power-on). The remaining PM and CO₂ metrics still drive the score during that window.

## Why not a weighted sum?

A weighted sum (`a·PM2.5 + b·PM10 + …`) is the obvious alternative but runs into three problems: the metrics have different units (µg/m³, ppm, dimensionless indices), the weights would need commuter-exposure literature that isn't readily available, and one severely elevated pollutant can be masked by clean readings on the others. The worst-metric approach sidesteps all three, and matches how established outdoor AQIs actually work.

Swapping to a weighted-sum formula later is a single-function replacement in [`hero_score_service.dart`](../commuta_app/lib/services/hero_score_service.dart) — the widget doesn't care where the number comes from.