import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../core/constants/map_constants.dart';
import '../core/utils/daqi_utils.dart';
import '../data/datasources/air_quality_datasource.dart';
import '../data/models/air_quality_reading.dart';
import '../data/models/tfl_station.dart';
import 'location_service.dart';
import 'readings_repository.dart';
import 'tfl_map_data.dart';

/// Watches the user's location, decides which TfL station (if any) they
/// are currently at, and tags every subsequent reading to that station's
/// collection until they leave.
///
/// Phase 5 Step 1 (skeleton) established the notifier + events contract.
/// Session 1 (manual override) added the sticky-override API:
///   • [setStationManually] and [clearStation] for UI-driven tagging
///   • [manualOverride] listenable so the chip badge can react to source
///     flips even when [currentStationId] doesn't change
///   • [_handleReading] persists via [ReadingsRepository.classifyReading]
///     whenever [_currentStationId] is set — manual and auto share the
///     same write path
///
/// Phase 5 Step 2 (Session 2) adds the 100 m / 60 s dwell rule to
/// [_handlePositionUpdate]:
///   • Entry: nearest station within
///     [MapConstants.stationDwellRadiusMetres] becomes a dwell candidate;
///     once the user has stayed on the same candidate for
///     [MapConstants.stationDwellDurationSeconds], it is auto-tagged and a
///     [StationEnteredEvent] is emitted. A one-shot confirmation timer
///     covers the case where the OS suppresses position updates while the
///     user is stationary (Decision 7) — the 60 s rule means "60 s of
///     physical presence", not "60 s and a fresh fix happened to arrive".
///   • Departure: [MapConstants.stationDepartureStreakSize] consecutive
///     out-of-range fixes release the tag and emit a
///     [StationExitedEvent]. Departure is purely fix-driven — the
///     confirmation timer plays no part in it.
///   • Sticky override honoured throughout: while [manualOverride] is
///     set, the position handler is completely inert (Decision 3) — it
///     never mutates state, emits events, or keeps dwell warm.
///
/// Session 4 (visited-station colouring) adds a per-day, per-station
/// worst-PM-band summary exposed via [visitedStationsToday]. The TfL map
/// listens to this notifier and colours station dots accordingly:
///   • On [start], hydrates from the DB by scanning today's classified
///     readings and taking the worst [DaqiUtils.worstPmBand] per station.
///   • On each live classified reading, [_handleReading] updates the
///     entry for the current station if the new reading has a strictly
///     worse band. The map is monotonic within a day.
///   • Day rollover is caught by a periodic wall-clock check
///     ([_startPeriodicDayCheck]) that ticks every 60 s of monotonic
///     time and asks [_ensureVisitedStateIsForToday] whether the
///     wall-clock date has advanced. This replaces the earlier one-shot
///     midnight `Timer` because Dart `Timer` durations are monotonic —
///     advancing the system clock forward past midnight (or the OS
///     applying its own clock corrections) would not fire the one-shot
///     even in the foreground. The periodic check reads
///     `DateTime.now()` on every tick and rehydrates if the day has
///     changed. Worst-case visible delay after midnight is 60 s.
///   • As a belt-and-braces measure, [_handleReading] also fires
///     [_ensureVisitedStateIsForToday] on every incoming reading before
///     its stationId-null early return, so a reading arriving shortly
///     after midnight triggers rehydration immediately regardless of
///     the periodic tick, and — critically — the check still fires when
///     no station is currently tagged.
///
/// There is no in-memory store of readings here. Every reading is already
/// persisted to SQLite by [ReadingsRepository] the moment it arrives, and
/// classified readings have their station written through
/// [ReadingsRepository.classifyReading]. The database is the single source
/// of truth; this service only decides *which* station to write and
/// maintains derived views of the classified rows.
///
/// Lifecycle is owned by `AppServices`:
///   • [start] runs once at app startup. It subscribes to the shared
///     readings stream (no permission needed), so the classification
///     pathway is live from launch. Session 4 hydration and the periodic
///     day-check also kick off here — asynchronously so
///     `AppServices.init()` isn't blocked on the DB scan.
///   • [startLocationTracking] runs once the app has a UI context where a
///     permission prompt is acceptable (the main scaffold). It secures
///     location permission, loads the TfL station geometry (Decision 6 —
///     so auto-tagging works even if the TfL map screen is never opened),
///     then subscribes to the GPS position stream. Kept separate from
///     [start] because permission must never be requested in `main()`,
///     before any UI exists.
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
  /// Always `null` for manual picks (the picker doesn't ask the user to
  /// pick a line, per Decision C.1) and for auto tags (a station may
  /// serve several lines and dwell detection can't tell which the user
  /// is riding). The API keeps `lineId` optional so a future enhancement
  /// can populate it.
  String? _currentLineId;

  /// Whether the current tag was set explicitly by the user (manual)
  /// or inferred by dwell logic (auto). While `true`, the position
  /// handler is inert per the sticky-override contract
  /// (see [_handlePositionUpdate]).
  final ValueNotifier<bool> _manualOverride = ValueNotifier(false);

  // ── Dwell state (Session 2, Decision 2: inline private fields) ─────────

  /// The station currently being considered for auto-tagging, or null
  /// when there is no warm candidate.
  String? _dwellCandidateStationId;

  /// When [_dwellCandidateStationId] was first seen. Null whenever the
  /// candidate is null.
  DateTime? _dwellCandidateSince;

  /// Consecutive position fixes outside the tagged station's radius.
  /// Reaching [MapConstants.stationDepartureStreakSize] releases the tag.
  int _outOfRangeStreak = 0;

  /// One-shot timer that re-evaluates the dwell candidate when the full
  /// dwell duration has elapsed (Decision 7). Needed because geolocator's
  /// 5 m distance filter means the OS may deliver no further fixes while
  /// the user stands still — without this, a stationary user would never
  /// be auto-tagged. Cancelled whenever the candidate changes, the dwell
  /// state resets, or a manual tag is set.
  Timer? _dwellConfirmTimer;

  /// Most recent position fix received. Used by the confirmation timer
  /// and by [clearStation]'s dwell reseed, both of which may run when no
  /// fresh fix is available.
  Position? _lastPosition;

  // ── Visited-stations-today state (Session 4) ───────────────────────────
  // Derived view of the readings table: today's classified rows,
  // collapsed to the worst PM band per station. Rebuilt on [start], on
  // day rollover, and updated live on every classified reading.

  /// Mutable backing store keyed by Naptan station ID. Values are the
  /// worst [DaqiBand] observed at that station today across the three
  /// PM metrics (see [DaqiUtils.worstPmBand]). Updates are pushed to
  /// consumers via [_visitedStationsTodayNotifier] as unmodifiable
  /// snapshots so mutations here can never leak to the UI.
  final Map<String, DaqiBand> _visitedStationsToday = {};

  /// Immutable snapshot of [_visitedStationsToday] published to the UI.
  /// `ValueNotifier` fires on reference inequality — each publish
  /// assigns a fresh unmodifiable Map instance so listeners always see
  /// the update.
  final ValueNotifier<Map<String, DaqiBand>> _visitedStationsTodayNotifier =
      ValueNotifier(const <String, DaqiBand>{});

  /// The local-midnight [DateTime] the current snapshot corresponds to.
  /// Set at the end of [_hydrateAndMarkToday]; compared against
  /// `DateTime.now()` in [_ensureVisitedStateIsForToday] to detect day
  /// rollover regardless of monotonic vs. wall-clock time drift.
  DateTime? _visitedHydratedFor;

  /// Periodic timer that wakes every
  /// [_dayCheckIntervalSeconds] seconds of monotonic time and asks
  /// [_ensureVisitedStateIsForToday] whether the wall-clock date has
  /// advanced. Rehydrates when it has. This is intentionally a
  /// `Timer.periodic` rather than a one-shot fired at midnight because
  /// Dart `Timer` durations are monotonic — a one-shot scheduled at
  /// 23:55 for "5 minutes from now" doesn't fire if the system clock
  /// jumps forward past midnight, and doesn't fire reliably across iOS
  /// backgrounding either. The tick callback is cheap: one `DateTime`
  /// comparison and an early return when already hydrated for today.
  Timer? _dayCheckTimer;

  /// Guards against concurrent hydration when [start] races with the
  /// first live reading, or when several call sites hit the
  /// day-rollover check within the same rebuild window. Reset in the
  /// finally block of the caller.
  Future<void>? _hydrationFuture;

  /// How often the periodic wall-clock day-check ticks. 60 seconds is
  /// the trade-off between wasted work (the tick body is a two-field
  /// comparison and early return when hydrated) and the worst-case
  /// visible delay after midnight (60 s).
  static const int _dayCheckIntervalSeconds = 60;

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

  /// Read-only view of today's visited stations, keyed by Naptan station
  /// ID, with the worst observed PM band as the value. The TfL map
  /// listens to this to colour visited-station dots. Empty until
  /// hydration completes; clears at (or within a minute of) local
  /// midnight.
  ValueListenable<Map<String, DaqiBand>> get visitedStationsToday =>
      _visitedStationsTodayNotifier;

  /// Broadcast stream of "entered"/"left" station events.
  ///
  /// Emitted on manual set / clear / switch (Session 1) and by the dwell
  /// logic on auto entry / departure (Session 2). Events are deliberately
  /// source-agnostic — a consumer reconstructing a journey doesn't care
  /// whether a station was tagged manually or automatically, only that
  /// the user was there between T1 and T2.
  final StreamController<ClassificationEvent> _eventController =
      StreamController<ClassificationEvent>.broadcast();

  Stream<ClassificationEvent> get events => _eventController.stream;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Subscribe to the shared readings stream. No location permission
  /// required. Idempotent — repeat calls are no-ops.
  ///
  /// Session 4: also kicks off initial hydration of the
  /// visited-stations-today snapshot and starts the periodic
  /// wall-clock day-check. Both operations run asynchronously so
  /// `AppServices.init()` doesn't block on a DB scan; the map painter
  /// tolerates an empty snapshot until hydration completes.
  void start() {
    _readingSub ??=
        _dataSource.subscribeToLiveReadings().listen(_handleReading);
    unawaited(_ensureVisitedStateIsForToday());
    _startPeriodicDayCheck();
  }

  /// Secure location permission, then subscribe to the GPS position
  /// stream. Call once from the main scaffold. Idempotent — repeat calls
  /// are no-ops.
  ///
  /// Session 2 (Decision 6): station geometry is loaded here, before the
  /// first fix can arrive, so auto-classification works even if the TfL
  /// map screen is never opened. [TflMapData.load] is idempotent, so the
  /// map view's own call remains a harmless no-op.
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
    try {
      await TflMapData.instance.load();
    } catch (_) {
      // Asset load failed. Auto-classification stays dormant — the
      // position handler guards on [TflMapData.isLoaded] — and the TfL
      // map view's own load() call will retry and surface the error to
      // the user. Manual tagging via the picker is unaffected once a
      // later load succeeds.
    }
    _positionSub =
        LocationService.positionStream().listen(_handlePositionUpdate);
    return result;
  }

  // ── Manual override API (Session 1, clearance generalised Session 2) ───

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
  /// Once set, this override is sticky: [_handlePositionUpdate] will not
  /// clear or overwrite it. Call [clearStation] to release.
  ///
  /// Session 2 (Decision 3): setting a manual tag resets all dwell state,
  /// including the confirmation timer. Dwell stays inert for the whole
  /// manual period and starts completely fresh on [clearStation].
  void setStationManually(String stationId, {String? lineId}) {
    _resetDwellState();

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

  /// Clears the current tag — manual or auto — via explicit user action
  /// (the chip's ✕). Generalised from Session 1's `clearManualStation`
  /// per Decision 1: one method, one contract, one call site.
  ///
  /// Emits a [StationExitedEvent] for the cleared station (if any),
  /// drops [_currentStationId] to null, and clears [manualOverride].
  ///
  /// Dwell restarts fresh (Decision 3): the full
  /// [MapConstants.stationDwellDurationSeconds] must elapse before auto
  /// tags anything again — even the station just cleared. Because the OS
  /// may deliver no further fixes while the user stands still, the fresh
  /// window is seeded immediately from the last known position rather
  /// than waiting for the next fix (Decision 7).
  void clearStation() {
    final previousStationId = _currentStationId.value;
    _manualOverride.value = false;
    _currentLineId = null;
    _currentStationId.value = null;

    if (previousStationId != null) {
      _eventController.add(
        StationExitedEvent(stationId: previousStationId, at: DateTime.now()),
      );
    }

    _resetDwellState();
    _seedDwellFromLastPosition();
  }

  // ── Handlers ───────────────────────────────────────────────────────────

  /// Position handler — the dwell-based auto-detection core
  /// (Phase 5 Step 2).
  ///
  /// Sticky-override contract: when [_manualOverride] is `true`, this
  /// handler is completely inert (Decision 3). It records the fix in
  /// [_lastPosition] — so [clearStation] can seed a fresh dwell window —
  /// but never mutates [_currentStationId], never emits events, and does
  /// not keep dwell candidates warm. Dwell state was already reset when
  /// the manual tag was set.
  ///
  /// While auto-tagged, only departure is evaluated: the tagged station
  /// cannot be displaced by a nearby neighbour until the user has
  /// actually left its radius (3-fix rule) — see [_evaluateDeparture].
  void _handlePositionUpdate(Position position) {
    _lastPosition = position;

    if (_manualOverride.value) return;
    if (!TflMapData.instance.isLoaded) return;

    final taggedId = _currentStationId.value;
    if (taggedId != null) {
      _evaluateDeparture(position, taggedId);
    } else {
      _evaluateEntry(position);
    }
  }

  /// Tag an incoming reading to the current station, if one is set.
  /// Runs for both manual and auto tagging paths — the source doesn't
  /// matter, only whether a station is currently set.
  ///
  /// Session 4: fires [_ensureVisitedStateIsForToday] at the top —
  /// before the stationId-null early return — so day rollover is caught
  /// from the reading stream even when no station is currently tagged.
  /// The check is cheap when already hydrated (one comparison, one map
  /// lookup) and complements the periodic wall-clock check for
  /// immediate response.
  void _handleReading(AirQualityReading reading) {
    // Session 4: day-rollover check runs unconditionally. Fire-and-
    // forget; the periodic timer covers the case where no readings
    // arrive at all (device disconnected, app open but idle).
    unawaited(_ensureVisitedStateIsForToday());

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

    // Session 4: update the visited-stations-today snapshot with this
    // reading's worst PM band. Internally awaits the day-rollover
    // check so the update lands on the correct day's map.
    unawaited(_updateVisitedForReading(stationId, reading));
  }

  // ── Dwell logic (Session 2) ─────────────────────────────────────────────

  /// Entry evaluation: runs on each fix while no station is tagged.
  ///
  /// Nearest station within [MapConstants.stationDwellRadiusMetres]
  /// becomes (or remains) the dwell candidate. A different nearest
  /// station replaces the candidate and restarts the clock; no station
  /// in range clears the candidate entirely.
  void _evaluateEntry(Position position) {
    final nearest = _nearestStationWithin(
      position,
      MapConstants.stationDwellRadiusMetres,
    );

    if (nearest == null) {
      _resetDwellState();
      return;
    }

    if (nearest.id != _dwellCandidateStationId) {
      _startDwell(nearest.id);
      return;
    }

    // Same candidate: confirm if the dwell duration has elapsed. The
    // confirmation timer normally gets there first when the user is
    // stationary; this fix-driven path covers the moving-but-in-range
    // case and acts as a backstop.
    final since = _dwellCandidateSince;
    if (since != null &&
        DateTime.now().difference(since).inSeconds >=
            MapConstants.stationDwellDurationSeconds) {
      _confirmDwell();
    }
  }

  /// Departure evaluation: runs on each fix while auto-tagged. Purely
  /// fix-driven —
  /// [MapConstants.stationDepartureStreakSize] consecutive fixes outside
  /// the tagged station's radius release the tag (Decision 4: the streak
  /// is the whole rule; there is no separate departure radius).
  void _evaluateDeparture(Position position, String taggedId) {
    final station = TflMapData.instance.stationById(taggedId);
    if (station == null) {
      // Defensive: the tagged ID no longer resolves (should be
      // impossible — auto tags come from the same dataset). Release
      // the tag cleanly rather than getting stuck.
      _releaseAutoTag(taggedId);
      return;
    }

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      station.position.latitude,
      station.position.longitude,
    );

    if (distance <= MapConstants.stationDwellRadiusMetres) {
      _outOfRangeStreak = 0;
      return;
    }

    _outOfRangeStreak++;
    if (_outOfRangeStreak >= MapConstants.stationDepartureStreakSize) {
      _releaseAutoTag(taggedId);
    }
  }

  /// Releases the current auto tag: emits [StationExitedEvent], clears
  /// the notifier, and resets dwell state so entry evaluation starts
  /// cold from the next fix.
  void _releaseAutoTag(String stationId) {
    _currentLineId = null;
    _currentStationId.value = null;
    _eventController.add(
      StationExitedEvent(stationId: stationId, at: DateTime.now()),
    );
    _resetDwellState();
  }

  /// Starts (or restarts) the dwell clock for [stationId] and arms the
  /// one-shot confirmation timer (Decision 7).
  void _startDwell(String stationId) {
    _dwellConfirmTimer?.cancel();
    _dwellCandidateStationId = stationId;
    _dwellCandidateSince = DateTime.now();
    _outOfRangeStreak = 0;
    _dwellConfirmTimer = Timer(
      const Duration(seconds: MapConstants.stationDwellDurationSeconds),
      _onDwellConfirmTimerFired,
    );
  }

  /// Confirmation-timer callback: the full dwell duration has elapsed
  /// with no candidate change. Re-checks that the last known position is
  /// still within the candidate's radius before tagging — the timer marks
  /// the deadline, but the position is what earns the tag.
  void _onDwellConfirmTimerFired() {
    _dwellConfirmTimer = null;

    // These should all be guaranteed by the cancellation discipline
    // (manual set / clear / candidate change all cancel the timer), but
    // guard anyway — a stray timer must never violate the contract.
    if (_manualOverride.value) return;
    if (_currentStationId.value != null) return;
    if (!TflMapData.instance.isLoaded) return;

    final candidateId = _dwellCandidateStationId;
    final position = _lastPosition;
    if (candidateId == null || position == null) return;

    final station = TflMapData.instance.stationById(candidateId);
    if (station == null) {
      _resetDwellState();
      return;
    }

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      station.position.latitude,
      station.position.longitude,
    );
    if (distance > MapConstants.stationDwellRadiusMetres) {
      // Last known fix has drifted out of range without a fresh fix
      // arriving to say so. Drop the candidate; entry evaluation will
      // rebuild it from the next fix.
      _resetDwellState();
      return;
    }

    _confirmDwell();
  }

  /// Promotes the current dwell candidate to the tagged station and
  /// emits [StationEnteredEvent]. [_manualOverride] is guaranteed false
  /// on every path here — both callers early-return under manual.
  void _confirmDwell() {
    final stationId = _dwellCandidateStationId;
    if (stationId == null) return;

    _resetDwellState();
    _currentLineId = null;
    _currentStationId.value = stationId;
    _eventController.add(
      StationEnteredEvent(stationId: stationId, at: DateTime.now()),
    );
  }

  /// Seeds a fresh dwell window from the last known position. Called by
  /// [clearStation] because the OS may deliver no further fixes while
  /// the user stands still — without this, clearing a tag while
  /// stationary would leave auto-detection waiting forever for a fix
  /// that never comes.
  void _seedDwellFromLastPosition() {
    final position = _lastPosition;
    if (position == null) return;
    if (!TflMapData.instance.isLoaded) return;

    final nearest = _nearestStationWithin(
      position,
      MapConstants.stationDwellRadiusMetres,
    );
    if (nearest != null) {
      _startDwell(nearest.id);
    }
  }

  /// Brute-force nearest-station scan (~470 stations per fix — trivially
  /// cheap at geolocator's 5 m-filter update rate; no spatial index
  /// needed). Returns null if no station is within [radiusMetres].
  TflStation? _nearestStationWithin(Position position, double radiusMetres) {
    TflStation? nearest;
    var nearestDistance = double.infinity;

    for (final station in TflMapData.instance.stations) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        station.position.latitude,
        station.position.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = station;
      }
    }

    if (nearest == null || nearestDistance > radiusMetres) return null;
    return nearest;
  }

  /// Drops all dwell state: candidate, clock, out-of-range streak, and
  /// the confirmation timer.
  void _resetDwellState() {
    _dwellConfirmTimer?.cancel();
    _dwellConfirmTimer = null;
    _dwellCandidateStationId = null;
    _dwellCandidateSince = null;
    _outOfRangeStreak = 0;
  }

  // ── Visited-stations-today logic (Session 4) ────────────────────────────

  /// Ensures the visited-stations-today snapshot reflects today's date.
  /// Runs a fresh hydration if never hydrated or if a day rollover has
  /// occurred since the last hydration. Guarded against concurrent
  /// invocations via [_hydrationFuture] — several call sites can await
  /// this without triggering duplicate DB scans.
  Future<void> _ensureVisitedStateIsForToday() async {
    final existing = _hydrationFuture;
    if (existing != null) {
      await existing;
      return;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_visitedHydratedFor == today) return;

    final future = _hydrateAndMarkToday(today);
    _hydrationFuture = future;
    try {
      await future;
    } finally {
      _hydrationFuture = null;
    }
  }

  /// Hydrates the visited map for [today] and stamps [_visitedHydratedFor]
  /// so subsequent [_ensureVisitedStateIsForToday] calls short-circuit
  /// until the wall-clock date advances again.
  Future<void> _hydrateAndMarkToday(DateTime today) async {
    await _hydrateVisitedStationsToday();
    _visitedHydratedFor = today;
  }

  /// Queries the repository for today's readings, filters to classified
  /// rows, and rebuilds [_visitedStationsToday] from scratch with the
  /// worst PM band per station. Publishes a fresh snapshot when done.
  ///
  /// On query failure, leaves the map empty and publishes an empty
  /// snapshot; the next hydration attempt will retry.
  Future<void> _hydrateVisitedStationsToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    _visitedStationsToday.clear();

    final List<AirQualityReading> readings;
    try {
      readings =
          await _readingsRepository.getReadingsBetween(startOfDay, now);
    } catch (_) {
      _publishVisitedSnapshot();
      return;
    }

    for (final reading in readings) {
      final stationId = reading.stationId;
      if (stationId == null) continue;
      final band = DaqiUtils.worstPmBand(
        reading.pm1,
        reading.pm25,
        reading.pm10,
      );
      final current = _visitedStationsToday[stationId];
      if (current == null || band.index > current.index) {
        _visitedStationsToday[stationId] = band;
      }
    }

    _publishVisitedSnapshot();
  }

  /// Starts the periodic wall-clock day-check. Cancels any existing
  /// timer first so repeat [start] calls are safe. See the field
  /// docstring on [_dayCheckTimer] for the rationale over a one-shot
  /// midnight timer.
  void _startPeriodicDayCheck() {
    _dayCheckTimer?.cancel();
    _dayCheckTimer = Timer.periodic(
      const Duration(seconds: _dayCheckIntervalSeconds),
      (_) => unawaited(_ensureVisitedStateIsForToday()),
    );
  }

  /// Updates the visited map for a single live classified reading.
  /// Ensures the snapshot is for today first (day-rollover check
  /// awaited here as belt-and-braces alongside the top-of-handler check
  /// in [_handleReading]).
  ///
  /// Only strictly-worse bands cause a publish — same-or-better bands
  /// leave the map unchanged. The map represents the worst observed
  /// band across the day, so it's monotonic within a day and updates
  /// are naturally rare after the first reading at each station.
  Future<void> _updateVisitedForReading(
    String stationId,
    AirQualityReading reading,
  ) async {
    await _ensureVisitedStateIsForToday();

    final band = DaqiUtils.worstPmBand(
      reading.pm1,
      reading.pm25,
      reading.pm10,
    );
    final current = _visitedStationsToday[stationId];
    if (current != null && current.index >= band.index) return;
    _visitedStationsToday[stationId] = band;
    _publishVisitedSnapshot();
  }

  /// Replaces the notifier's value with a fresh unmodifiable snapshot of
  /// [_visitedStationsToday]. `ValueNotifier` fires on reference
  /// inequality — a new Map instance every publish keeps listeners
  /// synchronised.
  void _publishVisitedSnapshot() {
    _visitedStationsTodayNotifier.value =
        Map<String, DaqiBand>.unmodifiable(_visitedStationsToday);
  }

  // ── Teardown ────────────────────────────────────────────────────────────

  /// Release resources. Called by `AppServices.dispose()`.
  Future<void> dispose() async {
    await _readingSub?.cancel();
    await _positionSub?.cancel();
    _readingSub = null;
    _positionSub = null;
    _dwellConfirmTimer?.cancel();
    _dwellConfirmTimer = null;
    _dayCheckTimer?.cancel();
    _dayCheckTimer = null;
    await _eventController.close();
    _currentStationId.dispose();
    _manualOverride.dispose();
    _visitedStationsTodayNotifier.dispose();
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