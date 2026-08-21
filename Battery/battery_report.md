# Commuta battery discharge characterisation

Test run: **2026-08-01 00:17** to **2026-08-02 00:17 (UTC+01:00)**  
Wall-clock span: 24.00 h. **Active sampling runtime: 12.76 h** — the cell was actually under load for this long. The two periods when the device was switched off (see §1) do not count.

> **Correction notice.** An earlier version of this report used wall-clock time as the discharge axis, which included the device-off periods and produced a fake voltage plateau. This version uses sequence-based active time, which is the correct denominator for a discharge curve. All lookup values and the stop-threshold recommendation have changed as a result.

## 1. Data quality

- **Rows recorded:** 4,165.
- **Single power session:** one `boot_epoch` throughout — device did not reboot even across the off-periods (the ESP32 sequence counter is restored from NVS on power-up).
- **Voltage range:** 3860 mV at first recorded sample, peak 3931 mV shortly after, ending at 2377 mV when the device died.

### Device-off periods

The device was switched off for these intervals. The voltage was not actually flat during them — the cell was simply not being sampled. On the active-time axis these intervals collapse to zero width.

| Wall-clock start | Wall-clock end | Duration | Voltage before → after |
|---|---|---|---|
| 03:53 | 14:11 | 618.2 min | 3599 mV → 3609 mV |
| 20:34 | 21:30 | 56.3 min | 3244 mV → 3251 mV |

### Data-loss periods (device on, samples never reached CSV)

| Active-time window | Missing samples | Voltage before → after |
|---|---|---|
| 7.84 h – 7.87 h | 9 | 3341 mV → 3323 mV |
| 11.15 h – 12.29 h | 412 | 3154 mV → 3035 mV |
| 12.34 h – 12.35 h | 4 | 3016 mV → 3009 mV |

These samples are irrecoverable — the LOWESS fit bridges the window smoothly using the voltages either side, which is safe given the slowly-varying discharge in that region.

## 2. Method

- **Axis:** sequence-based active time. Each sample carries a monotonically incrementing `sequence_number` that only advances while the device is actually sampling, so `(sequence_number − first_sequence) × 10 s` gives the true elapsed runtime under load.
- **Smoother:** locally-weighted regression (LOWESS), bandwidth `frac = 0.05`. Forced non-increasing via cumulative-minimum for percentage inversion.
- **Reference:** isotonic regression (guaranteed monotonic) is overlaid on the chart as a sanity check.
- **Gap handling:** the two device-off intervals do not exist on this axis at all. The data-loss intervals are bridged by the LOWESS fit anchored on the samples either side.

## 3. Discharge phases

| Phase | Active-time window | Voltage window | Mean slope |
|---|---|---|---|
| **Initial drop** | 0.00 h – 0.30 h | 3894 mV → 3843 mV | -167.8 mV/h |
| **Gentle decline** | 0.30 h – 11.15 h | 3843 mV → 3168 mV | -62.3 mV/h |
| **Cutoff** | 11.15 h – 12.76 h | 3168 mV → 2719 mV | -277.8 mV/h |

Interpretation:

- **Initial drop.** The characteristic post-full-charge relaxation — the surface-charge component decays quickly under load.
- **Gentle decline.** The long middle where the cell empties at a steady rate. Voltage tracks state-of-charge reasonably well here — unlike the fake plateau in the earlier report, there is no true flat region in this cell's discharge.
- **Cutoff.** Steep terminal drop of several hundred mV/hour. From here the cell has very little useful capacity left.

## 4. Voltage → percentage-remaining lookup

Percentages are computed as `1 − t(V) / active_total`, where `t(V)` is the active time at which the fitted curve crosses voltage `V`, and `active_total` = 12.76 h. Full 50 mV lookup is in `voltage_percentage_lookup.csv`.

| Voltage | Active time reached | Percent remaining | Active hours left |
|---|---|---|---|
| 3.90 V | 0.00 h | 100% | 12.8 h |
| 3.80 V | 0.65 h | 95% | 12.1 h |
| 3.70 V | 1.88 h | 85% | 10.9 h |
| 3.60 V | 3.58 h | 72% | 9.2 h |
| 3.50 V | 5.12 h | 60% | 7.6 h |
| 3.40 V | 6.62 h | 48% | 6.1 h |
| 3.35 V | 7.57 h | 41% | 5.2 h |
| 3.30 V | 8.64 h | 32% | 4.1 h |
| 3.20 V | 10.70 h | 16% | 2.1 h |
| 3.10 V | 11.46 h | 10% | 1.3 h |
| 3.00 V | 11.91 h | 7% | 0.8 h |
| 2.90 V | 12.34 h | 3% | 0.4 h |
| 2.80 V | 12.59 h | 1% | 0.2 h |
| 2.70 V | 12.76 h | 0% | 0.0 h |
| 2.60 V | 12.76 h | 0% | 0.0 h |
| 2.50 V | 12.76 h | 0% | 0.0 h |
| 2.40 V | 12.76 h | 0% | 0.0 h |

## 5. Recommendation on the stop threshold

- At **3.30 V**, the fitted curve gives **≈ 32% remaining** — reached after **8.6 hours** of active use, with roughly **4.1 hours** of runtime still available before the cell would die.
- Selected reference points for context:
  - 3.60 V ≈ 72% remaining
  - 3.50 V ≈ 60% remaining
  - 3.40 V ≈ 48% remaining
  - 3.20 V ≈ 16% remaining

**Practical runtime with a 3.30 V manual stop: ~8.6 hours of active use per charge.** This is enough for a single exhibition day but not two — plan on charging the cell nightly rather than trying to stretch a charge across consecutive collection days. Stopping earlier (e.g. at 3.40 V, ≈ 48%) buys headroom for cell longevity at the cost of shorter runtime per charge.

- No firmware low-voltage cutoff currently exists; this test drove the cell to 2377 mV (the point at which the device could no longer boot).

## 6. Caveats

- Percentages here are relative to *this specific test's* active runtime under the observed load. Real-world runtime will vary with BLE activity, temperature, cell ageing, and whether the app is foregrounded (buffering vs streaming).
- **The in-app battery indicator uses the earlier (wrong) lookup table** and has not been updated. It will show systematically lower percentages than reality in the mid-voltage range (e.g. 21% displayed at 3.30 V rather than ~32%, 29% at 3.40 V rather than ~48%). This is the conservative direction — the app under-reports, prompting earlier charging — but is worth logging for completeness.
- The full-charge peak of ~3.93 V (rather than the ~4.20 V typical of a single-cell LiPo) is worth logging for the dissertation. It doesn't affect the validity of the percentage mapping in-app so long as the same ADC reading path is used at runtime, but the ADC calibration or charging IC set-point may be worth checking after the exhibition.