class AirQualityReading {
  final DateTime timestamp;
  final double pm1;
  final double pm25;
  final double pm10;
  final double co2;

  /// SCD40 temperature in °C. Used as the ambient reading in the
  /// UI (info-sheet, home card, etc.), and by anything else that
  /// reads a single "temperature" value. Note the SCD40 has an
  /// internal NDIR heater and self-heats a degree or two above
  /// ambient once the enclosure warms up — this is a known bias
  /// documented in the dissertation's methodology chapter, where
  /// [dps368TempC] is used as the ambient reference for comparison.
  final double temperature;

  final double humidity;
  final double pressure;
  final double? pressureChangePaPerSec; // null on first reading (no prior to compare)

  /// SGP41 processed VOC index (1..500). Null on the mock, and null
  /// during CONDITIONING on the real device (the NOx pixel is still
  /// warming up and the processed indices aren't meaningful yet).
  final double? tvoc;

  /// SGP41 processed NOx index (1..500). Same nulling behaviour as
  /// [tvoc].
  final double? nox;

  /// SGP41 raw VOC ticks (uint16 on the wire). Populated on every
  /// real-device sample including during CONDITIONING — the raw
  /// ticks are diagnostically useful even while the NOx pixel warms
  /// up. Null on the mock. Persisted primarily for the dissertation's
  /// JSON export; not surfaced in the UI.
  final int? vocRaw;

  /// SGP41 raw NOx ticks (uint16 on the wire). Reads 0 during
  /// CONDITIONING on the real device (a valid measurement, not
  /// garbage), non-zero once warmed up. Null on the mock. Persisted
  /// primarily for the dissertation's JSON export; not surfaced in
  /// the UI.
  final int? noxRaw;

  /// Per-install random identifier stamped onto every v3 sample by
  /// the firmware, regenerated only on a full flash erase. Combined
  /// with [sequenceNumber] it forms the stable identity of a sample
  /// across reboots. Enforced as a unique key on `(bootEpoch,
  /// sequenceNumber)` via a UNIQUE INDEX at the DB layer alongside
  /// the pre-existing `(sequenceNumber, timestamp)` key (additive
  /// migration, Session 1 Decision 1).
  ///
  /// Nullable to accommodate two source paths that don't have a real
  /// firmware bootEpoch:
  ///   * Legacy pre-v3 rows already persisted to Drift — null after
  ///     the schema-v3 migration adds the column; SQLite treats null
  ///     values as never-equal in unique indexes so they don't
  ///     conflict with new v3 rows.
  ///   * Historically the mock left this null; the current mock
  ///     synthesises a stable ID at app start, so mock rows landing
  ///     from this build have a non-null value.
  final int? bootEpoch;

  /// DPS368 ambient temperature in °C. Reported by the DPS368
  /// (pressure sensor with an ambient temp channel), which has no
  /// internal heater and so isn't subject to the SCD40's
  /// self-heating drift. Captured in v3 primarily for the CSV
  /// export's `DPS_tem` column — the methodology chapter compares
  /// SCD40 vs DPS368 temperatures to characterise the SCD40 bias.
  /// Not currently surfaced in the UI.
  ///
  /// Nullable because pre-v3 samples don't carry this field and the
  /// mock leaves it null (sensor "unavailable" on mock).
  final double? dps368TempC;

  /// Raw battery cell voltage in millivolts (uint16 on the wire),
  /// sampled by the ESP32 ADC via a resistor divider. Persisted on
  /// every v3 sample so the app-side state-of-charge calculation
  /// (Phase 4b, Session 3) can smooth and look this up against an
  /// empirically-derived OCV table, replacing the current
  /// firmware-computed `battery_pct` used by the live gauge.
  ///
  /// Also the source column for the one-off battery
  /// characterisation CSV export — during the discharge run the
  /// device buffers every 10-second sample to flash, and on the
  /// next reconnect those rows land in Drift with `vbatMv`
  /// populated; the export queries `WHERE vbatMv IS NOT NULL` and
  /// writes a compact CSV so the OCV table can be derived from
  /// real data.
  ///
  /// Nullable because pre-v3 samples don't carry this field and the
  /// mock leaves it null.
  final int? vbatMv;

  final String sourceFlag; // 'live' | 'buffered' | 'mock'
  final int sequenceNumber;
  final String? stationId;
  final String? lineId;
  final double? gpsLat;
  final double? gpsLng;

  const AirQualityReading({
    required this.timestamp,
    required this.pm1,
    required this.pm25,
    required this.pm10,
    required this.co2,
    required this.temperature,
    required this.humidity,
    required this.pressure,
    this.pressureChangePaPerSec,
    this.tvoc,
    this.nox,
    this.vocRaw,
    this.noxRaw,
    this.bootEpoch,
    this.dps368TempC,
    this.vbatMv,
    required this.sourceFlag,
    required this.sequenceNumber,
    this.stationId,
    this.lineId,
    this.gpsLat,
    this.gpsLng,
  });
}