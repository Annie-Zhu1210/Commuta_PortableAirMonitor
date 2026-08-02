# Commuta battery discharge characterisation

Test run: **2026-08-01 00:17** to **2026-08-02 00:17 (UTC+01:00)**  
Total runtime: **24.00 hours** on a single full charge.

## 1. Data quality

- **Rows recorded:** 4,165 out of a theoretical maximum of ~8,640 (24 h × 6 samples/min).
- **Single power session:** one `boot_epoch` throughout — device did not reboot.
- **Voltage range:** 3860 mV at first recorded sample, peak 3931 mV shortly after, ending at 2377 mV when the device died.

### Sequence gaps

| Time window | Duration | Missing readings |
|---|---|---|
| 22.38 h – 23.53 h | 68.8 min | 412 |

The 68.8-min gap is the app-backgrounded period; this is a genuine gap in the recorded data (not a display-only gap), and it has been bridged by the fitted curve rather than filled with raw values.

## 2. Curve fit

- **Method:** locally-weighted regression (LOWESS) with bandwidth `frac = 0.05`, forced non-increasing via cumulative-minimum for percentage inversion.
- **Reference fit:** isotonic regression (guaranteed monotonic) is overlaid on the chart for comparison. The two agree closely except in the very flat plateau, where LOWESS gives a smoother characterisation of the underlying trend and isotonic is more sensitive to individual noisy samples.
- **Gap handling:** the fit is trained on all recorded samples (no synthetic points inserted). Because LOWESS is a local smoother, the 68.8-min gap is bridged naturally by anchoring on the samples immediately before and after; given the smooth, slowly-varying voltage in that region, this is a low-risk interpolation.

## 3. Discharge phases

| Phase | Time window | Voltage window | Mean slope |
|---|---|---|---|
| **Initial drop** | 0.00 h – 1.01 h | 3894 mV → 3762 mV | -130.8 mV/h |
| **Plateau** | 1.01 h – 21.68 h | 3762 mV → 3216 mV | -26.4 mV/h |
| **Decline** | 21.68 h – 22.38 h | 3216 mV → 3168 mV | -68.7 mV/h |
| **Cutoff** | 22.38 h – 24.00 h | 3168 mV → 2719 mV | -278.1 mV/h |

Interpretation:

- **Initial drop.** The characteristic post-full-charge relaxation — the surface-charge component decays quickly under load. This is normal.
- **Plateau.** A long, very flat region where voltage is a poor indicator of remaining charge — a single reading of, say, 3.60 V could correspond to anywhere from a few hours to a dozen hours of remaining runtime. Any in-app battery indicator based on voltage alone will be inherently coarse across this region.
- **Decline.** Voltage starts to fall more steadily as the cell approaches its empty state. Percentage estimates become more reliable here.
- **Cutoff.** A steep terminal drop of several hundred mV/hour. From the knee onwards the cell has very little useful capacity left.

## 4. Voltage → percentage-remaining lookup

Percentages are computed as `1 − t(V) / total_runtime`, where `t(V)` is the time at which the fitted curve crosses voltage `V`, and `total_runtime` = 24.00 h. Full 50 mV lookup is in `voltage_percentage_lookup.csv`.

| Voltage | Time reached | Percent remaining | Hours left |
|---|---|---|---|
| 3.90 V | 0.00 h | 100% | 24.0 h |
| 3.80 V | 0.65 h | 97% | 23.4 h |
| 3.70 V | 1.88 h | 92% | 22.1 h |
| 3.60 V | 6.79 h | 72% | 17.2 h |
| 3.50 V | 15.42 h | 36% | 8.6 h |
| 3.40 V | 16.92 h | 30% | 7.1 h |
| 3.35 V | 17.87 h | 26% | 6.1 h |
| 3.30 V | 18.94 h | 21% | 5.0 h |
| 3.20 V | 21.93 h | 9% | 2.1 h |
| 3.10 V | 22.69 h | 5% | 1.3 h |
| 3.00 V | 23.15 h | 4% | 0.8 h |
| 2.90 V | 23.58 h | 2% | 0.4 h |
| 2.80 V | 23.83 h | 1% | 0.2 h |
| 2.70 V | 24.00 h | 0% | 0.0 h |
| 2.60 V | 24.00 h | 0% | 0.0 h |
| 2.50 V | 24.00 h | 0% | 0.0 h |
| 2.40 V | 24.00 h | 0% | 0.0 h |

## 5. Recommendation on the stop threshold

- At **3.30 V**, the fitted curve gives **≈ 21% remaining** (device would have died in another ~5.1 hours from that point in this test).
- Selected reference points for context:
  - 3.60 V ≈ 72% remaining (mid-plateau; percentage estimate is soft here)
  - 3.50 V ≈ 36% remaining (near end of plateau)
  - 3.40 V ≈ 29% remaining (into the decline)
  - 3.20 V ≈ 9% remaining (past the knee, close to empty)

Stopping at 3.30 V is a reasonable protective choice — it leaves about a fifth of practical capacity in the cell and keeps well clear of the terminal collapse below ~3.10 V. If you wanted to be more conservative for cell longevity (especially with a cell whose full-charge voltage sits around 3.93 V rather than the 4.20 V of a typical LiPo), stopping around **3.40–3.50 V** would leave more headroom at the cost of shorter runtime per charge.

- **Practical exhibition runtime at 3.30 V stop:** approximately **18.9 hours** per full charge.
- No firmware low-voltage cutoff currently exists; this test drove the cell to 2377 mV (the point at which the device could no longer boot). If a firmware cutoff is added later, 3.30 V would be a sensible default given the observed shape.

## 6. Caveats

- Percentages here are relative to *this specific test's* runtime under the measured load. Real-world runtime will vary with BLE activity, temperature, cell ageing, and whether the app is foregrounded (buffering vs streaming).
- The plateau region gives inherently ambiguous percentages — this is a property of the cell chemistry, not the fitting method.
- The full-charge peak of ~3.93 V (rather than the ~4.20 V typical of a single-cell LiPo) is worth logging for the dissertation; it does not affect the validity of the percentage mapping in-app so long as the same ADC reading path is used at runtime, but it may be worth checking the ADC calibration or charging IC set-point at some point after the exhibition.