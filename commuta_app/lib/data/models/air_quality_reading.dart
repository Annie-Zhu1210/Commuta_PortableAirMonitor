class AirQualityReading {
  final DateTime timestamp;
  final double pm1;
  final double pm25;
  final double pm10;
  final double co2;
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
    required this.sourceFlag,
    required this.sequenceNumber,
    this.stationId,
    this.lineId,
    this.gpsLat,
    this.gpsLng,
  });
}