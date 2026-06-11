import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/constants/app_colours.dart';
import '../../core/constants/map_constants.dart';
import '../../core/utils/daqi_utils.dart';
import '../../core/utils/placeholder_overall_aqi.dart';
import '../../data/datasources/air_quality_datasource.dart';
import '../../services/app_services.dart';
import '../../data/models/air_quality_reading.dart';
import '../../data/models/geo_tagged_reading.dart';
import '../../services/aqi_marker_builder.dart';
import '../../services/dwell_detector.dart';
import '../../services/location_service.dart';
import '../../widgets/reading_floating_window.dart';

/// The Google Map view inside the Map screen.
///
/// Shows the user's live location, plots a coloured AQI marker for
/// every plottable reading, collapses stationary runs into stacked
/// collection markers via [DwellDetector], and surfaces a corner
/// indicator when GPS accuracy is too poor for plotting.
class GoogleMapView extends StatefulWidget {
  const GoogleMapView({super.key});

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView> {
  GoogleMapController? _mapController;

  // Data
  late final AirQualityDataSource _dataSource;
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
    _dwellDetector = DwellDetector();
    _initLocation();
    _subscribeToReadings();
    _subscribeToDwellEvents();
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    _dwellSub?.cancel();
    _positionSub?.cancel();
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

  // ── Readings → dwell detector ─────────────────────────────────────────────

  void _subscribeToReadings() {
    _readingSub = _dataSource.subscribeToLiveReadings().listen((reading) {
      final geoReading = GeoTaggedReading(
        reading: reading,
        position: _currentPosition,
      );
      if (!geoReading.isPlottable) return;
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

  // ── Marker handlers ───────────────────────────────────────────────────────

  Future<void> _onAddSingle(AddSingleEvent e) async {
    final info = PlaceholderOverallAqi.computeBand(e.reading);
    final value = PlaceholderOverallAqi.displayValue(e.reading);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final icon = await AqiMarkerBuilder.build(
      band: info.band,
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
    // Dominant band = worst band across the collection.
    DaqiBand worst = DaqiBand.low;
    for (final r in e.readings) {
      final b = PlaceholderOverallAqi.computeBand(r).band;
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
    final newBand = PlaceholderOverallAqi.computeBand(e.reading).band;
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
