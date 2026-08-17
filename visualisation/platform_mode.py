"""
Fig 4.1b — Platform PM2.5 by platform environment (pooled across all lines).

The mechanism figure: a standard box plot (five-number summary: min, Q1,
median, Q3, max) of platform PM2.5 for each platform-environment class,
ordered along the enclosure gradient. Overlaid points are per-stop medians
(the analytical unit). Boxes coloured by platform environment, matching the
per-station figures.

Reads : data/analysis/commuta_analysis.csv
        data/analysis/commuta_stops.csv
Writes: visualisation/figures/fig_platform_mode.{pdf,png}
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

# order along the enclosure gradient (ascending median exposure)
REGIME_ORDER = ["open_air", "full_psd", "train_height_psd",
                "partially_open", "underground_no_psd"]
REGIME_COLOR = {
    "open_air":           "#8FB08E",
    "full_psd":           "#7FA8C9",
    "partially_open":     "#E0C067",
    "train_height_psd":   "#D98E5A",
    "underground_no_psd": "#B24738",
}
REGIME_LABEL = {
    "open_air": "Open-air",
    "full_psd": "Full-height\nPSD",
    "train_height_psd": "Platform-height\nPSD",
    "partially_open": "Partially\nenclosed",
    "underground_no_psd": "Enclosed,\nno PSD",
}
WHO_24H = 15.0
YMAX = 320

fig, ax = plt.subplots(figsize=(8.0, 5.4))

data = [plat.loc[plat.platform_regime == r, "pm25"].dropna().values for r in REGIME_ORDER]
pos = range(len(REGIME_ORDER))
bp = ax.boxplot(data, positions=list(pos), widths=0.58, whis=(0, 100),
                showfliers=False, patch_artist=True, zorder=3)
for i, r in enumerate(REGIME_ORDER):
    bp["boxes"][i].set(facecolor=REGIME_COLOR[r], edgecolor="#2A2A2A",
                       linewidth=0.9, alpha=1.0, zorder=3)
for med in bp["medians"]:
    med.set(color="black", linewidth=1.8, zorder=4)
for el in ("whiskers", "caps"):
    for art in bp[el]:
        art.set(color="#2A2A2A", linewidth=1.0)

# per-stop medians overlaid (solid black)
for i, r in enumerate(REGIME_ORDER):
    sv = stops.loc[stops.platform_regime == r, "pm25_median"].dropna().values
    jit = np.random.default_rng(i).uniform(-0.16, 0.16, len(sv))
    ax.scatter(np.full(len(sv), i) + jit, sv, s=14, color="black",
               alpha=0.9, linewidths=0, zorder=6)
    # stop count annotation just above each box's maximum
    ax.text(i, data[i].max() + 7, f"n={len(sv)}", ha="center", va="bottom",
            fontsize=8, color="#6A655F")

# WHO reference
ax.axhline(WHO_24H, color="#6A655F", lw=0.9, ls=(0, (4, 3)), zorder=1)
ax.text(len(REGIME_ORDER) - 0.5, WHO_24H, "  WHO 24-h (15)", va="center",
        ha="left", fontsize=7.5, color="#6A655F", clip_on=False)

ax.set_xlim(-0.6, len(REGIME_ORDER) - 0.4)
ax.set_ylim(0, YMAX)
ax.set_xticks(list(pos))
ax.set_xticklabels([REGIME_LABEL[r] for r in REGIME_ORDER],
                   fontfamily=SERIF, fontsize=10.5)
ax.set_ylabel("Platform PM$_{2.5}$  (µg m$^{-3}$)", fontfamily=SERIF, fontsize=12)
ax.set_title("Platform PM$_{2.5}$ by platform environment (all lines pooled)",
             fontfamily=SERIF, fontsize=14, loc="left", pad=10)
for s in ("top", "right"):
    ax.spines[s].set_visible(False)
ax.spines["left"].set_linewidth(0.8)
ax.spines["bottom"].set_linewidth(0.8)
ax.tick_params(axis="x", length=0)
ax.tick_params(axis="y", length=3)
ax.grid(False)

handle = plt.Line2D([0], [0], marker="o", color="black", lw=0, alpha=0.9,
                    markersize=6, label="per-stop median")
ax.legend(handles=[handle], loc="upper left", frameon=False, fontsize=8.5,
          handlelength=1.0, borderpad=0.5)

fig.tight_layout()
os.makedirs("visualisation/figures", exist_ok=True)
fig.savefig("visualisation/figures/fig_platform_mode.pdf")
fig.savefig("visualisation/figures/fig_platform_mode.png", dpi=300)
print("saved fig_platform_mode.pdf / .png")