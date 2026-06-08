import 'package:geolocator/geolocator.dart';
import '../../core/constants/map_constants.dart';
import 'air_quality_reading.dart';

/// Pairs an [AirQualityReading] with the phone's GPS [Position] at the
/// moment the reading arrived.
///
/// The device itself has no notion of location, so geo-tagging is done
/// app-side. This wrapper is consumed by the Map screen — it isn't part
/// of the persisted data model.
class GeoTaggedReading {
  final AirQualityReading reading;

  /// The phone's position at the moment the reading was received.
  /// May be null if no GPS fix had been obtained yet.
  final Position? position;

  const GeoTaggedReading({
    required this.reading,
    this.position,
  });

  /// True when there's a position and its accuracy is within the
  /// configured threshold ([MapConstants.gpsAccuracyThresholdMetres]).
  /// Markers should only be drawn when this is true.
  bool get isPlottable {
    final p = position;
    if (p == null) return false;
    return p.accuracy <= MapConstants.gpsAccuracyThresholdMetres;
  }
}