import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/constants/app_colours.dart';
import '../../core/constants/map_constants.dart';
import '../../core/utils/placeholder_overall_aqi.dart';
import '../../data/datasources/air_quality_datasource.dart';
import '../../data/datasources/mock_datasource.dart';
import '../../data/models/geo_tagged_reading.dart';
import '../../services/aqi_marker_builder.dart';
import '../../services/location_service.dart';

/// The Google Map view inside the Map screen.
///
/// Shows the user's live location (built-in blue dot with accuracy
/// circle), plots a coloured AQI marker for every incoming reading
/// whose GPS accuracy is acceptable, and surfaces a corner indicator
/// when accuracy is too poor for plotting.
class GoogleMapView extends StatefulWidget {
  const GoogleMapView({super.key});

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView> {
  GoogleMapController? _mapController;

  // Data
  late final AirQualityDataSource _dataSource;
  StreamSubscription<dynamic>? _readingSub;
  StreamSubscription<Position>? _positionSub;

  // Location state
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  String? _locationError;

  // Markers
  final Set<Marker> _markers = {};

  // Initial camera — re-used until the first GPS fix lands.
  static const CameraPosition _fallbackCamera = CameraPosition(
    target: LatLng(
      MapConstants.defaultStartLat,
      MapConstants.defaultStartLng,
    ),
    zoom: 12,
  );

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _dataSource = MockDataSource();
    _initLocation();
    _subscribeToReadings();
  }

  @override
  void dispose() {
    _readingSub?.cancel();
    _positionSub?.cancel();
    _dataSource.dispose();
    _mapController?.dispose();
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
          LocationPermissionResult.denied =>
            'Location permission was denied.',
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

  // ── Readings → markers ────────────────────────────────────────────────────

  void _subscribeToReadings() {
    _readingSub = _dataSource.subscribeToLiveReadings().listen((reading) async {
      final geoReading = GeoTaggedReading(
        reading: reading,
        position: _currentPosition,
      );
      if (!geoReading.isPlottable) return;
      await _addMarkerFor(geoReading);
    });
  }

  Future<void> _addMarkerFor(GeoTaggedReading geoReading) async {
    final info = PlaceholderOverallAqi.computeBand(geoReading.reading);
    final value = PlaceholderOverallAqi.displayValue(geoReading.reading);

    final dpr = MediaQuery.of(context).devicePixelRatio;
    final icon = await AqiMarkerBuilder.build(
      band: info.band,
      displayValue: value,
      devicePixelRatio: dpr,
    );
    if (!mounted) return;

    final pos = geoReading.position!;
    setState(() {
      _markers.add(
        Marker(
          markerId: MarkerId('reading_${geoReading.reading.sequenceNumber}'),
          position: LatLng(pos.latitude, pos.longitude),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          // Tap behaviour is added in Phase 3 (floating window).
        ),
      );
    });
  }

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
          Positioned(
            top: 16,
            left: 16,
            child: _GpsWeakIndicator(),
          ),

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
                style: TextStyle(
                  fontSize: 14,
                  color: AppColours.textPrimary,
                ),
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
          Icon(
            Icons.gps_not_fixed,
            size: 14,
            color: AppColours.daqiModerate,
          ),
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