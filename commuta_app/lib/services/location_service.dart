import 'package:geolocator/geolocator.dart';

/// Result of a permission request.
enum LocationPermissionResult {
  granted,
  denied,
  deniedForever,
  servicesDisabled,
}

/// Wrapper around [Geolocator] so the map views don't deal with
/// permission plumbing directly.
class LocationService {
  LocationService._();

  /// Ensures location services are enabled and permission is granted,
  /// requesting permission if necessary.
  static Future<LocationPermissionResult> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionResult.servicesDisabled;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return LocationPermissionResult.denied;
    }
    if (perm == LocationPermission.deniedForever) {
      return LocationPermissionResult.deniedForever;
    }
    return LocationPermissionResult.granted;
  }

  /// One-shot position fetch.
  static Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  /// Continuous position stream. [distanceFilterMetres] controls how
  /// far the user must move before a new event is emitted.
  static Stream<Position> positionStream({int distanceFilterMetres = 5}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilterMetres,
      ),
    );
  }
}