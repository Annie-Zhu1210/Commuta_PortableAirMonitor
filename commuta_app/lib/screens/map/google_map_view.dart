import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/constants/app_colours.dart';
import '../../core/constants/map_constants.dart';
import '../../core/utils/daqi_utils.dart';
import '../../data/datasources/air_quality_datasource.dart';
import '../../services/app_services.dart';
import '../../data/models/air_quality_reading.dart';
import '../../data/models/geo_tagged_reading.dart';
import '../../services/aqi_marker_builder.dart';
import '../../services/dwell_detector.dart';
import '../../services/location_service.dart';
import '../../services/map_aqi_score.dart';
import '../../services/readings_repository.dart';
import '../../services/station_classification_service.dart';
import '../../widgets/reading_floating_window.dart';

/// The Google Map view inside the Map screen.
///
/// Shows the user's live location, plots a coloured AQI marker for
/// every plottable reading, collapses stationary runs into stacked
/// collection markers via [DwellDetector], and surfaces a corner
/// indicator when GPS accuracy is too poor for plotting.
///
/// Marker score and colour come from [MapAqiScore], which delegates
/// to the Home hero's scoring — the number inside a marker is the
/// same 0–100 integer the hero card shows for that reading.
///
/// Two gates decide whether a live reading is plotted (and,
/// identically, whether its coordinates are persisted to Drift via
/// [ReadingsRepository.setGpsForReading]):
///
///   1. GPS accuracy within [MapConstants.gpsAccuracyThresholdMetres]
///      ([GeoTaggedReading.isPlottable]);
///   2. no station currently tagged
///      ([StationClassificationService.currentStationId] is null) —
///      readings taken while at a station are represented on the TfL
///      map under that station; the station tag is their location.
///
/// Applying both gates to both actions keeps the invariant exact:
/// `gpsLat` is populated ⟺ the reading appeared on this map. That
/// invariant is what makes hydration honest — on `initState`, today's
/// unclassified GPS rows are replayed through the [DwellDetector] to
/// reconstruct exactly the markers the user saw before a restart.
///
/// A periodic wall-clock day check (mirroring
/// `StationClassificationService`) clears the marker set at local
/// midnight so a map left open overnight doesn't carry yesterday's
/// markers into the new day.
class GoogleMapView extends StatefulWidget {
  const GoogleMapView({super.key});

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView> {
  GoogleMapController? _mapController;

  // Data
  late final AirQualityDataSource _dataSource;
  late final ReadingsRepository _repository;
  late final StationClassificationService _classificationService;
  late final DwellDetector _dwellDetector;
  StreamSubscription<dynamic>? _readingSub;
  StreamSubscription<DwellEvent>? _dwellSub;
  StreamSubscription<Position>? _positionSub;

  // Location state
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  String? _locationError;

  // Markers
  final Set<Marker> _markers = {};

  // Per-collection state for tap handling and band-change detection.
  final Map<String, ValueNotifier<List<AirQualityReading>>>
  _collectionReadings = {};
  final Map<String, DaqiBand> _collectionBands = {};

  // ── Midnight rollover state ─────────────────────────────────────────────

  /// The local-midnight [DateTime] the current marker set corresponds
  /// to. Set by hydration and compared against `DateTime.now()` in
  /// [_ensureMarkersAreForToday] to detect day rollover regardless of
  /// monotonic vs. wall-clock time drift. Mirrors
  /// `StationClassificationService._visitedHydratedFor`.
  DateTime? _markersRenderedFor;

  /// Periodic timer that wakes every [_dayCheckIntervalSeconds]
  /// seconds of monotonic time and asks [_ensureMarkersAreForToday]
  /// whether the wall-clock date has advanced. Intentionally a
  /// `Timer.periodic` rather than a one-shot fired at midnight,
  /// because Dart `Timer` durations are monotonic — a one-shot
  /// scheduled at 23:55 for "5 minutes from now" doesn't fire if the
  /// system clock jumps forward past midnight, and doesn't fire
  /// reliably across iOS backgrounding either. The tick body is one
  /// `DateTime` comparison and an early return on the common path.
  Timer? _dayCheckTimer;

  /// How often the periodic wall-clock day check ticks. Same
  /// trade-off as `StationClassificationService`: negligible per-tick
  /// cost against a worst-case 60 s delay in clearing after midnight.
  static const int _dayCheckIntervalSeconds = 60;

  // Initial camera — re-used until the first GPS fix lands.
  static const CameraPosition _fallbackCamera = CameraPosition(
    target: LatLng(MapConstants.defaultStartLat, MapConstants.defaultStartLng),
    zoom: 12,
  );

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _dataSource = AppServices.instance.dataSource;
    _repository = AppServices.instance.readingsRepository;
    _classificationService = AppServices.instance.classificationService;
    _dwellDetector = DwellDetector();
    _initLocation();
    // Dwell-event subscription must exist before hydration replays
    // readings into the detector — its controller is a broadcast
    // stream, so events emitted with no listener are simply lost.
    _subscribeToDwellEvents();
    unawaited(_initReadings());
    _startPeriodicDayCheck();
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    _dwellSub?.cancel();
    _positionSub?.cancel();
    _dayCheckTimer?.cancel();
    _dwellDetector.dispose();
    _mapController?.dispose();
    for (final n in _collectionReadings.values) {
      n.dispose();
    }
    _collectionReadings.clear();
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    final result = await LocationService.ensurePermission();

    if (result != LocationPermissionResult.granted) {
      setState(() {
        _isLoadingLocation = false;
        _locationError = switch (result) {
          LocationPermissionResult.servicesDisabled =>
            'Location services are disabled.',
          LocationPermissionResult.denied => 'Location permission was denied.',
          LocationPermissionResult.deniedForever =>
            'Location permission permanently denied. Enable it in Settings.',
          LocationPermissionResult.granted => null,
        };
      });
      return;
    }

    try {
      final pos = await LocationService.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentPosition = pos;
        _isLoadingLocation = false;
      });
      _centreCameraOn(pos);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingLocation = false;
        _locationError = 'Could not obtain location: $e';
      });
    }

    _positionSub = LocationService.positionStream().listen((pos) {
      if (!mounted) return;
      setState(() => _currentPosition = pos);
    });
  }

  void _centreCameraOn(Position pos) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: MapConstants.initialZoom,
        ),
      ),
    );
  }

  // ── Readings: hydration, then live ────────────────────────────────────────

  /// Hydrates today's markers from Drift, then subscribes to the live
  /// stream. Sequenced (not parallel) so replayed and live readings
  /// enter the [DwellDetector] in timestamp order — the detector's
  /// cluster logic keys off inter-reading timestamps and anchor
  /// positions, so an out-of-order live reading landing mid-replay
  /// could split or mis-anchor a cluster.
  Future<void> _initReadings() async {
    await _hydrateTodayMarkers();
    if (!mounted) return;
    _subscribeToReadings();
  }

  /// Replays today's unclassified GPS-tagged readings from Drift
  /// through the [DwellDetector], reconstructing the singles and
  /// collections that were on the map before the last restart (or
  /// before this view was last disposed).
  ///
  /// Self-healing by construction: rows persisted before GPS
  /// persistence landed have null GPS columns and are invisible to
  /// the query, so first launch after this session simply restores
  /// nothing. The moment [ReadingsRepository.setGpsForReading] starts
  /// writing, subsequent restarts start restoring markers.
  ///
  /// Rows arrive already accuracy-gated — coordinates were only ever
  /// written for readings that passed [GeoTaggedReading.isPlottable]
  /// — so they're fed straight to the detector without re-gating.
  Future<void> _hydrateTodayMarkers() async {
    final now = DateTime.now();
    _markersRenderedFor = DateTime(now.year, now.month, now.day);

    final rows = await _repository.getUnclassifiedGpsReadingsForDay(now);
    if (!mounted) return;

    for (final r in rows) {
      final lat = r.gpsLat;
      final lng = r.gpsLng;
      if (lat == null || lng == null) continue; // defensive; query filters
      _dwellDetector.addReading(
        GeoTaggedReading(
          reading: r,
          position: Position(
            latitude: lat,
            longitude: lng,
            timestamp: r.timestamp,
            // Synthetic fix reconstructed from persisted coordinates.
            // Accuracy 0 is a statement that gating already happened
            // at write time, not a claim about the original fix.
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          ),
        ),
      );
    }
  }

  /// Subscribes to live readings. Each reading passes through two
  /// gates before being plotted *and* having its coordinates
  /// persisted — the two actions share their gates exactly, which is
  /// what keeps the `gpsLat populated ⟺ appeared on this map`
  /// invariant true (see class docstring).
  void _subscribeToReadings() {
    _readingSub = _dataSource.subscribeToLiveReadings().listen((reading) {
      // Day-rollover check from the reading stream too — cheap when
      // already on today, and catches midnight promptly on an active
      // commute even between periodic ticks.
      _ensureMarkersAreForToday();

      // Gate 2 (checked first — it's a synchronous field read):
      // readings taken while tagged at a station belong to the TfL
      // map. The classification service classifies this same reading
      // from this same stream whenever currentStationId is non-null,
      // so this check and the classification decision can never
      // disagree.
      if (_classificationService.currentStationId.value != null) return;

      // Gate 1: GPS accuracy.
      final position = _currentPosition;
      final geoReading = GeoTaggedReading(
        reading: reading,
        position: position,
      );
      if (!geoReading.isPlottable) return;

      // Both gates passed — persist coordinates (fire-and-forget; the
      // raw row is persisted separately by ReadingsRepository, so a
      // failure here only costs this marker's hydration after a
      // restart) and plot.
      unawaited(
        _repository
            .setGpsForReading(
              reading,
              lat: position!.latitude,
              lng: position.longitude,
            )
            .catchError((Object _) {}),
      );

      _dwellDetector.addReading(geoReading);
    });
  }

  void _subscribeToDwellEvents() {
    _dwellSub = _dwellDetector.events.listen((event) async {
      switch (event) {
        case AddSingleEvent():
          await _onAddSingle(event);
        case CollapseToCollectionEvent():
          await _onCollapse(event);
        case AppendToCollectionEvent():
          await _onAppend(event);
      }
    });
  }

  // ── Midnight rollover ─────────────────────────────────────────────────────

  /// Starts the periodic wall-clock day check. Cancels any existing
  /// timer first so repeat calls are safe. See [_dayCheckTimer] for
  /// the rationale over a one-shot midnight timer.
  void _startPeriodicDayCheck() {
    _dayCheckTimer?.cancel();
    _dayCheckTimer = Timer.periodic(
      const Duration(seconds: _dayCheckIntervalSeconds),
      (_) => _ensureMarkersAreForToday(),
    );
  }

  /// Clears the marker set if the wall-clock date has advanced past
  /// the day the current markers belong to. Nothing is rehydrated on
  /// rollover — the new day has no unclassified GPS rows yet by
  /// definition. If the view is instead disposed overnight and
  /// recreated the next day, `initState` hydration achieves the same
  /// outcome, so both paths converge on an empty map at dawn.
  void _ensureMarkersAreForToday() {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    if (_markersRenderedFor == todayMidnight) return;
    _markersRenderedFor = todayMidnight;

    // Reset cluster state so the first reading of the new day starts
    // a fresh cluster rather than continuing yesterday's anchor.
    _dwellDetector.reset();

    // Dispose collection notifiers (same teardown as dispose()).
    for (final n in _collectionReadings.values) {
      n.dispose();
    }
    _collectionReadings.clear();
    _collectionBands.clear();

    if (!mounted) return;
    setState(() => _markers.clear());
  }

  // ── Marker handlers ───────────────────────────────────────────────────────

  Future<void> _onAddSingle(AddSingleEvent e) async {
    final band = MapAqiScore.computeBand(e.reading);
    final value = MapAqiScore.displayValue(e.reading);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final icon = await AqiMarkerBuilder.build(
      band: band,
      displayValue: value,
      devicePixelRatio: dpr,
    );
    if (!mounted) return;
    setState(() {
      _markers.add(
        Marker(
          markerId: _singleMarkerId(e.reading),
          position: LatLng(e.position.latitude, e.position.longitude),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          onTap: () => _onSingleMarkerTapped(e.reading),
        ),
      );
    });
  }

  Future<void> _onCollapse(CollapseToCollectionEvent e) async {
    // Dominant band = worst score-derived band across the collection,
    // so single and collection markers colour by the same rule.
    DaqiBand worst = DaqiBand.low;
    for (final r in e.readings) {
      final b = MapAqiScore.computeBand(r);
      if (b.index > worst.index) worst = b;
    }
    _collectionBands[e.collectionId] = worst;
    _collectionReadings[e.collectionId] = ValueNotifier(List.of(e.readings));

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final icon = await AqiMarkerBuilder.buildCollection(
      dominantBand: worst,
      devicePixelRatio: dpr,
    );
    if (!mounted) return;

    final removeIds = e.readings.map(_singleMarkerId).toSet();
    setState(() {
      _markers.removeWhere((m) => removeIds.contains(m.markerId));
      _markers.add(
        Marker(
          markerId: _collectionMarkerId(e.collectionId),
          position: LatLng(
            e.anchorPosition.latitude,
            e.anchorPosition.longitude,
          ),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          onTap: () => _onCollectionMarkerTapped(e.collectionId),
        ),
      );
    });
  }

  Future<void> _onAppend(AppendToCollectionEvent e) async {
    final notifier = _collectionReadings[e.collectionId];
    if (notifier == null) return;
    notifier.value = [...notifier.value, e.reading];

    // Dominant band is monotonic — only re-render if the new reading
    // has pushed the band higher than what's currently displayed.
    final newBand = MapAqiScore.computeBand(e.reading);
    final currentBand = _collectionBands[e.collectionId] ?? DaqiBand.low;
    if (newBand.index <= currentBand.index) return;
    _collectionBands[e.collectionId] = newBand;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final icon = await AqiMarkerBuilder.buildCollection(
      dominantBand: newBand,
      devicePixelRatio: dpr,
    );
    if (!mounted) return;

    final id = _collectionMarkerId(e.collectionId);
    final old = _markers.firstWhere((m) => m.markerId == id);
    setState(() {
      _markers.remove(old);
      _markers.add(old.copyWith(iconParam: icon));
    });
  }

  // ── Tap handlers ──────────────────────────────────────────────────────────

  void _onSingleMarkerTapped(AirQualityReading reading) {
    showReadingFloatingWindow(context, readings: [reading]);
  }

  void _onCollectionMarkerTapped(String collectionId) {
    final notifier = _collectionReadings[collectionId];
    if (notifier == null || notifier.value.isEmpty) return;
    showLiveReadingFloatingWindow(context, readings: notifier);
  }

  // ── Marker ID helpers ─────────────────────────────────────────────────────

  MarkerId _singleMarkerId(AirQualityReading r) =>
      MarkerId('single_${r.sequenceNumber}');

  MarkerId _collectionMarkerId(String id) => MarkerId('collection_$id');

  // ── Map callbacks ─────────────────────────────────────────────────────────

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_currentPosition != null) _centreCameraOn(_currentPosition!);
  }

  // ── GPS-weak indicator ────────────────────────────────────────────────────

  bool get _isGpsWeak {
    final p = _currentPosition;
    return p != null && p.accuracy > MapConstants.gpsAccuracyThresholdMetres;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_locationError != null) return _buildErrorState();

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: _fallbackCamera,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: _markers,
        ),

        if (_isLoadingLocation)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: Center(
                child: CircularProgressIndicator(color: AppColours.accent),
              ),
            ),
          ),

        // GPS-weak indicator (top-left)
        if (!_isLoadingLocation && _isGpsWeak)
          Positioned(top: 16, left: 16, child: _GpsWeakIndicator()),

        // My-location FAB (bottom-left)
        if (!_isLoadingLocation)
          Positioned(
            bottom: 100,
            left: 16,
            child: FloatingActionButton.small(
              backgroundColor: AppColours.surface,
              foregroundColor: AppColours.accent,
              elevation: 4,
              onPressed: () {
                final p = _currentPosition;
                if (p != null) _centreCameraOn(p);
              },
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Container(
      color: AppColours.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off_outlined,
                size: 48,
                color: AppColours.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                _locationError ?? 'Location unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColours.textPrimary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoadingLocation = true;
                    _locationError = null;
                  });
                  _initLocation();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColours.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small chip shown when GPS accuracy is worse than the plotting
/// threshold. Spec §4.2.
class _GpsWeakIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColours.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_not_fixed, size: 14, color: AppColours.daqiModerate),
          const SizedBox(width: 6),
          Text(
            'GPS signal weak — readings still being collected',
            style: TextStyle(
              fontSize: 11,
              color: AppColours.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}