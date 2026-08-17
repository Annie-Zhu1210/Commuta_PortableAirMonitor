"""
Fig 4.1a — Platform PM2.5 (and PM10 companion) by Underground line.

Overview box plots (one per line) showing the five-number summary
(min, Q1, median, Q3, max); overlaid points are per-stop medians (the
analytical unit). Boxes are coloured by official TfL line colour.
Background bands are UK DAQI thresholds (DEFRA) — different tables for
PM2.5 and PM10.

Reads : data/analysis/commuta_analysis.csv
        data/analysis/commuta_stops.csv
Writes: visualisation/figures/fig_4_1a_pm.pdf  (vector)
        visualisation/figures/fig_4_1a_pm.png  (300 dpi)
"""
import os
import numpy as np
import pandas as pd
import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm

# ---------------------------------------------------------------- fonts
FONT_DIR = os.path.join(os.path.dirname(__file__), "..", "fonts")
for f in ["Fraunces-Display.ttf", "Inter-Regular.ttf", "Inter-SemiBold.ttf"]:
    p = os.path.join(FONT_DIR, f)
    if os.path.exists(p):
        fm.fontManager.addfont(p)
SERIF = "Fraunces" if any("Fraunces" in f.name for f in fm.fontManager.ttflist) else "DejaVu Serif"
SANS = "Inter" if any(f.name == "Inter" for f in fm.fontManager.ttflist) else "DejaVu Sans"
mpl.rcParams.update({
    "font.family": SANS, "axes.edgecolor": "#4A4642",
    "text.color": "#3A3733", "axes.labelcolor": "#3A3733",
    "xtick.color": "#3A3733", "ytick.color": "#3A3733",
    "svg.fonttype": "none", "pdf.fonttype": 42,
})

# ---------------------------------------------------------------- data
a = pd.read_csv("data/analysis/commuta_analysis.csv")
stops = pd.read_csv("data/analysis/commuta_stops.csv")
plat = a[a.location_type == "platform"].copy()

LINE_ORDER = ["Northern", "Victoria", "Central", "Jubilee",
              "Hammersmith & City", "Elizabeth"]

# official TfL line colours (Northern = dark grey so black points stay visible)
LINE_COLOR = {
    "Central":            (219 / 255, 37 / 255, 30 / 255),
    "Northern":           (105 / 255, 105 / 255, 105 / 255),
    "Victoria":           (1 / 255, 160 / 255, 227 / 255),
    "Jubilee":            (135 / 255, 142 / 255, 152 / 255),
    "Hammersmith & City": (215 / 255, 153 / 255, 176 / 255),
    "Elizabeth":          (98 / 255, 66 / 255, 154 / 255),
}

# DAQI bands (µg/m³) — separate tables for PM2.5 and PM10 (DEFRA)
BAND_LOW_RGB = (122 / 255, 158 / 255, 135 / 255)
BAND_MID_RGB = (212 / 255, 169 / 255, 106 / 255)
BAND_HIGH_RGB = (204 / 255, 122 / 255, 111 / 255)
BAND_VHIGH_RGB = (155 / 255, 74 / 255, 66 / 255)
BAND_ALPHA = 0.5
DAQI = {
    "pm25": [(0, 35, BAND_LOW_RGB, "Low"), (35, 53, BAND_MID_RGB, "Moderate"),
             (53, 70, BAND_HIGH_RGB, "High"), (70, 1e4, BAND_VHIGH_RGB, "Very high")],
    "pm10": [(0, 50, BAND_LOW_RGB, "Low"), (50, 75, BAND_MID_RGB, "Moderate"),
             (75, 100, BAND_HIGH_RGB, "High"), (100, 1e4, BAND_VHIGH_RGB, "Very high")],
}


def panel(ax, metric, ylabel, ymax):
    for lo, hi, col, name in DAQI[metric]:
        ax.axhspan(lo, hi, color=col, alpha=BAND_ALPHA, zorder=0, linewidth=0)
        yc = min(hi, ymax) - (min(hi, ymax) - lo) * 0.5
        if lo < ymax:
            ax.text(len(LINE_ORDER) - 0.28, yc, name, va="center", ha="left",
                    fontsize=7.5, color="#4A4642", clip_on=False)

    data = [plat.loc[plat.line_name == ln, metric].dropna().values for ln in LINE_ORDER]
    pos = range(len(LINE_ORDER))
    bp = ax.boxplot(data, positions=list(pos), widths=0.55, whis=(0, 100),
                    showfliers=False, patch_artist=True, zorder=3)
    for i, ln in enumerate(LINE_ORDER):
        bp["boxes"][i].set(facecolor=LINE_COLOR[ln], edgecolor="#2A2A2A",
                           linewidth=0.9, alpha=1.0, zorder=3)
    for med in bp["medians"]:
        med.set(color="black", linewidth=1.8, zorder=4)
    for el in ("whiskers", "caps"):
        for art in bp[el]:
            art.set(color="#2A2A2A", linewidth=1.0)

    for i, ln in enumerate(LINE_ORDER):
        scol = f"{metric}_median" if f"{metric}_median" in stops else f"{metric}_mean"
        sv = stops.loc[stops.line_name == ln, scol].dropna().values
        jit = np.random.default_rng(i).uniform(-0.15, 0.15, len(sv))
        ax.scatter(np.full(len(sv), i) + jit, sv, s=14, color="black",
                   alpha=0.9, linewidths=0, zorder=6)

    ax.set_xlim(-0.6, len(LINE_ORDER) - 0.4)
    ax.set_ylim(0, ymax)
    ax.set_xticks(list(pos))
    ax.set_xticklabels([l.replace("Hammersmith & City", "H&C") for l in LINE_ORDER],
                       fontfamily=SERIF, fontsize=11)
    ax.set_ylabel(ylabel, fontfamily=SERIF, fontsize=12)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.spines["left"].set_linewidth(0.8)
    ax.spines["bottom"].set_linewidth(0.8)
    ax.tick_params(length=3)
    ax.grid(False)


fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(8.4, 8.8), sharex=True)
panel(ax1, "pm25", "PM$_{2.5}$  (µg m$^{-3}$)", 320)
panel(ax2, "pm10", "PM$_{10}$  (µg m$^{-3}$)", 430)

ax1.set_title("Platform PM$_{2.5}$ and PM$_{10}$ by line",
              fontfamily=SERIF, fontsize=15, pad=12, loc="left")

handle = plt.Line2D([0], [0], marker="o", color="black", lw=0, alpha=0.9,
                    markersize=6, label="per-stop median")
ax1.legend(handles=[handle], loc="upper right", frameon=False,
           fontsize=8.5, handlelength=1.0, borderpad=0.5)

fig.text(0.012, 0.012,
         "Background bands: UK Daily Air Quality Index (DAQI) 24-hour thresholds "
         "(DEFRA); PM$_{2.5}$ and PM$_{10}$ use separate band tables.",
         fontsize=7.2, color="#6A655F")

fig.tight_layout(rect=[0, 0.03, 0.94, 1])
os.makedirs("visualisation/figures", exist_ok=True)
fig.savefig("visualisation/figures/fig_perline_boxplot.pdf")
fig.savefig("visualisation/figures/fig_perline_boxplot.png", dpi=300)
print("saved fig_perline_boxplot.pdf / .png")

