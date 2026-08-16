#!/usr/bin/env python3
"""
Commuta data-processing pipeline
================================
Reads the untouched raw exports in  data/raw/  together with two hand-maintained
metadata files in  data/metadata/  and writes a single tidy, analysis-ready file
to  data/clean/commuta_clean.csv .

The script is fully deterministic: re-running it on the same raw + metadata always
produces the same clean file. Raw files are never modified. Sensor values are never
altered, rounded, or corrected here (humidity correction, rounding, etc. belong in
the downstream analysis notebook). The ONLY things this script changes are:

  1. station tags      - fixed per corrections.csv (clear_tag / set_tag / drop)
  2. which rows survive - only rows inside a journey in segments.csv are kept
  3. added labels       - line_name, group, direction, segment_id, day,
                          location_type, source_file

Keying is (source_file, sequence_number): file 1's sequence numbers overlap file 2's,
so sequence_number alone is not unique across files.

Usage:  python process_data.py
"""
import os, glob, sys
import pandas as pd

HERE   = os.path.dirname(os.path.abspath(__file__))
RAW    = os.path.join(HERE, "raw")
META   = os.path.join(HERE, "metadata")
CLEAN  = os.path.join(HERE, "clean")

# Canonical raw schema (file 1 lacks DPS_tem; it is filled with NA on load).
RAW_COLS = ["sequence_number","timestamp","pm1","pm25","pm10","co2","temperature",
            "DPS_tem","humidity","pressure","pressure_change_pa_per_sec","nox","tvoc",
            "voc_raw","nox_raw","source_flag","station_id","station_name",
            "line_id","line_name","gps_lat","gps_lng"]

# Output column order: identity + labels first, then raw sensor values.
OUT_COLS = ["source_file","day","sequence_number","timestamp","segment_id","line_name",
            "group","direction","location_type","station_id","station_name",
            "pm1","pm25","pm10","co2","temperature","DPS_tem","humidity","pressure",
            "pressure_change_pa_per_sec","nox","tvoc","voc_raw","nox_raw",
            "source_flag","gps_lat","gps_lng"]


def log(msg=""): print(msg)


def load_raw(path):
    df = pd.read_csv(path)
    # normalise schema: add any missing canonical column as NA (handles file 1's DPS_tem)
    for c in RAW_COLS:
        if c not in df.columns:
            df[c] = pd.NA
    # the app never populated line_id / line_name at row level; assert and drop them,
    # the authoritative line comes from segments.csv
    for c in ["line_id", "line_name"]:
        if df[c].notna().any():
            log(f"  WARNING: {os.path.basename(path)} has non-empty {c} - overwritten by route label")
    return df


def expand(meta_rows):
    """yield (start, end) inclusive from a metadata frame with start_seq/end_seq."""
    for _, r in meta_rows.iterrows():
        yield int(r.start_seq), int(r.end_seq), r


def main():
    segments    = pd.read_csv(os.path.join(META, "segments.csv"))
    corrections = pd.read_csv(os.path.join(META, "corrections.csv"),
                             dtype={"station_id": "string", "station_name": "string"})
    os.makedirs(CLEAN, exist_ok=True)

    out_frames = []
    log("="*72)
    log("COMMUTA CLEANING REPORT")
    log("="*72)

    for path in sorted(glob.glob(os.path.join(RAW, "*.csv"))):
        fn  = os.path.basename(path)
        day = fn.split("_")[3]                     # YYYYMMDD from filename (robust to bad RTC)
        day = f"{day[:4]}-{day[4:6]}-{day[6:8]}"
        df  = load_raw(path).set_index("sequence_number", drop=False).sort_index()
        seg_f = segments[segments.source_file == fn]
        cor_f = corrections[corrections.source_file == fn]
        n_raw = len(df)

        # ---- 1. apply corrections -------------------------------------------------
        drop_seqs = set()
        for a, b, r in expand(cor_f):
            present = [s for s in range(a, b + 1) if s in df.index]
            if r.action == "clear_tag":
                df.loc[present, ["station_id", "station_name"]] = [pd.NA, pd.NA]
            elif r.action == "set_tag":
                df.loc[present, "station_name"] = r.station_name
                df.loc[present, "station_id"]   = r.station_id
            elif r.action == "drop":
                drop_seqs.update(present)
            missing = [s for s in range(a, b + 1) if s not in df.index]
            if missing:
                log(f"  note [{fn}] {r.action} {a}-{b}: sample(s) not recorded, skipped: {missing}")

        # ---- 2. assign segment membership ----------------------------------------
        df["segment_id"] = pd.NA
        df["line_name"]  = pd.NA
        df["group"]      = pd.NA
        df["direction"]  = pd.NA
        for a, b, r in expand(seg_f):
            m = (df.index >= a) & (df.index <= b)
            df.loc[m, "segment_id"] = r.segment_id
            df.loc[m, "line_name"]  = r.line_name
            df.loc[m, "group"]      = r.group
            df.loc[m, "direction"]  = r.direction

        # ---- 3. keep only rows inside a journey (and not explicitly dropped) ------
        keep = df["segment_id"].notna() & ~df.index.isin(drop_seqs)
        dropped = df[~keep]
        kept    = df[keep].copy()

        # dropped-row report (this is what surfaces stray rows / note typos)
        drng = _to_ranges(sorted(dropped.index))
        log(f"\n{fn}  ({day})")
        log(f"  raw rows: {n_raw}   kept: {len(kept)}   dropped: {len(dropped)}")
        log(f"  dropped ranges (startup / interchange / explicit): "
            + ", ".join(f"{a}-{b}" if a != b else f"{a}" for a, b in drng))

        # ---- 4. derived labels ----------------------------------------------------
        kept["source_file"]   = fn
        kept["day"]           = day
        kept["location_type"] = kept["station_name"].where(kept["station_name"].isna(),
                                                            "platform")
        kept["location_type"] = kept["location_type"].where(kept["station_name"].notna(),
                                                            "in_train")

        # per-segment dwell order (integrity eyeball)
        for _, r in seg_f.iterrows():
            sub = kept[kept.segment_id == r.segment_id].sort_index()
            order = _collapse([n for n in sub["station_name"] if pd.notna(n)])
            reps  = [s for s in set(order) if order.count(s) > 1]
            tail  = f"   <-- REPEAT {reps}" if reps else ""
            log(f"    {r.segment_id} [{r.group}] {r.line_name} {r.direction}: "
                f"{len(order)} stops{tail}")

        out_frames.append(kept)

    # ---- 5. combine + defensive dedup --------------------------------------------
    allrows = pd.concat(out_frames, ignore_index=True)
    before  = len(allrows)
    # keep 'live' over 'buffered' when the same (source_file, sequence) appears twice
    allrows["_pref"] = (allrows["source_flag"] == "live").astype(int)
    allrows = (allrows.sort_values(["source_file", "sequence_number", "_pref"],
                                   ascending=[True, True, False])
                       .drop_duplicates(["source_file", "sequence_number"], keep="first")
                       .drop(columns="_pref"))
    deduped = before - len(allrows)
    if deduped:
        log(f"\n  defensive dedup removed {deduped} re-transmitted duplicate row(s)")

    allrows = allrows[OUT_COLS].sort_values(["source_file", "sequence_number"])
    out = os.path.join(CLEAN, "commuta_clean.csv")
    allrows.to_csv(out, index=False)

    log("\n" + "="*72)
    log(f"WROTE {out}")
    log(f"  {len(allrows)} rows | platform: "
        f"{(allrows.location_type=='platform').sum()} | "
        f"in_train: {(allrows.location_type=='in_train').sum()}")
    log(f"  key (source_file, sequence_number) unique: "
        f"{not allrows.duplicated(['source_file','sequence_number']).any()}")
    log("  rows per line x group:")
    tab = allrows.groupby(["line_name","group"]).size()
    for (ln, g), n in tab.items():
        log(f"    {ln:<20} {g:<8} {n}")


def _to_ranges(seqs):
    out = []
    for s in seqs:
        if out and s == out[-1][1] + 1:
            out[-1][1] = s
        else:
            out.append([s, s])
    return out


def _collapse(names):
    out = []
    for n in names:
        if not out or out[-1] != n:
            out.append(n)
    return out


if __name__ == "__main__":
    main()