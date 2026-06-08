import '../../data/models/air_quality_reading.dart';
import 'daqi_utils.dart';

/// Placeholder overall AQI computation for the Map screen.
///
/// Returns the worst DAQI band between PM2.5 and PM10, and shows the
/// PM2.5 µg/m³ value (rounded) inside the marker.
///
/// This is a *temporary* stand-in until Annie's commuter-weighted
/// algorithm is researched and implemented. When that lands, replace
/// the bodies of [computeBand] and [displayValue] — every marker on
/// the Map screen flows through these two functions, so no other code
/// needs to change.
class PlaceholderOverallAqi {
  PlaceholderOverallAqi._();

  /// Worst-banded [DaqiInfo] between PM2.5 and PM10.
  /// (Higher [DaqiBand.index] means worse air quality.)
  static DaqiInfo computeBand(AirQualityReading reading) {
    final pm25 = DaqiUtils.forPm25(reading.pm25);
    final pm10 = DaqiUtils.forPm10(reading.pm10);
    return pm25.band.index >= pm10.band.index ? pm25 : pm10;
  }

  /// Number shown inside the marker. Currently the rounded PM2.5 µg/m³.
  static int displayValue(AirQualityReading reading) {
    return reading.pm25.round();
  }
}