# ======================================================================
# Dwell time vs platform PM2.5 — stop-level table + Spearman correlation
# Reproduces the figures used in Section 4.3 from the clean dataset.
# Uses ONLY pandas + numpy (no scipy). Read-only on commuta_clean.csv.
# ======================================================================
import pandas as pd
from pathlib import Path

# ---- Locate the clean CSV regardless of where this is run from ------
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
REPO = CLEAN_PATH.parents[2]                      # .../Commuta_PortableAirMonitor

df = pd.read_csv(CLEAN_PATH)
df["ts"] = pd.to_datetime(df["timestamp"], utc=True)
# Chronological order within each file (sequence_number resets between files).
df = df.sort_values(["source_file", "sequence_number"]).reset_index(drop=True)

# ---- Build the stop-level table -------------------------------------
# A "platform stop" = a maximal run of consecutive platform rows with the
# same station tag within one segment. A new stop begins whenever
# location_type or station_name changes.
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
            "segment_id": seg,
            "line_name":  s["line_name"].iloc[0],
            "group":      s["group"].iloc[0],
            "station_name": station,
            "n_samples":  len(s),
            # dwell = span of the stop + one sampling interval (~10 s/row)
            "dwell_s":    (s["ts"].max() - s["ts"].min()).total_seconds() + 10,
            "pm25_mean":  s["pm25"].mean(),
            "pm25_median": s["pm25"].median(),
            "pm10_mean":  s["pm10"].mean(),
        })
stops = pd.DataFrame(stops)

# Save the stop-level table into the auditable pipeline.
out = REPO / "data" / "analysis" / "commuta_stops.csv"
out.parent.mkdir(parents=True, exist_ok=True)
stops.to_csv(out, index=False)

# ---- Spearman without scipy -----------------------------------------
# Spearman's rho IS the Pearson correlation of the ranked values. pandas'
# .rank() (average ranks for ties) and default .corr() (Pearson) are both
# numpy-based, so this needs no scipy and matches scipy.stats.spearmanr.
# Computed at STOP level (n stops): 10 s rows within a stop are autocorrelated,
# so row-level n would mislead. Stops are still nested within sessions, so treat
# this descriptively — the rho and its (in)consistency across lines are the point.
def spearman(a, b):
    return a.rank().corr(b.rank())

rho = spearman(stops["dwell_s"], stops["pm25_mean"])
pear = stops["dwell_s"].corr(stops["pm25_mean"])   # default = Pearson (no scipy)
print(f"clean file: {CLEAN_PATH}")
print(f"n stops = {len(stops)}")
print(f"Overall  Spearman rho = {rho:+.3f}   [Pearson r = {pear:+.3f}]")
print("Within-line Spearman (dwell_s vs pm25_mean):")
for line, gp in stops.groupby("line_name"):
    print(f"  {line:20s} n = {len(gp):2d}   rho = {spearman(gp['dwell_s'], gp['pm25_mean']):+.2f}")

