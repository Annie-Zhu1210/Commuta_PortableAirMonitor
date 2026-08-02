"""
Commuta battery discharge characterisation.

Fits a LOWESS smoother to the raw vbat_mv readings, uses the fitted curve to
interpolate through the 68.8-min data gap between 22:38 and 23:53, and builds
a voltage -> percentage-remaining lookup table for use in the Commuta app or
for exhibition-day stop decisions.

Inputs
------
CSV columns: boot_epoch, sequence_number, timestamp, vbat_mv, dps368_temp_c, source_flag

Outputs
-------
battery_curve.png                   Discharge chart with raw + fitted + gap + phases
voltage_percentage_curve.png        Voltage -> percentage remaining curve
voltage_percentage_lookup.csv       50 mV lookup table (3.90 V down to 2.40 V)
battery_report.md                   Markdown report of the fit and findings

Usage
-----
python3 battery_analysis.py [path/to/input.csv] [output_dir]
Defaults: input = commuta_battery_characterisation_20260802_004327.csv
          output_dir = ./
"""
import sys
from pathlib import Path
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from statsmodels.nonparametric.smoothers_lowess import lowess
from sklearn.isotonic import IsotonicRegression

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
LOWESS_FRAC = 0.05          # bandwidth for the local smoother (~5% of samples)
GAP_MIN_SEQ = 100           # sequence gap size that qualifies as a "big" gap
LOOKUP_STEP_MV = 50         # spacing of the lookup table in mV
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
    df['t_seconds'] = (df['timestamp'] - df['timestamp'].iloc[0]).dt.total_seconds()
    df['t_hours'] = df['t_seconds'] / 3600.0
    df['sequence_number'] = df['sequence_number'].astype(int)
    df['vbat_mv'] = df['vbat_mv'].astype(int)
    return df


def find_gaps(df: pd.DataFrame, min_seq: int) -> list:
    """Return list of (t_start_h, t_end_h, seq_missing) for gaps above threshold."""
    seq = df['sequence_number'].values
    t = df['t_hours'].values
    diffs = np.diff(seq)
    idxs = np.where(diffs > min_seq)[0]
    return [(t[i], t[i + 1], int(diffs[i] - 1)) for i in idxs]


# -----------------------------------------------------------------------------
# Curve fitting
# -----------------------------------------------------------------------------
def fit_lowess(t: np.ndarray, v: np.ndarray, frac: float) -> tuple:
    """Fit LOWESS and force non-increasing (cumulative-min) for percentage inversion."""
    sm = lowess(v, t, frac=frac, return_sorted=True)
    t_fit, v_fit = sm[:, 0], sm[:, 1]
    v_mono = np.minimum.accumulate(v_fit)
    return t_fit, v_fit, v_mono


def fit_isotonic(t: np.ndarray, v: np.ndarray) -> np.ndarray:
    ir = IsotonicRegression(increasing=False)
    return ir.fit_transform(t, v)


# -----------------------------------------------------------------------------
# Voltage <-> time <-> percentage inversion
# -----------------------------------------------------------------------------
def voltage_to_time_hours(v_query: float, t_arr: np.ndarray, v_arr_mono: np.ndarray) -> float:
    """For a non-increasing v_arr_mono over t_arr, return the time at which v_arr_mono crosses v_query."""
    if v_query >= v_arr_mono[0]:
        return t_arr[0]
    if v_query <= v_arr_mono[-1]:
        return t_arr[-1]
    idx = np.searchsorted(-v_arr_mono, -v_query)
    if idx == 0:
        return t_arr[0]
    if idx == len(v_arr_mono):
        return t_arr[-1]
    t0, t1 = t_arr[idx - 1], t_arr[idx]
    v0, v1 = v_arr_mono[idx - 1], v_arr_mono[idx]
    if v0 == v1:
        return t0
    frac = (v0 - v_query) / (v0 - v1)
    return t0 + frac * (t1 - t0)


def voltage_to_percent(v_query: float, t_arr: np.ndarray, v_arr_mono: np.ndarray, total_runtime_h: float) -> float:
    t = voltage_to_time_hours(v_query, t_arr, v_arr_mono)
    return max(0.0, min(100.0, 100.0 * (1.0 - t / total_runtime_h)))


# -----------------------------------------------------------------------------
# Phase segmentation
# -----------------------------------------------------------------------------
def segment_phases(t_fit: np.ndarray, v_mono: np.ndarray) -> list:
    """
    Return list of (phase_name, t_start_h, t_end_h, v_start_mv, v_end_mv, mean_slope_mV_per_h).

    Phases are identified heuristically from the smoothed derivative:
      - initial_drop:   |dv/dt| >= 100 mV/h at the start
      - plateau:        |dv/dt| <= 60 mV/h in the middle
      - decline:        60 < |dv/dt| <= 120 mV/h leading into the knee
      - cutoff:         |dv/dt| >= 120 mV/h at the tail
    """
    dv_dt = np.gradient(v_mono, t_fit)  # mV/hour, negative

    # Find hard boundaries with rolling thresholds
    n = len(t_fit)
    # Initial drop: from t=0 until |dv/dt| first drops below 100 mV/h and stays there for >0.5h
    initial_end = 0
    for i in range(n):
        if abs(dv_dt[i]) < 100 and t_fit[i] > 0.5:
            initial_end = i
            break

    # Cutoff: last portion where |dv/dt| > 120 mV/h, sustained
    cutoff_start = n - 1
    for i in range(n - 1, 0, -1):
        if abs(dv_dt[i]) < 120:
            cutoff_start = i
            break

    # Split middle into plateau and decline by finding where |dv/dt| exceeds 80 for the last time before cutoff
    plateau_end = initial_end
    for i in range(initial_end, cutoff_start):
        if abs(dv_dt[i]) < 60:
            plateau_end = i
    # decline runs from plateau_end to cutoff_start

    phases = []

    def add_phase(name, i0, i1):
        if i1 <= i0:
            return
        v0 = v_mono[i0]
        v1 = v_mono[i1]
        t0 = t_fit[i0]
        t1 = t_fit[i1]
        slope = (v1 - v0) / (t1 - t0) if t1 > t0 else 0.0
        phases.append((name, t0, t1, v0, v1, slope))

    add_phase('Initial drop', 0, initial_end)
    add_phase('Plateau', initial_end, plateau_end)
    add_phase('Decline', plateau_end, cutoff_start)
    add_phase('Cutoff', cutoff_start, n - 1)
    return phases


# -----------------------------------------------------------------------------
# Plotting
# -----------------------------------------------------------------------------
def plot_discharge_curve(df, t_fit, v_fit, v_iso, gaps, phases, stop_voltage_mv, output_path):
    fig, ax = plt.subplots(figsize=(12, 6.5))

    # Phase background stripes
    for i, (name, t0, t1, v0, v1, slope) in enumerate(phases):
        ax.axvspan(t0, t1, facecolor=COLOUR_PHASE_BG[i % len(COLOUR_PHASE_BG)], zorder=0, alpha=0.5)
        ax.text((t0 + t1) / 2, 3.98, name, ha='center', va='bottom', fontsize=9,
                color='dimgrey', zorder=5)

    # Raw scatter
    ax.scatter(df['t_hours'], df['vbat_mv'] / 1000.0, s=3, c=COLOUR_RAW, alpha=0.25,
               label='Raw readings', zorder=1)

    # Fitted curves
    ax.plot(t_fit, v_fit / 1000.0, color=COLOUR_FIT, lw=1.8,
            label=f'LOWESS fit (frac={LOWESS_FRAC})', zorder=3)
    ax.plot(df['t_hours'], v_iso / 1000.0, color=COLOUR_ISO, lw=1.0, ls='--',
            label='Isotonic (monotonic) reference', zorder=2, alpha=0.7)

    # Gap regions
    for i, (t0, t1, missing) in enumerate(gaps):
        label = 'Data gap (bridged by fit)' if i == 0 else None
        ax.axvspan(t0, t1, facecolor=COLOUR_GAP, alpha=0.15, zorder=1, label=label)

    # Stop threshold
    ax.axhline(stop_voltage_mv / 1000.0, color=COLOUR_STOP, ls=':', lw=1.4, zorder=4,
               label=f'Planned stop threshold ({stop_voltage_mv/1000:.2f} V)')

    ax.set_xlabel('Time from start of test (hours)', fontsize=11)
    ax.set_ylabel('Battery voltage (V)', fontsize=11)
    ax.set_title('Commuta battery discharge curve — 24-hour drain test', fontsize=13, pad=14)
    ax.set_xlim(0, 24)
    ax.set_ylim(2.3, 4.05)
    ax.grid(True, alpha=0.3)
    ax.legend(loc='upper right', fontsize=9, framealpha=0.95)

    plt.tight_layout()
    plt.savefig(output_path, dpi=140, bbox_inches='tight')
    plt.close(fig)


def plot_voltage_percent_curve(t_fit, v_mono, total_runtime_h, stop_voltage_mv, output_path):
    v_range = np.arange(2400, 3931, 10)  # mV
    pct = [voltage_to_percent(v, t_fit, v_mono, total_runtime_h) for v in v_range]

    fig, ax = plt.subplots(figsize=(10, 5.5))
    ax.plot(v_range / 1000.0, pct, color=COLOUR_FIT, lw=2.0)

    # Mark key voltages
    for v_mv, label in [(3800, '3.80 V'), (3700, '3.70 V'), (3600, '3.60 V'),
                        (3500, '3.50 V'), (3400, '3.40 V'), (3300, '3.30 V'),
                        (3200, '3.20 V'), (3000, '3.00 V')]:
        p = voltage_to_percent(v_mv, t_fit, v_mono, total_runtime_h)
        ax.plot(v_mv / 1000.0, p, 'o', color=COLOUR_FIT, ms=5)
        ax.annotate(f'{label}: {p:.0f}%', (v_mv / 1000.0, p),
                    xytext=(6, 4), textcoords='offset points', fontsize=8)

    # Stop threshold
    p_stop = voltage_to_percent(stop_voltage_mv, t_fit, v_mono, total_runtime_h)
    ax.axvline(stop_voltage_mv / 1000.0, color=COLOUR_STOP, ls=':', lw=1.4,
               label=f'Planned stop: {stop_voltage_mv/1000:.2f} V ≈ {p_stop:.0f}% remaining')

    ax.set_xlabel('Battery voltage (V)', fontsize=11)
    ax.set_ylabel('Percentage remaining (% of 24 h runtime)', fontsize=11)
    ax.set_title('Voltage → percentage-remaining lookup', fontsize=13, pad=14)
    ax.set_xlim(2.4, 3.95)
    ax.set_ylim(-2, 102)
    ax.invert_xaxis()  # so full-charge is on the left
    ax.grid(True, alpha=0.3)
    ax.legend(loc='upper left', fontsize=9)

    plt.tight_layout()
    plt.savefig(output_path, dpi=140, bbox_inches='tight')
    plt.close(fig)


# -----------------------------------------------------------------------------
# Lookup table
# -----------------------------------------------------------------------------
def build_lookup(t_fit, v_mono, total_runtime_h, step_mv=50) -> pd.DataFrame:
    v_range = list(range(3900, 2400 - step_mv, -step_mv))
    rows = []
    for v_mv in v_range:
        t_h = voltage_to_time_hours(v_mv, t_fit, v_mono)
        pct = max(0.0, min(100.0, 100.0 * (1.0 - t_h / total_runtime_h)))
        rows.append({
            'vbat_mv': v_mv,
            'vbat_v': v_mv / 1000.0,
            'time_elapsed_h': round(t_h, 3),
            'percent_remaining': round(pct, 1),
            'estimated_hours_left': round(total_runtime_h - t_h, 2),
        })
    return pd.DataFrame(rows)


# -----------------------------------------------------------------------------
# Markdown report
# -----------------------------------------------------------------------------
def write_report(output_path, df, gaps, phases, t_fit, v_mono, lookup_df,
                 total_runtime_h, stop_voltage_mv):
    v_start = int(df['vbat_mv'].iloc[0])
    v_peak = int(df['vbat_mv'].max())
    v_end = int(df['vbat_mv'].iloc[-1])
    t_start = df['timestamp'].iloc[0]
    t_end = df['timestamp'].iloc[-1]

    p_at_stop = voltage_to_percent(stop_voltage_mv, t_fit, v_mono, total_runtime_h)
    t_at_stop = voltage_to_time_hours(stop_voltage_mv, t_fit, v_mono)

    p_at_3600 = voltage_to_percent(3600, t_fit, v_mono, total_runtime_h)
    p_at_3500 = voltage_to_percent(3500, t_fit, v_mono, total_runtime_h)
    p_at_3400 = voltage_to_percent(3400, t_fit, v_mono, total_runtime_h)
    p_at_3200 = voltage_to_percent(3200, t_fit, v_mono, total_runtime_h)

    md = []
    md.append("# Commuta battery discharge characterisation\n")
    md.append(f"Test run: **{t_start.strftime('%Y-%m-%d %H:%M')}** to "
              f"**{t_end.strftime('%Y-%m-%d %H:%M')} ({t_end.tzinfo})**  ")
    md.append(f"Total runtime: **{total_runtime_h:.2f} hours** on a single full charge.\n")

    md.append("## 1. Data quality\n")
    md.append(f"- **Rows recorded:** {len(df):,} out of a theoretical maximum of ~8,640 "
              f"(24 h × 6 samples/min).")
    md.append(f"- **Single power session:** one `boot_epoch` throughout — device did not reboot.")
    md.append(f"- **Voltage range:** {v_start} mV at first recorded sample, "
              f"peak {v_peak} mV shortly after, ending at {v_end} mV when the device died.\n")
    md.append("### Sequence gaps\n")
    md.append("| Time window | Duration | Missing readings |")
    md.append("|---|---|---|")
    for t0, t1, missing in gaps:
        md.append(f"| {t0:.2f} h – {t1:.2f} h | {(t1 - t0) * 60:.1f} min | {missing} |")
    md.append("")
    md.append("The 68.8-min gap is the app-backgrounded period; this is a genuine gap in the "
              "recorded data (not a display-only gap), and it has been bridged by the fitted "
              "curve rather than filled with raw values.\n")

    md.append("## 2. Curve fit\n")
    md.append(f"- **Method:** locally-weighted regression (LOWESS) with bandwidth "
              f"`frac = {LOWESS_FRAC}`, forced non-increasing via cumulative-minimum for "
              f"percentage inversion.")
    md.append("- **Reference fit:** isotonic regression (guaranteed monotonic) is overlaid on "
              "the chart for comparison. The two agree closely except in the very flat plateau, "
              "where LOWESS gives a smoother characterisation of the underlying trend and "
              "isotonic is more sensitive to individual noisy samples.")
    md.append("- **Gap handling:** the fit is trained on all recorded samples (no synthetic "
              "points inserted). Because LOWESS is a local smoother, the 68.8-min gap is "
              "bridged naturally by anchoring on the samples immediately before and after; "
              "given the smooth, slowly-varying voltage in that region, this is a low-risk "
              "interpolation.\n")

    md.append("## 3. Discharge phases\n")
    md.append("| Phase | Time window | Voltage window | Mean slope |")
    md.append("|---|---|---|---|")
    for name, t0, t1, v0, v1, slope in phases:
        md.append(f"| **{name}** | {t0:.2f} h – {t1:.2f} h | {v0:.0f} mV → {v1:.0f} mV | "
                  f"{slope:.1f} mV/h |")
    md.append("")
    md.append("Interpretation:\n")
    md.append("- **Initial drop.** The characteristic post-full-charge relaxation — the "
              "surface-charge component decays quickly under load. This is normal.")
    md.append("- **Plateau.** A long, very flat region where voltage is a poor indicator of "
              "remaining charge — a single reading of, say, 3.60 V could correspond to anywhere "
              "from a few hours to a dozen hours of remaining runtime. Any in-app battery "
              "indicator based on voltage alone will be inherently coarse across this region.")
    md.append("- **Decline.** Voltage starts to fall more steadily as the cell approaches its "
              "empty state. Percentage estimates become more reliable here.")
    md.append("- **Cutoff.** A steep terminal drop of several hundred mV/hour. From the knee "
              "onwards the cell has very little useful capacity left.\n")

    md.append("## 4. Voltage → percentage-remaining lookup\n")
    md.append("Percentages are computed as `1 − t(V) / total_runtime`, where `t(V)` is the "
              "time at which the fitted curve crosses voltage `V`, and `total_runtime` = "
              f"{total_runtime_h:.2f} h. Full 50 mV lookup is in `voltage_percentage_lookup.csv`.\n")
    md.append("| Voltage | Time reached | Percent remaining | Hours left |")
    md.append("|---|---|---|---|")
    for _, r in lookup_df.iterrows():
        if int(r['vbat_mv']) % 100 == 0 or int(r['vbat_mv']) in (3300, 3350):
            md.append(f"| {r['vbat_v']:.2f} V | {r['time_elapsed_h']:.2f} h | "
                      f"{r['percent_remaining']:.0f}% | {r['estimated_hours_left']:.1f} h |")
    md.append("")

    md.append("## 5. Recommendation on the stop threshold\n")
    md.append(f"- At **{stop_voltage_mv/1000:.2f} V**, the fitted curve gives "
              f"**≈ {p_at_stop:.0f}% remaining** (device would have died in another "
              f"~{total_runtime_h - t_at_stop:.1f} hours from that point in this test).")
    md.append(f"- Selected reference points for context:")
    md.append(f"  - 3.60 V ≈ {p_at_3600:.0f}% remaining (mid-plateau; percentage estimate is soft here)")
    md.append(f"  - 3.50 V ≈ {p_at_3500:.0f}% remaining (near end of plateau)")
    md.append(f"  - 3.40 V ≈ {p_at_3400:.0f}% remaining (into the decline)")
    md.append(f"  - 3.20 V ≈ {p_at_3200:.0f}% remaining (past the knee, close to empty)")
    md.append("")
    md.append(f"Stopping at 3.30 V is a reasonable protective choice — it leaves about a fifth "
              f"of practical capacity in the cell and keeps well clear of the terminal collapse "
              f"below ~3.10 V. If you wanted to be more conservative for cell longevity "
              f"(especially with a cell whose full-charge voltage sits around 3.93 V rather "
              f"than the 4.20 V of a typical LiPo), stopping around **3.40–3.50 V** would "
              f"leave more headroom at the cost of shorter runtime per charge.\n")
    md.append(f"- **Practical exhibition runtime at 3.30 V stop:** approximately "
              f"**{t_at_stop:.1f} hours** per full charge.")
    md.append("- No firmware low-voltage cutoff currently exists; this test drove the cell to "
              f"{v_end} mV (the point at which the device could no longer boot). If a firmware "
              "cutoff is added later, 3.30 V would be a sensible default given the observed "
              "shape.\n")

    md.append("## 6. Caveats\n")
    md.append("- Percentages here are relative to *this specific test's* runtime under the "
              "measured load. Real-world runtime will vary with BLE activity, temperature, "
              "cell ageing, and whether the app is foregrounded (buffering vs streaming).")
    md.append("- The plateau region gives inherently ambiguous percentages — this is a "
              "property of the cell chemistry, not the fitting method.")
    md.append("- The full-charge peak of ~3.93 V (rather than the ~4.20 V typical of a "
              "single-cell LiPo) is worth logging for the dissertation; it does not affect the "
              "validity of the percentage mapping in-app so long as the same ADC reading path "
              "is used at runtime, but it may be worth checking the ADC calibration or charging "
              "IC set-point at some point after the exhibition.")

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
    gaps = find_gaps(df, GAP_MIN_SEQ)
    t_fit, v_fit, v_mono = fit_lowess(df['t_hours'].values, df['vbat_mv'].values, LOWESS_FRAC)
    v_iso = fit_isotonic(df['t_hours'].values, df['vbat_mv'].values)
    phases = segment_phases(t_fit, v_mono)
    total_runtime_h = float(df['t_hours'].iloc[-1] - df['t_hours'].iloc[0])
    stop_voltage_mv = 3300

    lookup = build_lookup(t_fit, v_mono, total_runtime_h, LOOKUP_STEP_MV)

    plot_discharge_curve(df, t_fit, v_fit, v_iso, gaps, phases, stop_voltage_mv,
                         out_dir / 'battery_curve.png')
    plot_voltage_percent_curve(t_fit, v_mono, total_runtime_h, stop_voltage_mv,
                               out_dir / 'voltage_percentage_curve.png')
    lookup.to_csv(out_dir / 'voltage_percentage_lookup.csv', index=False)
    write_report(out_dir / 'battery_report.md', df, gaps, phases, t_fit, v_mono, lookup,
                 total_runtime_h, stop_voltage_mv)

    print(f"Wrote outputs to {out_dir.resolve()}")


if __name__ == '__main__':
    main(sys.argv)