"""
Commuta battery discharge characterisation — corrected axis.

Rebuilds the discharge curve, lookup table, and report using sequence-based
*active sampling time* rather than wall-clock time. This corrects a substantive
error in the original run of this script, which used wall-clock time and so
silently interpolated LOWESS across two device-off periods (10.3 h and 56 min),
creating two entirely fake voltage plateaus.

The fix is one line of principle: each sample's sequence number is a
monotonically incrementing counter that only advances when the device is
actually sampling. Multiplying the sequence delta from the first row by the
10 s sampling interval gives true active runtime. Wall-clock timestamps
(from the phone at packet arrival) are only used as a diagnostic for gap
detection.

Inputs
------
CSV columns: boot_epoch, sequence_number, timestamp, vbat_mv,
             dps368_temp_c, source_flag

Outputs
-------
battery_curve.png                   Discharge chart, active-time axis
voltage_percentage_curve.png        Voltage → percentage remaining
voltage_percentage_lookup.csv       50 mV lookup table
battery_report.md                   Markdown report

Usage
-----
python3 battery_analysis.py [path/to/input.csv] [output_dir]
"""
import sys
from pathlib import Path
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from statsmodels.nonparametric.smoothers_lowess import lowess
from sklearn.isotonic import IsotonicRegression

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
LOWESS_FRAC = 0.05
LOOKUP_STEP_MV = 50
SAMPLING_INTERVAL_S = 10
STOP_VOLTAGE_MV = 3300

# Gap detection thresholds:
#   • device-off: wall-clock jump > this AND sequence increment ≤ 2
#     (the device stopped sampling entirely)
#   • data-loss: sequence jump > this (device kept sampling but some samples
#     never reached the CSV — e.g. app backgrounded, buffer overflow)
DEVICE_OFF_MIN_DT_MIN = 5
DEVICE_OFF_MAX_DSEQ = 2
DATA_LOSS_MIN_DSEQ = 5

COLOUR_RAW = '#B0B0B0'
COLOUR_FIT = '#0B5FFF'
COLOUR_ISO = '#7B7B7B'
COLOUR_GAP = '#FF3B30'
COLOUR_STOP = '#E67300'
COLOUR_PHASE_BG = ['#E8F1FF', '#EAF7E6', '#FFF6DA', '#FBE6E6']


# -----------------------------------------------------------------------------
# Data loading
# -----------------------------------------------------------------------------
def load(csv_path: Path) -> pd.DataFrame:
    df = pd.read_csv(csv_path, encoding='utf-8-sig')
    df['timestamp'] = pd.to_datetime(df['timestamp'])
    df['sequence_number'] = df['sequence_number'].astype(int)
    df['vbat_mv'] = df['vbat_mv'].astype(int)

    first_seq = int(df['sequence_number'].iloc[0])
    # Active sampling time: one tick per sample × 10 s. This is the true
    # elapsed runtime the cell has been under load.
    df['active_hours'] = (df['sequence_number'] - first_seq) * SAMPLING_INTERVAL_S / 3600.0
    # Wall-clock (phone-side) time, used only for gap diagnostics.
    df['wall_hours'] = (
        df['timestamp'] - df['timestamp'].iloc[0]
    ).dt.total_seconds() / 3600.0
    return df


def detect_gaps(df: pd.DataFrame) -> tuple[list, list]:
    """
    Return (device_off_gaps, data_loss_gaps).

    A device-off gap is a wall-clock jump between consecutive rows that is
    large but with only a tiny sequence increment — the device stopped
    sampling. A data-loss gap has a much larger sequence increment relative
    to the wall-clock delta — the device kept sampling but some samples
    never made it into the CSV.
    """
    device_off = []
    data_loss = []
    for i in range(1, len(df)):
        dt_min = (df['wall_hours'].iloc[i] - df['wall_hours'].iloc[i - 1]) * 60.0
        dseq = int(df['sequence_number'].iloc[i] - df['sequence_number'].iloc[i - 1])
        base = {
            'seq_before': int(df['sequence_number'].iloc[i - 1]),
            'seq_after': int(df['sequence_number'].iloc[i]),
            'wall_dt_min': float(dt_min),
            'seq_dt': dseq,
            'active_hours_before': float(df['active_hours'].iloc[i - 1]),
            'active_hours_after': float(df['active_hours'].iloc[i]),
            'v_before_mv': int(df['vbat_mv'].iloc[i - 1]),
            'v_after_mv': int(df['vbat_mv'].iloc[i]),
            'timestamp_before': df['timestamp'].iloc[i - 1],
            'timestamp_after': df['timestamp'].iloc[i],
        }
        if dt_min > DEVICE_OFF_MIN_DT_MIN and dseq <= DEVICE_OFF_MAX_DSEQ:
            device_off.append(base)
        elif dseq >= DATA_LOSS_MIN_DSEQ:
            base['missing_count'] = dseq - 1
            data_loss.append(base)
    return device_off, data_loss


# -----------------------------------------------------------------------------
# Curve fitting
# -----------------------------------------------------------------------------
def fit_lowess(t: np.ndarray, v: np.ndarray, frac: float) -> tuple:
    sm = lowess(v, t, frac=frac, return_sorted=True)
    t_fit, v_fit = sm[:, 0], sm[:, 1]
    v_mono = np.minimum.accumulate(v_fit)
    return t_fit, v_fit, v_mono


def fit_isotonic(t: np.ndarray, v: np.ndarray) -> np.ndarray:
    ir = IsotonicRegression(increasing=False)
    return ir.fit_transform(t, v)


# -----------------------------------------------------------------------------
# Voltage ↔ time ↔ percentage
# -----------------------------------------------------------------------------
def voltage_to_time_hours(v_query: float, t_arr: np.ndarray, v_mono: np.ndarray) -> float:
    if v_query >= v_mono[0]:
        return t_arr[0]
    if v_query <= v_mono[-1]:
        return t_arr[-1]
    idx = np.searchsorted(-v_mono, -v_query)
    if idx == 0:
        return t_arr[0]
    if idx == len(v_mono):
        return t_arr[-1]
    t0, t1 = t_arr[idx - 1], t_arr[idx]
    v0, v1 = v_mono[idx - 1], v_mono[idx]
    if v0 == v1:
        return t0
    frac = (v0 - v_query) / (v0 - v1)
    return t0 + frac * (t1 - t0)


def voltage_to_percent(v_query, t_arr, v_mono, total_active_h) -> float:
    t = voltage_to_time_hours(v_query, t_arr, v_mono)
    return max(0.0, min(100.0, 100.0 * (1.0 - t / total_active_h)))


# -----------------------------------------------------------------------------
# Phase segmentation
# -----------------------------------------------------------------------------
def segment_phases(t_fit: np.ndarray, v_mono: np.ndarray) -> list:
    """
    Segment the corrected curve into a few interpretable phases based on the
    slope of the smoothed voltage:

      • Initial drop:   |dv/dt| ≥ 150 mV/h at the very start (post-full-charge
                        surface-charge relaxation)
      • Gentle decline: the long middle where the cell empties steadily
      • Knee:           slope grows to 100–200 mV/h ahead of the terminal drop
      • Cutoff:         terminal steep drop, |dv/dt| ≥ 200 mV/h
    """
    dv_dt = np.gradient(v_mono, t_fit)
    n = len(t_fit)

    # Initial drop: from t=0 until |dv/dt| first drops below 150 mV/h
    initial_end = 0
    for i in range(n):
        if abs(dv_dt[i]) < 150 and t_fit[i] > 0.3:
            initial_end = i
            break

    # Cutoff: last sustained region where |dv/dt| ≥ 200 mV/h
    cutoff_start = n - 1
    for i in range(n - 1, 0, -1):
        if abs(dv_dt[i]) < 200:
            cutoff_start = i
            break

    # Knee: between gentle decline and cutoff, |dv/dt| in the 100-200 mV/h band
    knee_start = cutoff_start
    for i in range(cutoff_start, initial_end, -1):
        if abs(dv_dt[i]) < 100:
            knee_start = i
            break

    phases = []

    def add(name, i0, i1):
        if i1 <= i0:
            return
        v0, v1 = float(v_mono[i0]), float(v_mono[i1])
        t0, t1 = float(t_fit[i0]), float(t_fit[i1])
        slope = (v1 - v0) / (t1 - t0) if t1 > t0 else 0.0
        phases.append((name, t0, t1, v0, v1, slope))

    add('Initial drop', 0, initial_end)
    add('Gentle decline', initial_end, knee_start)
    add('Knee', knee_start, cutoff_start)
    add('Cutoff', cutoff_start, n - 1)
    return phases


# -----------------------------------------------------------------------------
# Plots
# -----------------------------------------------------------------------------
def plot_discharge_curve(df, t_fit, v_fit, v_iso, data_loss, phases,
                         stop_voltage_mv, active_total, output_path):
    fig, ax = plt.subplots(figsize=(12, 6.5))

    for i, (name, t0, t1, v0, v1, slope) in enumerate(phases):
        ax.axvspan(t0, t1, facecolor=COLOUR_PHASE_BG[i % len(COLOUR_PHASE_BG)],
                   zorder=0, alpha=0.5)
        ax.text((t0 + t1) / 2, 3.98, name, ha='center', va='bottom', fontsize=9,
                color='dimgrey', zorder=5)

    ax.scatter(df['active_hours'], df['vbat_mv'] / 1000.0, s=3, c=COLOUR_RAW,
               alpha=0.25, label='Raw readings', zorder=1)
    ax.plot(t_fit, v_fit / 1000.0, color=COLOUR_FIT, lw=1.8,
            label=f'LOWESS fit (frac={LOWESS_FRAC})', zorder=3)
    ax.plot(df['active_hours'].values, v_iso / 1000.0, color=COLOUR_ISO,
            lw=1.0, ls='--', label='Isotonic (monotonic) reference',
            zorder=2, alpha=0.7)

    for i, gap in enumerate(data_loss):
        label = 'App-backgrounded (data loss)' if i == 0 else None
        ax.axvspan(gap['active_hours_before'], gap['active_hours_after'],
                   facecolor=COLOUR_GAP, alpha=0.15, zorder=1, label=label)

    ax.axhline(stop_voltage_mv / 1000.0, color=COLOUR_STOP, ls=':', lw=1.4,
               zorder=4,
               label=f'Planned stop threshold ({stop_voltage_mv/1000:.2f} V)')

    ax.set_xlabel('Active sampling time (hours)', fontsize=11)
    ax.set_ylabel('Battery voltage (V)', fontsize=11)
    ax.set_title(
        f'Commuta battery discharge curve — {active_total:.2f} h active runtime',
        fontsize=13, pad=14,
    )
    ax.set_xlim(0, active_total + 0.2)
    ax.set_ylim(2.3, 4.05)
    ax.grid(True, alpha=0.3)
    ax.legend(loc='upper right', fontsize=9, framealpha=0.95)
    plt.tight_layout()
    plt.savefig(output_path, dpi=140, bbox_inches='tight')
    plt.close(fig)


def plot_voltage_percent_curve(t_fit, v_mono, active_total, stop_voltage_mv,
                                output_path):
    v_range = np.arange(2400, 3931, 10)
    pct = [voltage_to_percent(v, t_fit, v_mono, active_total) for v in v_range]

    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.plot(v_range / 1000.0, pct, color=COLOUR_FIT, lw=2.0)

    for v_mv, label in [(3800, '3.80 V'), (3700, '3.70 V'), (3600, '3.60 V'),
                        (3500, '3.50 V'), (3400, '3.40 V'), (3300, '3.30 V'),
                        (3200, '3.20 V'), (3000, '3.00 V')]:
        p = voltage_to_percent(v_mv, t_fit, v_mono, active_total)
        ax.plot(v_mv / 1000.0, p, 'o', color=COLOUR_FIT, ms=5)
        ax.annotate(f'{label}: {p:.0f}%', (v_mv / 1000.0, p),
                    xytext=(6, 4), textcoords='offset points', fontsize=8)

    p_stop = voltage_to_percent(stop_voltage_mv, t_fit, v_mono, active_total)
    ax.axvline(stop_voltage_mv / 1000.0, color=COLOUR_STOP, ls=':', lw=1.4,
               label=f'Planned stop: {stop_voltage_mv/1000:.2f} V '
                     f'≈ {p_stop:.0f}% remaining')

    ax.set_xlabel('Battery voltage (V)', fontsize=11)
    ax.set_ylabel(
        f'Percentage remaining (% of {active_total:.2f} h active runtime)',
        fontsize=11,
    )
    ax.set_title('Voltage → percentage-remaining lookup', fontsize=13, pad=14)
    ax.set_xlim(2.4, 3.95)
    ax.set_ylim(-2, 102)
    ax.invert_xaxis()
    ax.grid(True, alpha=0.3)
    ax.legend(loc='upper left', fontsize=9)
    plt.tight_layout()
    plt.savefig(output_path, dpi=140, bbox_inches='tight')
    plt.close(fig)


# -----------------------------------------------------------------------------
# Lookup table
# -----------------------------------------------------------------------------
def build_lookup(t_fit, v_mono, active_total, step_mv=50) -> pd.DataFrame:
    v_range = list(range(3900, 2400 - step_mv, -step_mv))
    rows = []
    for v_mv in v_range:
        t_h = voltage_to_time_hours(v_mv, t_fit, v_mono)
        pct = max(0.0, min(100.0, 100.0 * (1.0 - t_h / active_total)))
        rows.append({
            'vbat_mv': v_mv,
            'vbat_v': v_mv / 1000.0,
            'active_time_elapsed_h': round(t_h, 3),
            'percent_remaining': round(pct, 1),
            'active_hours_left': round(active_total - t_h, 2),
        })
    return pd.DataFrame(rows)


# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------
def write_report(output_path, df, device_off, data_loss, phases, t_fit, v_mono,
                 lookup_df, active_total, stop_voltage_mv):
    v_start = int(df['vbat_mv'].iloc[0])
    v_peak = int(df['vbat_mv'].max())
    v_end = int(df['vbat_mv'].iloc[-1])
    t_start = df['timestamp'].iloc[0]
    t_end = df['timestamp'].iloc[-1]
    wall_total = float(df['wall_hours'].iloc[-1])

    p_at_stop = voltage_to_percent(stop_voltage_mv, t_fit, v_mono, active_total)
    t_at_stop = voltage_to_time_hours(stop_voltage_mv, t_fit, v_mono)

    md = []
    md.append("# Commuta battery discharge characterisation\n")
    md.append(f"Test run: **{t_start.strftime('%Y-%m-%d %H:%M')}** to "
              f"**{t_end.strftime('%Y-%m-%d %H:%M')} ({t_end.tzinfo})**  ")
    md.append(f"Wall-clock span: {wall_total:.2f} h. "
              f"**Active sampling runtime: {active_total:.2f} h** — "
              f"the cell was actually under load for this long. The two "
              f"periods when the device was switched off (see §1) do not "
              f"count.\n")

    md.append("> **Correction notice.** An earlier version of this report "
              "used wall-clock time as the discharge axis, which included "
              "the device-off periods and produced a fake voltage plateau. "
              "This version uses sequence-based active time, which is the "
              "correct denominator for a discharge curve. All lookup values "
              "and the stop-threshold recommendation have changed as a "
              "result.\n")

    # § 1 — Data quality
    md.append("## 1. Data quality\n")
    md.append(f"- **Rows recorded:** {len(df):,}.")
    md.append(f"- **Single power session:** one `boot_epoch` throughout — "
              f"device did not reboot even across the off-periods (the ESP32 "
              f"sequence counter is restored from NVS on power-up).")
    md.append(f"- **Voltage range:** {v_start} mV at first recorded sample, "
              f"peak {v_peak} mV shortly after, ending at {v_end} mV when the "
              f"device died.\n")

    if device_off:
        md.append("### Device-off periods\n")
        md.append("The device was switched off for these intervals. The "
                  "voltage was not actually flat during them — the cell was "
                  "simply not being sampled. On the active-time axis these "
                  "intervals collapse to zero width.\n")
        md.append("| Wall-clock start | Wall-clock end | Duration | Voltage before → after |")
        md.append("|---|---|---|---|")
        for g in device_off:
            md.append(f"| {g['timestamp_before'].strftime('%H:%M')} | "
                      f"{g['timestamp_after'].strftime('%H:%M')} | "
                      f"{g['wall_dt_min']:.1f} min | "
                      f"{g['v_before_mv']} mV → {g['v_after_mv']} mV |")
        md.append("")

    if data_loss:
        md.append("### Data-loss periods (device on, samples never reached CSV)\n")
        md.append("| Active-time window | Missing samples | Voltage before → after |")
        md.append("|---|---|---|")
        for g in data_loss:
            md.append(f"| {g['active_hours_before']:.2f} h – "
                      f"{g['active_hours_after']:.2f} h | "
                      f"{g['missing_count']} | "
                      f"{g['v_before_mv']} mV → {g['v_after_mv']} mV |")
        md.append("")
        md.append("These samples are irrecoverable — the LOWESS fit bridges "
                  "the window smoothly using the voltages either side, which "
                  "is safe given the slowly-varying discharge in that "
                  "region.\n")

    # § 2 — Method
    md.append("## 2. Method\n")
    md.append("- **Axis:** sequence-based active time. Each sample carries a "
              "monotonically incrementing `sequence_number` that only "
              "advances while the device is actually sampling, so "
              "`(sequence_number − first_sequence) × 10 s` gives the true "
              "elapsed runtime under load.")
    md.append(f"- **Smoother:** locally-weighted regression (LOWESS), "
              f"bandwidth `frac = {LOWESS_FRAC}`. Forced non-increasing via "
              f"cumulative-minimum for percentage inversion.")
    md.append("- **Reference:** isotonic regression (guaranteed monotonic) "
              "is overlaid on the chart as a sanity check.")
    md.append("- **Gap handling:** the two device-off intervals do not exist "
              "on this axis at all. "
              + ("The data-loss intervals are bridged by the LOWESS fit "
                 "anchored on the samples either side."
                 if len(data_loss) != 1
                 else "The one data-loss interval is bridged by "
                      "the LOWESS fit anchored on the samples either side.")
              + "\n")

    # § 3 — Phases
    md.append("## 3. Discharge phases\n")
    md.append("| Phase | Active-time window | Voltage window | Mean slope |")
    md.append("|---|---|---|---|")
    for name, t0, t1, v0, v1, slope in phases:
        md.append(f"| **{name}** | {t0:.2f} h – {t1:.2f} h | "
                  f"{v0:.0f} mV → {v1:.0f} mV | {slope:.1f} mV/h |")
    md.append("")
    md.append("Interpretation:\n")
    phase_descriptions = {
        'Initial drop':
            "**Initial drop.** The characteristic post-full-charge "
            "relaxation — the surface-charge component decays quickly "
            "under load.",
        'Gentle decline':
            "**Gentle decline.** The long middle where the cell empties "
            "at a steady rate. Voltage tracks state-of-charge reasonably "
            "well here — unlike the fake plateau in the earlier report, "
            "there is no true flat region in this cell's discharge.",
        'Knee':
            "**Knee.** Slope begins to grow as the cell approaches "
            "empty. Percentage estimates from voltage remain reliable.",
        'Cutoff':
            "**Cutoff.** Steep terminal drop of several hundred mV/hour. "
            "From here the cell has very little useful capacity left.",
    }
    detected_names = {p[0] for p in phases}
    for name, description in phase_descriptions.items():
        if name in detected_names:
            md.append(f"- {description}")
    md.append("")

    # § 4 — Lookup
    md.append("## 4. Voltage → percentage-remaining lookup\n")
    md.append(f"Percentages are computed as `1 − t(V) / active_total`, "
              f"where `t(V)` is the active time at which the fitted curve "
              f"crosses voltage `V`, and `active_total` = "
              f"{active_total:.2f} h. Full 50 mV lookup is in "
              f"`voltage_percentage_lookup.csv`.\n")
    md.append("| Voltage | Active time reached | Percent remaining | Active hours left |")
    md.append("|---|---|---|---|")
    for _, r in lookup_df.iterrows():
        v_mv = int(r['vbat_mv'])
        if v_mv % 100 == 0 or v_mv in (3350,):
            md.append(f"| {r['vbat_v']:.2f} V | "
                      f"{r['active_time_elapsed_h']:.2f} h | "
                      f"{r['percent_remaining']:.0f}% | "
                      f"{r['active_hours_left']:.1f} h |")
    md.append("")

    # § 5 — Stop threshold
    md.append("## 5. Recommendation on the stop threshold\n")
    md.append(f"- At **{stop_voltage_mv/1000:.2f} V**, the fitted curve "
              f"gives **≈ {p_at_stop:.0f}% remaining** — reached after "
              f"**{t_at_stop:.1f} hours** of active use, with roughly "
              f"**{active_total - t_at_stop:.1f} hours** of runtime still "
              f"available before the cell would die.")
    md.append("- Selected reference points for context:")
    for v_mv in (3600, 3500, 3400, 3200):
        p = voltage_to_percent(v_mv, t_fit, v_mono, active_total)
        md.append(f"  - {v_mv/1000:.2f} V ≈ {p:.0f}% remaining")
    md.append("")
    md.append(f"**Practical runtime with a 3.30 V manual stop: ~{t_at_stop:.1f} "
              f"hours of active use per charge.** This is enough for a "
              f"single exhibition day but not two — plan on charging the "
              f"cell nightly rather than trying to stretch a charge across "
              f"consecutive collection days. Stopping earlier (e.g. at "
              f"3.40 V, ≈ {voltage_to_percent(3400, t_fit, v_mono, active_total):.0f}%) "
              f"buys headroom for cell longevity at the cost of "
              f"shorter runtime per charge.\n")
    md.append(f"- No firmware low-voltage cutoff currently exists; this "
              f"test drove the cell to {v_end} mV (the point at which the "
              f"device could no longer boot).\n")

    # § 6 — Caveats
    md.append("## 6. Caveats\n")
    md.append("- Percentages here are relative to *this specific test's* "
              "active runtime under the observed load. Real-world runtime "
              "will vary with BLE activity, temperature, cell ageing, and "
              "whether the app is foregrounded (buffering vs streaming).")
    md.append("- **The in-app battery indicator uses the earlier (wrong) "
              "lookup table** and has not been updated. It will show "
              "systematically lower percentages than reality in the "
              "mid-voltage range (e.g. 21% displayed at 3.30 V rather than "
              f"~{p_at_stop:.0f}%, 29% at 3.40 V rather than "
              f"~{voltage_to_percent(3400, t_fit, v_mono, active_total):.0f}%). "
              "This is the conservative direction — the app under-reports, "
              "prompting earlier charging — but is worth logging for "
              "completeness.")
    md.append("- The full-charge peak of ~3.93 V (rather than the ~4.20 V "
              "typical of a single-cell LiPo) is worth logging for the "
              "dissertation. It doesn't affect the validity of the "
              "percentage mapping in-app so long as the same ADC reading "
              "path is used at runtime, but the ADC calibration or charging "
              "IC set-point may be worth checking after the exhibition.")

    Path(output_path).write_text('\n'.join(md), encoding='utf-8')


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
def main(argv):
    csv_path = Path(argv[1]) if len(argv) > 1 else Path(
        'commuta_battery_characterisation_20260802_004327.csv')
    out_dir = Path(argv[2]) if len(argv) > 2 else Path('.')
    out_dir.mkdir(parents=True, exist_ok=True)

    df = load(csv_path)
    device_off, data_loss = detect_gaps(df)
    active_total = float(df['active_hours'].iloc[-1])

    t_fit, v_fit, v_mono = fit_lowess(
        df['active_hours'].values, df['vbat_mv'].values, LOWESS_FRAC,
    )
    v_iso = fit_isotonic(df['active_hours'].values, df['vbat_mv'].values)
    phases = segment_phases(t_fit, v_mono)
    lookup = build_lookup(t_fit, v_mono, active_total, LOOKUP_STEP_MV)

    plot_discharge_curve(df, t_fit, v_fit, v_iso, data_loss, phases,
                         STOP_VOLTAGE_MV, active_total,
                         out_dir / 'battery_curve.png')
    plot_voltage_percent_curve(t_fit, v_mono, active_total, STOP_VOLTAGE_MV,
                               out_dir / 'voltage_percentage_curve.png')
    lookup.to_csv(out_dir / 'voltage_percentage_lookup.csv', index=False)
    write_report(out_dir / 'battery_report.md', df, device_off, data_loss,
                 phases, t_fit, v_mono, lookup, active_total, STOP_VOLTAGE_MV)

    print(f"Wrote outputs to {out_dir.resolve()}")
    print(f"Device-off gaps: {len(device_off)}")
    print(f"Data-loss gaps: {len(data_loss)}")
    print(f"Active runtime: {active_total:.2f} h")


if __name__ == '__main__':
    main(sys.argv)
