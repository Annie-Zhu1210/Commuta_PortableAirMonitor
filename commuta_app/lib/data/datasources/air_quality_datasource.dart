import '../models/air_quality_reading.dart';

/// Abstract interface for all air quality data sources.
/// The rest of the app talks only to this interface — never to a
/// concrete implementation directly. This means swapping MockManager
/// for BLEManager later requires no changes outside this file's consumers.
abstract class AirQualityDataSource {
  /// Stream of live readings as they arrive (every ~10 seconds).
  Stream<AirQualityReading> subscribeToLiveReadings();

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