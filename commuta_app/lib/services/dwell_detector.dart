import 'dart:async';
import 'package:geolocator/geolocator.dart';

import '../core/constants/map_constants.dart';
import '../data/models/air_quality_reading.dart';
import '../data/models/geo_tagged_reading.dart';

/// Events emitted by [DwellDetector] for the map view to apply
/// to its marker set.
sealed class DwellEvent {
  const DwellEvent();
}

/// Plot a new single-reading marker at the given position.
class AddSingleEvent extends DwellEvent {
  final AirQualityReading reading;
  final Position position;
  const AddSingleEvent({required this.reading, required this.position});
}

/// Remove the single markers for [readings] and replace them with
/// one collection marker at [anchorPosition].
class CollapseToCollectionEvent extends DwellEvent {
  final String collectionId;
  final List<AirQualityReading> readings;
  final Position anchorPosition;
  const CollapseToCollectionEvent({
    required this.collectionId,
    required this.readings,
    required this.anchorPosition,
  });
}

/// Append [reading] to an existing collection. No new marker is
/// added — the listener only needs to update the collection's
/// stored readings (and re-render the icon if the dominant band
/// shifted).
class AppendToCollectionEvent extends DwellEvent {
  final String collectionId;
  final AirQualityReading reading;
  const AppendToCollectionEvent({
    required this.collectionId,
    required this.reading,
  });
}

/// Tracks the user's recent positions and decides when a run of
/// stationary readings should collapse into a single collection
/// marker.
///
/// Behaviour:
///   - Each cluster's anchor is the position of its first reading.
///   - Readings within [radiusMetres] of the anchor extend the cluster.
///   - Once the cluster spans [durationSeconds] of readings, it
///     collapses: all its singles are removed, one collection marker
///     is placed at the anchor.
///   - Subsequent in-range readings append to that collection
///     (no new marker; data only).
///   - A reading outside the radius closes the current cluster
///     (its singles or collection stay on the map) and opens a
///     fresh one.
///
/// Readings without a usable [Position] are ignored — they're not
/// plottable on the map either (see [GeoTaggedReading.isPlottable]).
class DwellDetector {
  final double radiusMetres;
  final int durationSeconds;

  // Broadcast so future listeners (e.g. a debug overlay) can subscribe.
  final StreamController<DwellEvent> _controller =
      StreamController<DwellEvent>.broadcast();
  Stream<DwellEvent> get events => _controller.stream;

  // Active cluster state.
  Position? _anchor;
  DateTime? _clusterStart;
  final List<AirQualityReading> _clusterReadings = [];
  String? _activeCollectionId;

  int _collectionCounter = 0;

  DwellDetector({
    this.radiusMetres = MapConstants.dwellRadiusMetres,
    this.durationSeconds = MapConstants.dwellDurationSeconds,
  });

  /// Feed a geo-tagged reading into the detector. The detector
  /// uses [GeoTaggedReading.position] directly (which the map view
  /// has already gated by accuracy before reaching us).
  void addReading(GeoTaggedReading geoReading) {
    final position = geoReading.position;
    if (position == null) return;
    final reading = geoReading.reading;

    // First reading after start or after a cluster reset.
    if (_anchor == null) {
      _startNewCluster(reading, position);
      _controller.add(AddSingleEvent(reading: reading, position: position));
      return;
    }

    final dist = Geolocator.distanceBetween(
      _anchor!.latitude,
      _anchor!.longitude,
      position.latitude,
      position.longitude,
    );

    // Left the cluster — close the old one (its singles or collection
    // remain on the map untouched) and open a fresh cluster.
    if (dist > radiusMetres) {
      _startNewCluster(reading, position);
      _controller.add(AddSingleEvent(reading: reading, position: position));
      return;
    }

    // Within radius — extend the active cluster.
    _clusterReadings.add(reading);

    // Already a collection — silent append.
    if (_activeCollectionId != null) {
      _controller.add(AppendToCollectionEvent(
        collectionId: _activeCollectionId!,
        reading: reading,
      ));
      return;
    }

    // Still pre-collapse — emit as a single, then check the threshold.
    _controller.add(AddSingleEvent(reading: reading, position: position));

    final elapsed = reading.timestamp.difference(_clusterStart!);
    if (elapsed.inSeconds >= durationSeconds) {
      final id = 'col_${++_collectionCounter}';
      _activeCollectionId = id;
      _controller.add(CollapseToCollectionEvent(
        collectionId: id,
        readings: List.of(_clusterReadings),
        anchorPosition: _anchor!,
      ));
    }
  }

  /// Clears all active cluster state without closing the event stream.
  ///
  /// Called by the Google Map view on midnight rollover: yesterday's
  /// markers are wiped, and the detector must not treat the first
  /// reading of the new day as a continuation of a cluster whose
  /// anchor belongs to yesterday. The collection counter is
  /// deliberately *not* reset — collection IDs (and therefore marker
  /// and notifier keys) stay unique across day boundaries within a
  /// single app session.
  void reset() {
    _anchor = null;
    _clusterStart = null;
    _clusterReadings.clear();
    _activeCollectionId = null;
  }

  void _startNewCluster(AirQualityReading reading, Position position) {
    _anchor = position;
    _clusterStart = reading.timestamp;
    _clusterReadings
      ..clear()
      ..add(reading);
    _activeCollectionId = null;
  }

  void dispose() {
    _controller.close();
  }
}