"""
Builds the derived analysis dataset and the stop-level table from the
untouched clean CSV. The clean CSV is never overwritten.

Inputs
    data/clean/commuta_clean.csv      (3,156 rows, untouched raw truth)
    data/analysis/station_regime.csv  (5-class platform taxonomy)

Outputs
    data/analysis/commuta_analysis.csv   (row-level, lean schema)
    data/analysis/commuta_stops.csv      (stop-level table)

Design rules honoured:
  - line identity comes from `line_name` in the data, never from station_name
  - no humidity correction (raw PM is the sole dataset); `humidity` kept only
    so the RH range can be reported
  - full sensor precision retained; rounding happens only at the reporting stage
"""
import pandas as pd

CLEAN = "data/clean/commuta_clean.csv"
REGIME = "data/analysis/station_regime.csv"
OUT_ANALYSIS = "data/analysis/commuta_analysis.csv"
OUT_STOPS = "data/analysis/commuta_stops.csv"

SAMPLE_INTERVAL_S = 10  # nominal cadence; added to each stop span for dwell


# ---------------------------------------------------------------- 1. load
df = pd.read_csv(CLEAN)
reg = pd.read_csv(REGIME)

# ---------------------------------------------------------------- 2. join regime
# platform_regime is station-specific -> join on (line_name, station_id),
# so it is only populated for platform rows (in_train rows have no station_id).
df = df.merge(
    reg[["line_name", "station_id", "platform_regime"]],
    on=["line_name", "station_id"],
    how="left",
)
# line_regime is a line property -> assign to every row from a line-level lookup.
line_lookup = reg[["line_name", "line_regime"]].drop_duplicates()
assert line_lookup["line_name"].is_unique, "line_regime is not 1:1 with line_name"
df = df.merge(line_lookup, on="line_name", how="left")

# ---------------------------------------------------------------- 3. no humidity correction
# (intentionally nothing here; raw PM is analysed as-is — see §3.3)

# ---------------------------------------------------------------- 4. write lean analysis CSV
schema = [
    "source_file", "sequence_number", "day", "timestamp",
    "segment_id", "line_name", "group", "direction", "location_type",
    "station_id", "station_name", "platform_regime", "line_regime",
    "pm1", "pm25", "pm10", "humidity", "co2",
]
analysis = df[schema].copy()
analysis.to_csv(OUT_ANALYSIS, index=False)

# ---------------------------------------------------------------- 5. stop-level table
# A platform stop = maximal run of consecutive platform rows with the same
# station tag, within a single segment. A new run starts whenever segment,
# location_type, or station changes.
d = df.sort_values(["segment_id", "source_file", "sequence_number"]).copy()
d["ts"] = pd.to_datetime(d["timestamp"])
d["_stationkey"] = d["station_id"].fillna("__IN_TRAIN__")

change = (
    (d["segment_id"] != d["segment_id"].shift())
    | (d["location_type"] != d["location_type"].shift())
    | (d["_stationkey"] != d["_stationkey"].shift())
)
d["_block"] = change.cumsum()

platform = d[d["location_type"] == "platform"].copy()

stops = (
    platform.groupby("_block")
    .agg(
        segment_id=("segment_id", "first"),
        line_name=("line_name", "first"),
        group=("group", "first"),
        station_id=("station_id", "first"),
        station_name=("station_name", "first"),
        platform_regime=("platform_regime", "first"),
        line_regime=("line_regime", "first"),
        n_samples=("pm25", "size"),
        ts_first=("ts", "min"),
        ts_last=("ts", "max"),
        pm25_mean=("pm25", "mean"),
        pm25_median=("pm25", "median"),
        pm25_peak=("pm25", "max"),
        pm10_mean=("pm10", "mean"),
        co2_mean=("co2", "mean"),
    )
    .reset_index(drop=True)
)
stops["dwell_s"] = (stops["ts_last"] - stops["ts_first"]).dt.total_seconds() + SAMPLE_INTERVAL_S

stops = stops[[
    "segment_id", "line_name", "group", "station_id", "station_name",
    "platform_regime", "line_regime", "dwell_s", "n_samples",
    "pm25_mean", "pm25_median", "pm25_peak", "pm10_mean", "co2_mean",
]]
stops.to_csv(OUT_STOPS, index=False)

print(f"analysis rows : {len(analysis)}")
print(f"platform rows : {(analysis.location_type=='platform').sum()}")
print(f"in_train rows : {(analysis.location_type=='in_train').sum()}")
print(f"stops         : {len(stops)}")
