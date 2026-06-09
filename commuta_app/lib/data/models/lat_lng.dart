/// A geographic coordinate (latitude, longitude in degrees, WGS84).
///
/// Kept deliberately minimal. We don't reuse `google_maps_flutter`'s
/// `LatLng` here because the TfL Tube map renders to a `CustomPainter`,
/// not a Google Map — the TfL data layer should not depend on the
/// Google Maps package.
///
/// If you ever need to import this alongside another `LatLng` (e.g.
/// from `google_maps_flutter`), use an import alias:
///   import 'package:commuta_app/data/models/lat_lng.dart' as tfl;
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';

  @override
  bool operator ==(Object other) =>
      other is LatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}