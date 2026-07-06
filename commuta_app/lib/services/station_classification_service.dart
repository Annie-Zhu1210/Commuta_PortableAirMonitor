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
/// Phase 5 Step 1 (skeleton) established the notifier + events contract.
/// Session 1 (manual override, this pass) adds the sticky-override API:
///   • [setStationManually] and [clearManualStation] for UI-driven tagging
///   • [manualOverride] listenable so the chip badge can react to source
///     flips even when [currentStationId] doesn't change
///   • [_handleReading] now persists via [ReadingsRepository.classifyReading]
///     whenever [_currentStationId] is set — manual and (later) auto share
///     the same write path
///
/// Phase 5 Step 2 (Session 2) will add the 100 m / 60 s dwell rule to
/// [_handlePositionUpdate]. That handler MUST honour the manual-override
/// silence contract (see the note in the handler body).
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
  final ReadingsRepository _readingsRepository;

  StreamSubscription<AirQualityReading>? _readingSub;
  StreamSubscription<Position>? _positionSub;

  /// The station the user is currently classified to, or null if none.
  /// Drives the sage halo on the TfL map. Mutated only inside this
  /// service; exposed read-only via [currentStationId].
  final ValueNotifier<String?> _currentStationId = ValueNotifier(null);

  /// Line associated with the currently tagged station, if any. Written
  /// to the DB alongside `stationId` via [ReadingsRepository.classifyReading].
  ///
  /// Session 1: always `null` for manual picks — the picker doesn't ask
  /// the user to pick a line, per Decision C.1. The API keeps `lineId`
  /// optional so a future picker enhancement (or auto-classification in
  /// Session 2) can populate it.
  String? _currentLineId;

  /// Whether the current tag was set explicitly by the user (manual)
  /// or inferred by dwell logic (auto). Session 1 only ever produces
  /// manual tags; Session 2 introduces auto and must respect the
  /// sticky-override contract (see [_handlePositionUpdate]).
  final ValueNotifier<bool> _manualOverride = ValueNotifier(false);

  /// Read-only view of the currently classified station ID. The TfL map
  /// listens to this to paint (or hide) the halo.
  ValueListenable<String?> get currentStationId => _currentStationId;

  /// Read-only view of the manual-override flag. The chip badge listens
  /// to this in combination with [currentStationId] so it re-renders
  /// even in the auto→manual same-station case where [currentStationId]
  /// stays constant but the badge flips.
  ValueListenable<bool> get manualOverride => _manualOverride;

  /// Convenience synchronous accessor for [manualOverride].value.
  /// Callers that need to rebuild on changes should listen to
  /// [manualOverride] instead.
  bool get isManualOverride => _manualOverride.value;

  /// Broadcast stream of "entered"/"left" station events.
  ///
  /// Session 1 emits these on manual set / clear / switch. Session 2
  /// will emit them from the dwell logic in [_handlePositionUpdate].
  /// Events are deliberately source-agnostic — a consumer reconstructing
  /// a journey doesn't care whether a station was tagged manually or
  /// automatically, only that the user was there between T1 and T2.
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

  // ── Manual override API (Session 1) ────────────────────────────────────

  /// Sets [stationId] as the currently tagged station via explicit user
  /// action (the picker, a tap-a-dot in a later session, etc.).
  ///
  /// Behaviour:
  ///   • First-time set from null → emits [StationEnteredEvent] for
  ///     the new station.
  ///   • Switch to a different station (regardless of previous source)
  ///     → emits [StationExitedEvent] for the old station, then
  ///     [StationEnteredEvent] for the new one.
  ///   • Same station already tagged → no exit/enter events; only the
  ///     [manualOverride] flag flips (auto → manual case) or nothing
  ///     changes at all (manual → same manual). The user's physical
  ///     location hasn't changed, so downstream consumers see a
  ///     continuous dwell.
  ///
  /// Once set, this override is sticky: [_handlePositionUpdate] (Session 2)
  /// will not clear or overwrite it. Call [clearManualStation] to release.
  void setStationManually(String stationId, {String? lineId}) {
    final previousStationId = _currentStationId.value;
    _currentLineId = lineId;

    // Same station: no exit/enter events. Just flip the source flag if
    // needed (covers auto → manual same-station transitions).
    if (previousStationId == stationId) {
      if (!_manualOverride.value) {
        _manualOverride.value = true;
      }
      return;
    }

    // Different station: exit the old (if any), enter the new.
    final now = DateTime.now();
    if (previousStationId != null) {
      _eventController.add(
        StationExitedEvent(stationId: previousStationId, at: now),
      );
    }
    _manualOverride.value = true;
    _currentStationId.value = stationId;
    _eventController.add(
      StationEnteredEvent(stationId: stationId, at: now),
    );
  }

  /// Clears the current manual tag. No-op if no manual tag is set
  /// (including when an auto tag is set — auto clearance in Session 2
  /// will need its own path; see the handoff note).
  ///
  /// Emits a [StationExitedEvent] for the cleared station and drops
  /// [_currentStationId] to null. Session 2 will additionally reset
  /// the dwell timer here so auto starts a fresh 60-second window from
  /// the next position update.
  void clearManualStation() {
    if (!_manualOverride.value) return;

    final previousStationId = _currentStationId.value;
    _manualOverride.value = false;
    _currentLineId = null;
    _currentStationId.value = null;

    if (previousStationId != null) {
      _eventController.add(
        StationExitedEvent(stationId: previousStationId, at: DateTime.now()),
      );
    }

    // Step 2 hook: reset dwell-timer state here so the next
    // position update starts a fresh 60-second window and auto
    // does not immediately re-tag the same station.
  }

  // ── Handlers ───────────────────────────────────────────────────────────

  /// Position handler. Empty for Session 1 — Session 2 owns this.
  ///
  /// IMPORTANT FOR SESSION 2: When [_manualOverride.value] is `true`, this
  /// handler must NOT mutate [_currentStationId], must NOT emit events, and
  /// must NOT clear the manual tag. The sticky-override contract says the
  /// dwell rule "still runs internally" — it may keep the dwell timer warm
  /// so a subsequent [clearManualStation] can hand off cleanly — but its
  /// output is suppressed.
  ///
  /// Suggested shape:
  /// ```dart
  /// void _handlePositionUpdate(Position position) {
  ///   // Update dwell state regardless, so it's warm when manual clears.
  ///   _updateDwellState(position);
  ///   if (_manualOverride.value) return;
  ///   // ... nearest-station lookup, dwell threshold check,
  ///   //     _currentStationId mutation, event emission ...
  /// }
  /// ```
  void _handlePositionUpdate(Position position) {
    // Step 2 lands here.
  }

  /// Tag an incoming reading to the current station, if one is set.
  /// Runs for both manual and auto tagging paths — the source doesn't
  /// matter, only whether a station is currently set.
  void _handleReading(AirQualityReading reading) {
    final stationId = _currentStationId.value;
    if (stationId == null) return;

    final lineId = _currentLineId;
    // Fire-and-forget. The raw row is already persisted separately by
    // [ReadingsRepository.start]'s subscription, so an error here just
    // means this reading stays unclassified — recoverable in Phase 7
    // via manual reclassification.
    unawaited(
      _readingsRepository
          .classifyReading(
            reading: reading,
            stationId: stationId,
            lineId: lineId,
          )
          .catchError((Object _) {}),
    );
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
    _manualOverride.dispose();
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

/// The user has settled at [stationId] — the dwell threshold was met,
/// or the user manually tagged this station.
/// Readings from now on are classified to this station until a matching
/// [StationExitedEvent].
final class StationEnteredEvent extends ClassificationEvent {
  const StationEnteredEvent({required super.stationId, required super.at});
}

/// The user has left [stationId]'s radius, or manually cleared /
/// switched away from this station. Subsequent readings are unclassified
/// until the next [StationEnteredEvent].
final class StationExitedEvent extends ClassificationEvent {
  const StationExitedEvent({required super.stationId, required super.at});
}