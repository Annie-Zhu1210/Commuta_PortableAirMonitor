"""
Per-station PM2.5 profiles for the two lines examined in detail
(within-line evidence: platform environment, not line, drives exposure).

Two separate figures, in the stem style of the reference example:
    visualisation/figures/Jubilee_per_station.{pdf,png}
    visualisation/figures/H&C_per_station.{pdf,png}

Reads : data/analysis/commuta_analysis.csv
Each station: grey stem = pooled median platform PM2.5 (both sessions);
baseline dot coloured by platform environment (regime). Stations are in
route order.
"""
import os
import re
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
a["ts"] = pd.to_datetime(a["timestamp"])
plat = a[a.location_type == "platform"].copy()

# platform-environment palette (green -> red = increasing exposure severity)
REGIME_COLOR = {
    "open_air":           "#8FB08E",
    "full_psd":           "#7FA8C9",
    "partially_open":     "#E0C067",
    "train_height_psd":   "#D98E5A",
    "underground_no_psd": "#B24738",
}
REGIME_LABEL = {
    "open_air": "Open-air",
    "full_psd": "Full-height PSD",
    "partially_open": "Partially enclosed",
    "train_height_psd": "Platform-height PSD",
    "underground_no_psd": "Enclosed, no PSD",
}
REGIME_SEVERITY = ["open_air", "full_psd", "partially_open",
                   "train_height_psd", "underground_no_psd"]

WHO_24H = 15.0
NAME_FIX = {"King's Cross St. Pancras": "King's Cross St P."}


def clean_name(n):
    n = re.sub(r"\s*\(.*?\)", "", n)          # drop "(H&C Line)" / "(Circle Line)"
    n = n.replace("-Underground", "").strip()
    return NAME_FIX.get(n, n)


def route_order(line, seg):
    d = plat[(plat.line_name == line) & (plat.segment_id == seg)]
    return d.sort_values(["source_file", "sequence_number"])["station_id"].drop_duplicates().tolist()


def per_station_fig(line, seg, line_color, outfile, ymax=100):
    order = route_order(line, seg)
    d = plat[plat.line_name == line]
    g = d.groupby("station_id").agg(
        station_name=("station_name", "first"),
        platform_regime=("platform_regime", "first"),
        pm25_med=("pm25", "median"),
    ).reindex(order)

    x = np.arange(len(g))
    fig, ax = plt.subplots(figsize=(0.62 * len(g) + 2.4, 4.8))

    # grey stems
    for xi, v in zip(x, g["pm25_med"].values):
        ax.plot([xi, xi], [0, v], color="#8C877F", lw=2.4, solid_capstyle="round",
                zorder=2)
    # line-coloured baseline
    ax.axhline(0, color=line_color, lw=3.0, zorder=3)
    # WHO reference
    ax.axhline(WHO_24H, color="#6A655F", lw=0.9, ls=(0, (4, 3)), zorder=1)
    ax.text(len(g) - 0.5, WHO_24H, "  WHO 24-h (15)", va="center", ha="left",
            fontsize=7.5, color="#6A655F", clip_on=False)
    # baseline dots coloured by platform environment
    for xi, reg in zip(x, g["platform_regime"].values):
        ax.scatter(xi, 0, s=110, color=REGIME_COLOR[reg], edgecolor="#2A2A2A",
                   linewidth=0.8, zorder=4)

    ax.set_ylim(-3, ymax)
    ax.set_xlim(-0.7, len(g) - 0.3)
    ax.set_xticks(x)
    ax.set_xticklabels([clean_name(n) for n in g["station_name"]],
                       rotation=45, ha="right", fontfamily=SERIF, fontsize=9.5)
    ax.set_ylabel("Platform PM$_{2.5}$  (µg m$^{-3}$)", fontfamily=SERIF, fontsize=12)
    ax.set_title(f"{line} — platform PM$_{{2.5}}$ by station (route order)",
                 fontfamily=SERIF, fontsize=14, loc="left", pad=10)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.spines["left"].set_linewidth(0.8)
    ax.spines["bottom"].set_visible(False)
    ax.tick_params(axis="x", length=0)
    ax.tick_params(axis="y", length=3)
    ax.grid(False)

    # legend: platform environments present, in severity order
    present = [r for r in REGIME_SEVERITY if r in set(g["platform_regime"])]
    handles = [plt.Line2D([0], [0], marker="o", color=REGIME_COLOR[r], lw=0,
               markeredgecolor="#2A2A2A", markeredgewidth=0.8, markersize=9,
               label=REGIME_LABEL[r]) for r in present]
    ax.legend(handles=handles, title="Platform environment", loc="upper right",
              frameon=False, fontsize=8.5, title_fontsize=9, handletextpad=0.4)

    fig.tight_layout()
    os.makedirs("visualisation/figures", exist_ok=True)
    fig.savefig(f"visualisation/figures/{outfile}.pdf")
    fig.savefig(f"visualisation/figures/{outfile}.png", dpi=300)
    plt.close(fig)
    print(f"saved {outfile}: {len(g)} stations")


# Jubilee: use the Bond Street -> Stratford session (S04) for west->east order
per_station_fig("Jubilee", "S04", (135/255, 142/255, 152/255), "Jubilee_per_station")
# H&C: Paddington -> Liverpool Street (S09)
per_station_fig("Hammersmith & City", "S09", (215/255, 153/255, 176/255), "H&C_per_station")