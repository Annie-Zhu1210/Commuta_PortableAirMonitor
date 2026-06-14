import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../data/datasources/air_quality_datasource.dart';
import '../data/models/air_quality_reading.dart';
import 'location_service.dart';
import 'readings_repository.dart';

/// Watches the user's location, decides which TfL station (if any) they
/// are currently at, and tags every subsequent reading to that station's
/// collection until they leave.
///
/// Phase 5 Step 1 (this file) is the skeleton: it owns the current-station
/// notifier and an events stream, and wires up its two subscriptions
/// (readings + GPS position). The decision logic itself — the 100 m / 60 s
/// dwell rule, nearest-station lookup, departure handling, event emission —
/// lands in Step 2. The two handlers below are deliberately empty for now.
///
/// There is no in-memory store of readings here. Every reading is already
/// persisted to SQLite by [ReadingsRepository] the moment it arrives, and
/// classified readings have their station written through
/// [ReadingsRepository.classifyReading]. The database is the single source
/// of truth; this service only decides *which* station to write.
///
/// Lifecycle is owned by `AppServices`:
///   • [start] runs once at app startup. It subscribes to the shared
///     readings stream (no permission needed), so the classification
///     pathway is live from launch.
///   • [startLocationTracking] runs once the app has a UI context where a
///     permission prompt is acceptable (the main scaffold). It secures
///     location permission, then subscribes to the GPS position stream.
///     Kept separate from [start] because permission must never be
///     requested in `main()`, before any UI exists.
class StationClassificationService {
  StationClassificationService(this._dataSource, this._readingsRepository);

  final AirQualityDataSource _dataSource;

  // Unused until Step 2, when _handleReading calls classifyReading on it.
  // Taken in the constructor now so the AppServices wiring stays stable.
  // ignore: unused_field
  final ReadingsRepository _readingsRepository;

  StreamSubscription<AirQualityReading>? _readingSub;
  StreamSubscription<Position>? _positionSub;

  /// The station the user is currently classified to, or null if none.
  /// Drives the sage halo on the TfL map. Mutated only inside this
  /// service; exposed read-only via [currentStationId].
  final ValueNotifier<String?> _currentStationId = ValueNotifier(null);

  /// Read-only view of the currently classified station ID. The TfL map
  /// listens to this to paint (or hide) the halo.
  ValueListenable<String?> get currentStationId => _currentStationId;

  /// Broadcast stream of "entered"/"left" station events. Nothing is
  /// emitted until Step 2 adds the dwell logic — the contract is defined
  /// now so downstream consumers (e.g. journey reconstruction later) have
  /// something stable to build against.
  final StreamController<ClassificationEvent> _eventController =
      StreamController<ClassificationEvent>.broadcast();

  Stream<ClassificationEvent> get events => _eventController.stream;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Subscribe to the shared readings stream. No location permission
  /// required. Idempotent — repeat calls are no-ops.
  void start() {
    _readingSub ??=
        _dataSource.subscribeToLiveReadings().listen(_handleReading);
  }

  /// Secure location permission, then subscribe to the GPS position
  /// stream. Call once from the main scaffold. Idempotent — repeat calls
  /// are no-ops.
  ///
  /// Returns the permission result so the caller can surface a message if
  /// location was refused. If refused, classification simply stays dormant
  /// — readings still persist unclassified via the repository.
  Future<LocationPermissionResult> startLocationTracking() async {
    if (_positionSub != null) {
      return LocationPermissionResult.granted;
    }
    final result = await LocationService.ensurePermission();
    if (result != LocationPermissionResult.granted) {
      return result;
    }
    _positionSub =
        LocationService.positionStream().listen(_handlePositionUpdate);
    return result;
  }

  // ── Handlers (logic lands in Step 2) ───────────────────────────────────

  /// Decide which station the user is at, update [_currentStationId], and
  /// emit the appropriate [ClassificationEvent]. Empty until Step 2.
  void _handlePositionUpdate(Position position) {
    // Step 2: nearest-station lookup within 100 m, 60 s dwell before
    // confirming entry, small hysteresis on departure, event emission.
  }

  /// Tag an incoming reading to the current station, if one is set.
  /// Empty until Step 2.
  void _handleReading(AirQualityReading reading) {
    // Step 2: if _currentStationId.value != null, call
    // _readingsRepository.classifyReading(reading: ..., stationId: ...).
  }

  // ── Teardown ────────────────────────────────────────────────────────────

  /// Release resources. Called by `AppServices.dispose()`.
  Future<void> dispose() async {
    await _readingSub?.cancel();
    await _positionSub?.cancel();
    _readingSub = null;
    _positionSub = null;
    await _eventController.close();
    _currentStationId.dispose();
  }
}

/// Base type for events emitted by
/// [StationClassificationService.events].
///
/// Sealed so a `switch` over the event type is exhaustive — mirrors the
/// `DwellEvent` pattern already used in `DwellDetector`.
sealed class ClassificationEvent {
  const ClassificationEvent({required this.stationId, required this.at});

  /// The station this event concerns.
  final String stationId;

  /// When the event occurred, on the app clock (per the
  /// app-as-source-of-truth time model).
  final DateTime at;
}

/// The user has settled at [stationId] — the dwell threshold was met.
/// Readings from now on are classified to this station until a matching
/// [StationExitedEvent].
final class StationEnteredEvent extends ClassificationEvent {
  const StationEnteredEvent({required super.stationId, required super.at});
}

/// The user has left [stationId]'s radius. Subsequent readings are
/// unclassified until the next [StationEnteredEvent].
final class StationExitedEvent extends ClassificationEvent {
  const StationExitedEvent({required super.stationId, required super.at});
}