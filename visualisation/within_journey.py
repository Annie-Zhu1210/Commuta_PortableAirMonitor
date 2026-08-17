"""
Fig 4.2 — Within-journey PM2.5 time series.

Two separate figures, one per line, each a single quieter-session journey:
    visualisation/figures/northern_within_journey.{pdf,png}    (S05, deep tube)
    visualisation/figures/elizabeth_within_journey.{pdf,png}   (S10, full PSD)

The point of the pair is the platform-vs-carriage contrast by ventilation
regime, made visible along the journey:
  - Northern (enclosed, no PSD): PM2.5 stays high the whole journey; the
    in-carriage stretches are no lower than the platforms, so being inside the
    train gives no cleaner air than standing on the platform.
  - Elizabeth (full-height PSDs): PM2.5 is low and rises only at the enclosed
    stations; the in-carriage stretches drop below the platforms, so the air
    inside the train is cleaner than on the platform; the single open-air stop
    (Custom House) is near-zero.

Shaded bands  = time on a platform, coloured by station environment (regime).
Unshaded gaps = time in the carriage, between stations.

Reads : data/analysis/commuta_analysis.csv
"""
import os
import re
import numpy as np
import pandas as pd
import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm
from matplotlib.patches import Patch
from matplotlib.lines import Line2D

# ---------------------------------------------------------------- fonts
FONT_DIR = os.path.join(os.path.dirname(__file__), "..", "fonts")
FONT_DIR_LOCAL = os.path.join(os.path.dirname(__file__), "fonts")
for d in (FONT_DIR, FONT_DIR_LOCAL):
    for f in ["Fraunces-Display.ttf", "Inter-Regular.ttf", "Inter-SemiBold.ttf"]:
        p = os.path.join(d, f)
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

SAMPLE_INTERVAL_S = 10

# platform-environment palette (shared with the rest of the figure suite)
REGIME_COLOR = {
    "open_air":           "#8FB08E",
    "full_psd":           "#7FA8C9",
    "partially_open":     "#E0C067",
    "train_height_psd":   "#D98E5A",
    "underground_no_psd": "#B24738",
}
REGIME_LABEL = {
    "open_air":           "Open-air",
    "full_psd":           "Full-height PSD",
    "partially_open":     "Partially enclosed",
    "train_height_psd":   "Platform-height PSD",
    "underground_no_psd": "Enclosed, no PSD",
}
LINE_COLOR = {
    "Northern":  "#4A4642",   # dark charcoal trace (reads over pale bands)
    "Elizabeth": "#1A1A1A",   # black trace, per request
}
WHO_24H = 15.0
NAME_FIX = {
    "Tottenham Court Road": "Tottenham Ct Rd",
    "King's Cross St. Pancras": "King's Cross",
    "Paddington (H&C Line)-Underground": "Paddington",
    "Edgware Road (Circle Line)": "Edgware Road",
}


def clean_name(n):
    n = NAME_FIX.get(n, n)
    n = re.sub(r"\s*\(.*?\)", "", n)
    return n.replace("-Underground", "").strip()


def runs(g):
    """Yield contiguous runs of the same (location_type, station) as
    (location_type, regime, name, x_start_min, x_end_min)."""
    g = g.sort_values(["source_file", "sequence_number"]).reset_index(drop=True)
    g["t"] = (g["ts"] - g["ts"].min()).dt.total_seconds() / 60.0
    key = g["location_type"].astype(str) + "|" + g["station_id"].astype(str)
    grp = (key != key.shift()).cumsum()
    out = []
    for _, r in g.groupby(grp):
        loc = r["location_type"].iloc[0]
        reg = r["platform_regime"].iloc[0] if loc == "platform" else None
        nm = clean_name(str(r["station_name"].iloc[0])) if loc == "platform" else None
        x0 = r["t"].iloc[0]
        x1 = r["t"].iloc[-1] + SAMPLE_INTERVAL_S / 60.0
        out.append((loc, reg, nm, x0, x1))
    return g, out


def within_journey_fig(seg, ymax, ytick, outfile, med_pos=("right", "top")):
    g = a[a.segment_id == seg].copy()
    line = g["line_name"].iloc[0]
    grp = g["group"].iloc[0]
    g, rr = runs(g)

    plat_med = g.loc[g.location_type == "platform", "pm25"].median()
    train_med = g.loc[g.location_type == "in_train", "pm25"].median()

    fig, ax = plt.subplots(figsize=(9.6, 5.2))

    # background bands: platform (regime colour) / in-carriage (faint grey)
    regimes_present = []
    for loc, reg, nm, x0, x1 in rr:
        if loc == "platform":
            ax.axvspan(x0, x1, color=REGIME_COLOR[reg], alpha=0.30, lw=0, zorder=0)
            if reg not in regimes_present:
                regimes_present.append(reg)
        else:
            ax.axvspan(x0, x1, color="#000000", alpha=0.035, lw=0, zorder=0)

    # WHO reference
    ax.axhline(WHO_24H, color="#6A655F", lw=0.9, ls=(0, (4, 3)), zorder=1)
    ax.text(g["t"].max() * 0.998, WHO_24H, "WHO 24-h (15)", va="bottom", ha="right",
            fontsize=7.5, color="#6A655F")

    # PM2.5 trace + faint sample points
    ax.plot(g["t"], g["pm25"], color=LINE_COLOR[line], lw=1.7, zorder=4,
            solid_capstyle="round")
    ax.scatter(g["t"], g["pm25"], s=6, color=LINE_COLOR[line], alpha=0.35,
               linewidths=0, zorder=5)

    # station labels: vertical, hung from the top on a white chip (out of the data)
    for loc, reg, nm, x0, x1 in rr:
        if loc != "platform":
            continue
        ax.text((x0 + x1) / 2, ymax * 0.985, nm, rotation=90, ha="center",
                va="top", fontsize=7.5, family=SERIF, color="#3A3733", zorder=7,
                bbox=dict(boxstyle="round,pad=0.15", fc="white", ec="none", alpha=0.72))

    # median annotation box (the refuge / no-refuge point, in numbers)
    txt = (f"Platform median  {plat_med:.0f}\n"
           f"In-carriage median  {train_med:.0f}  µg m$^{{-3}}$")
    hx = 0.985 if med_pos[0] == "right" else 0.015
    vy = med_pos[1]
    ax.text(hx, vy, txt, transform=ax.transAxes, ha=med_pos[0], va="top",
            fontsize=8.5, family=SERIF, color="#3A3733",
            bbox=dict(boxstyle="round,pad=0.45", fc="white", ec="#C9C4BC", lw=0.8),
            zorder=8)

    ax.set_xlim(0, g["t"].max())
    ax.set_ylim(0, ymax)
    ax.set_yticks(np.arange(0, ymax + 1, ytick))
    ax.set_xlabel("Elapsed journey time (minutes)", family=SERIF, fontsize=11.5)
    ax.set_ylabel("PM$_{2.5}$  (µg m$^{-3}$)", family=SERIF, fontsize=12)
    ax.set_title(f"{line} line — within-journey PM$_{{2.5}}$ ({grp} session)",
                 family=SERIF, fontsize=14, loc="left", pad=10)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.spines["left"].set_linewidth(0.8)
    ax.spines["bottom"].set_linewidth(0.8)
    ax.tick_params(length=3)
    ax.grid(False)

    # legend below the plot (never collides with the trace)
    handles = [Patch(fc=REGIME_COLOR[r], ec="none", alpha=0.55,
                     label=f"Platform — {REGIME_LABEL[r]}") for r in regimes_present]
    handles.append(Patch(fc="#E3DED6", ec="none", label="In carriage"))
    handles.append(Line2D([0], [0], color=LINE_COLOR[line], lw=1.7, label="PM$_{2.5}$"))
    ax.legend(handles=handles, loc="upper center", bbox_to_anchor=(0.5, -0.14),
              ncol=len(handles), frameon=False, fontsize=8.2,
              handlelength=1.3, borderpad=0.4, columnspacing=1.6)

    fig.tight_layout(rect=[0, 0.02, 1, 1])
    os.makedirs("visualisation/figures", exist_ok=True)
    fig.savefig(f"visualisation/figures/{outfile}.pdf")
    fig.savefig(f"visualisation/figures/{outfile}.png", dpi=300)
    plt.close(fig)
    print(f"saved {outfile}  (platform median {plat_med:.1f}, in-carriage {train_med:.1f})")


# Northern: deep tube; PM stays high the whole journey, carriage no cleaner than platform
within_journey_fig("S05", ymax=320, ytick=80, outfile="northern_within_journey",
                   med_pos=("right", 0.235))
# Elizabeth: full PSD; low, rising only at enclosed stations, carriage air cleaner than platform
within_journey_fig("S10", ymax=70, ytick=10, outfile="elizabeth_within_journey",
                   med_pos=("right", 0.60))