# Visualisation & Analysis

Analysis scripts and figures for the first real-world study run with Commuta: **how London Underground line types and platform ventilation designs affect commuters' PM2.5 exposure** (MSc dissertation case study). The Commuta system itself is general-purpose — this folder is where its data was put to work on one specific question.

All scripts read from the reproducible dataset in [`../data/`](../data) (see that folder's README for the raw → clean pipeline) and write figures into [`figures/`](figures).

## Setup

```bash
pip install -r requirements.txt
```

(pandas, matplotlib, openpyxl, jupyter — no scipy needed; correlations are computed with pandas/numpy only.)

## Run order

**Step 0 must run first** — it builds the derived analysis tables every plotting script reads:

```bash
python step0_dataprep.py
```

This reads `data/clean/commuta_clean.csv` (never modified) and `data/analysis/station_regime.csv` (the 5-class platform environment taxonomy), and writes `data/analysis/commuta_analysis.csv` (row-level) and `data/analysis/commuta_stops.csv` (stop-level — the analytical unit).

After that, each plotting script is independent and can be run in any order from the repo root.

## Script → figure map

| Script | Output (in `figures/`) | What it shows |
|---|---|---|
| `perline_boxplot.py` | `fig_perline_boxplot.{pdf,png}` | **Fig 4.1a** — Platform PM2.5 by Underground line: box plots per line (TfL line colours), per-stop medians overlaid, UK DAQI thresholds as background bands |
| `platform_mode.py` | `fig_platform_mode.{pdf,png}` | **Fig 4.1b** — the mechanism figure: platform PM2.5 by platform-environment class, ordered along the enclosure gradient, pooled across lines |
| `perstation.py` | `Jubilee_per_station.{pdf,png}`, `H&C_per_station.{pdf,png}` | Per-station PM2.5 stem profiles for the two lines examined in detail — within-line evidence that platform environment, not line, drives exposure |
| `within_journey.py` | `northern_within_journey.{pdf,png}`, `elizabeth_within_journey.{pdf,png}` | **Fig 4.2** — within-journey PM2.5 time series contrasting a deep tube line (no platform screen doors) with a fully screened modern line |
| `plot_4_3_dwell_vs_pm25.py` | `fig_4_3_dwell_vs_pm25.{pdf,png}` | **Fig 4.3** — platform dwell time vs stop-mean PM2.5, with Spearman correlations (self-contained; rebuilds its own stop table) |
| `dwell_spearman_cell.py` | (console/table output) | The stop-level table and Spearman correlation behind Fig 4.3, as a standalone reproducible cell |

## Other contents

- [`notebooks/analysis.ipynb`](notebooks/analysis.ipynb) — exploratory analysis notebook.
- [`exhibition_data/`](exhibition_data) — a single-journey Excel export prepared for exhibition display.
- `commuta_pm25_co2.{png,svg}` and the `*_busier.*` variants in `figures/` — additional comparison figures.

## Reproducing from scratch

The full chain, starting from untouched raw device exports:

```bash
cd data && python process_data.py     # raw → clean (rule-driven, auditable)
cd ..
python visualisation/step0_dataprep.py       # clean → analysis tables
python visualisation/perline_boxplot.py      # then any figure scripts, any order
```
