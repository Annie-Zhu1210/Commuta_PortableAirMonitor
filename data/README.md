# Commuta dataset

Personal PM-exposure measurements collected on six London Underground lines with the
Commuta portable air-quality monitor. This folder holds the raw exports, the
transformation that produces the analysis-ready dataset, and that dataset itself.

## Provenance and reproducibility

The raw exports in `raw/` are the CSV files produced by the Commuta app, byte-for-byte,
and are **never edited**. All cleaning is done by `process_data.py`, driven entirely by
two small, human-readable metadata files. Anyone can regenerate the clean dataset from
the untouched raw data with a single command:

```
python process_data.py
```

Because every change is expressed as an explicit, auditable rule in the metadata files
(not a manual edit to a data cell), the raw -> clean transformation is fully
reproducible. This is the integrity guarantee: the clean dataset was not hand-assembled.

## Folder layout

```
data/
├── raw/                     five app exports, untouched
├── metadata/
│   ├── segments.csv         one row per journey: sequence range -> line, group, direction
│   └── corrections.csv      station-tag fixes (clear_tag / set_tag / drop)
├── clean/
│   └── commuta_clean.csv    output of process_data.py
├── process_data.py          the pipeline
└── README.md
```

## What cleaning does — and does not — change

Cleaning changes only three things:

1. **Station tags** are corrected per `corrections.csv`.
   - `clear_tag` removes a stale/false GPS auto-tag (a previous station briefly
     re-detected while in transit).
   - `set_tag` restores the correct tag on rows that arrived as buffered data and so
     missed the platform tag that was selected in the app.
2. **Row inclusion**: only rows inside a journey defined in `segments.csv` are kept.
   Everything else (device warm-up before the first station, interchange walks between
   lines) is dropped. `process_data.py` prints every dropped range so each exclusion is
   visible and intentional.
3. **Labels are added**: `line_name`, `group` (busier / quieter, from observed
   conditions), `direction`, `segment_id`, `day`, `location_type`, `source_file`.

Cleaning **never alters sensor values**. PM, CO2, temperature, humidity, pressure and
gas readings are carried through at full precision exactly as recorded. Humidity
correction (Crilley et al.), any rounding, and all analysis are done downstream in the
analysis notebook, so raw research values are preserved in the clean file too.

## Key notes

- **Keying** is `(source_file, sequence_number)`. File 1's sequence numbers overlap
  file 2's (the counter was reset by an early code change), so sequence number alone is
  not unique across files.
- **File 1** was recorded before the code change that added the DPS368 secondary-
  temperature column, so its `DPS_tem` is blank; its `temperature` column is SCD40, the
  same source as every other file, so temperature is directly comparable throughout.
- **`day`** is taken from the filename date, not the row timestamp, because file 1's
  clock was set during a home test of the app.
- **`location_type`** is `platform` where a (corrected) station tag is present and
  `in_train` for the untagged stretches between stations — both are valid measurements.

## Columns in `commuta_clean.csv`

`source_file, day, sequence_number, timestamp, segment_id, line_name, group, direction,
location_type, station_id, station_name, pm1, pm25, pm10, co2, temperature, DPS_tem,
humidity, pressure, pressure_change_pa_per_sec, nox, tvoc, voc_raw, nox_raw,
source_flag, gps_lat, gps_lng`
