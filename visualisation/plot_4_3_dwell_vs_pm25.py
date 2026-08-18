# ======================================================================
# Figure 4.3 — Platform dwell time vs stop-mean PM2.5
# Self-contained: locates the clean CSV, rebuilds the stop-level table,
# computes Spearman correlations, and writes fig_4_3_dwell_vs_pm25.{png,pdf}
# next to this script (i.e. into visualisation/ if placed there).
#
# Read-only on commuta_clean.csv. Deps: pandas, numpy, matplotlib (no scipy).
# Run:  python visualisation/plot_4_3_dwell_vs_pm25.py
#   or: paste into a notebook cell and execute.
# ======================================================================
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import ScalarFormatter
from pathlib import Path

# ---- Locate paths regardless of where this is run from --------------
try:
    HERE = Path(__file__).resolve().parent      # running as a .py script
except NameError:
    HERE = Path.cwd()                            # running inside a notebook

CLEAN_PATH = None
for base in [HERE, *HERE.parents]:
    cand = base / "data" / "clean" / "commuta_clean.csv"
    if cand.exists():
        CLEAN_PATH = cand
        break
if CLEAN_PATH is None:
    raise FileNotFoundError(
        "Could not find data/clean/commuta_clean.csv — set CLEAN_PATH manually."
    )
OUT_DIR = HERE                                    # figures land beside the script

# ---- Load clean data -------------------------------------------------
df = pd.read_csv(CLEAN_PATH)
df["ts"] = pd.to_datetime(df["timestamp"], utc=True)
# sequence_number resets between files, so sort within each file
df = df.sort_values(["source_file", "sequence_number"]).reset_index(drop=True)

# ---- Build the stop-level table (same logic as dwell_spearman_cell) --
# A platform stop = maximal run of consecutive platform rows with the
# same station tag within one segment.
stops = []
for seg, g in df.groupby("segment_id", sort=False):
    g = g.sort_values("sequence_number")
    changed = (
        g["location_type"].ne(g["location_type"].shift())
        | g["station_name"].fillna("NA").ne(g["station_name"].fillna("NA").shift())
    )
    g = g.assign(stop_idx=changed.cumsum())
    platform = g[g["location_type"] == "platform"]
    for (stop_idx, station), s in platform.groupby(["stop_idx", "station_name"]):
        stops.append({
            "segment_id":  seg,
            "line_name":   s["line_name"].iloc[0],
            "group":       s["group"].iloc[0],
            "station_name": station,
            "n_samples":   len(s),
            "dwell_s":     (s["ts"].max() - s["ts"].min()).total_seconds() + 10,
            "pm25_mean":   s["pm25"].mean(),
            "pm10_mean":   s["pm10"].mean(),
        })
stops = pd.DataFrame(stops)

# ---- Spearman rho without scipy (rank-then-Pearson) ------------------
def spearman(a, b):
    return a.rank().corr(b.rank())

overall_rho = spearman(stops["dwell_s"], stops["pm25_mean"])
print(f"clean file : {CLEAN_PATH}")
print(f"n stops    : {len(stops)}")
print(f"overall rho: {overall_rho:+.3f}")

# ---- Academic plot style --------------------------------------------
plt.rcParams.update({
    "font.family": "serif",
    "font.size": 11,
    "axes.linewidth": 0.8,
    "xtick.direction": "out",
    "ytick.direction": "out",
})

# line -> (colour, marker); Okabe-Ito colourblind-safe palette
style = {
    "Northern":            ("#000000", "o"),
    "Victoria":            ("#0072B2", "s"),
    "Central":             ("#D55E00", "^"),
    "Jubilee":             ("#009E73", "D"),
    "Hammersmith & City":  ("#E69F00", "v"),
    "Elizabeth":           ("#CC79A7", "P"),
}
# legend ordered by descending within-line median PM (dirtiest first)
order = (stops.groupby("line_name")["pm25_mean"].median()
             .sort_values(ascending=False).index.tolist())

fig, ax = plt.subplots(figsize=(11.0, 4.0))

# WHO 24-h PM2.5 guideline reference line
ax.axhline(15, color="0.55", lw=0.9, ls=(0, (5, 4)), zorder=1)
ax.text(430, 16.5, "WHO 24-h guideline", va="bottom", ha="left",
        fontsize=8, color="0.4")

for line in order:
    g = stops[stops.line_name == line]
    colour, marker = style.get(line, ("0.3", "o"))
    rho = spearman(g["dwell_s"], g["pm25_mean"])
    ax.scatter(g["dwell_s"], g["pm25_mean"], s=42, marker=marker,
               facecolor=colour, edgecolor="white", linewidth=0.5, alpha=0.9,
               zorder=3,
               label=f"{line}  (n={len(g)}, " + r"$\rho$=" + f"{rho:+.2f})")

ax.set_yscale("log")
ax.set_ylim(2, 340)
ax.set_xlim(0, 700)
ax.set_yticks([2, 5, 10, 20, 50, 100, 200])
ax.get_yaxis().set_major_formatter(ScalarFormatter())
ax.set_xlabel("Platform dwell time (s)")
ax.set_ylabel(r"Stop-mean PM$_{2.5}$ ($\mu$g m$^{-3}$)")

ax.spines[["top", "right"]].set_visible(False)
ax.grid(True, which="major", axis="both", lw=0.4, color="0.88", zorder=0)
ax.grid(True, which="minor", axis="y", lw=0.3, color="0.94", zorder=0)

leg = ax.legend(title="Line  (within-line correlation)", loc="upper left",
                bbox_to_anchor=(1.02, 1.0), fontsize=8.3, title_fontsize=8.8,
                frameon=True, framealpha=0.95, edgecolor="0.7",
                borderpad=0.6, labelspacing=0.4)
leg.get_title().set_fontweight("normal")

fig.tight_layout()

# Place the overall-rho box just below the legend, left-aligned with it.
fig.canvas.draw()
lb = leg.get_window_extent()
lx0, ly0 = ax.transAxes.inverted().transform((lb.x0, lb.y0))
ovl = ax.text(lx0, ly0 - 0.045,
              "Overall  " + r"Spearman $\rho$ = " + f"{overall_rho:+.2f}"
              + f"   (n = {len(stops)} stops)",
              transform=ax.transAxes, ha="left", va="top", fontsize=9.5,
              bbox=dict(boxstyle="round,pad=0.4", fc="white", ec="0.7", lw=0.7))

png = OUT_DIR / "fig_4_3_dwell_vs_pm25.png"
pdf = OUT_DIR / "fig_4_3_dwell_vs_pm25.pdf"
fig.savefig(png, dpi=300, bbox_inches="tight", bbox_extra_artists=(leg, ovl))
fig.savefig(pdf, bbox_inches="tight", bbox_extra_artists=(leg, ovl))
print(f"saved      : {png}")
print(f"saved      : {pdf}")