import '../models/air_quality_reading.dart';

/// Abstract interface for all air quality data sources.
/// The rest of the app talks only to this interface — never to a
/// concrete implementation directly. This means swapping MockManager
/// for BLEManager later requires no changes outside this file's consumers.
abstract class AirQualityDataSource {
  /// Stream of live readings as they arrive (every ~10 seconds).
  ///
  /// UI surfaces that show "the current reading" (home dashboard, live
  /// gauges, etc.) subscribe here. Buffered catch-up records are
  /// deliberately kept off this stream so a reconnect sync doesn't
  /// flood consumers with stale samples masquerading as live ones.
  Stream<AirQualityReading> subscribeToLiveReadings();

  /// Stream of readings arriving from the device's flash buffer during
  /// a catch-up sync. Semantically old data with reconstructed
  /// timestamps and `sourceFlag = 'buffered'`.
  ///
  /// Consumed by `ReadingsRepository` for persistence only. UI must
  /// **not** subscribe here — buffered records represent past
  /// conditions, not present ones, and rendering them alongside live
  /// readings would misrepresent the state of the current commute.
  ///
  /// Mock data sources return `Stream<AirQualityReading>.empty()`; no
  /// synthetic buffered data is generated.
  Stream<AirQualityReading> subscribeToBufferedReadings();

  /// Fetch historical readings between [from] and [to].
  Future<List<AirQualityReading>> getHistoricalReadings({
    required DateTime from,
    required DateTime to,
  });

  /// Latest single reading (convenience accessor for the home dashboard).
  Future<AirQualityReading?> getLatestReading();

  /// Clean up any open streams or connections.
  void dispose();
}