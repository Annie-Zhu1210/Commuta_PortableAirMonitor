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
  final double? nox;     // nullable — SGP41 not yet wired up
  final double? tvoc;    // nullable — SGP41 not yet wired up
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
    this.nox,
    this.tvoc,
    required this.sourceFlag,
    required this.sequenceNumber,
    this.stationId,
    this.lineId,
    this.gpsLat,
    this.gpsLng,
  });
}