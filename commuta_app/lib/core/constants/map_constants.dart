/// Map screen tunable constants.
///
/// Values are deliberately concentrated here so they can be tweaked
/// once real-world testing begins. Spec values from
/// Commuta_MapScreen_Requirements §4 and §8.
class MapConstants {
  MapConstants._();

  // ── GPS gating ──────────────────────────────────────────────────────────
  /// Markers are only plotted when the phone's GPS accuracy
  /// is within this many metres. See §4.2.
  static const double gpsAccuracyThresholdMetres = 50.0;

  // ── Camera ──────────────────────────────────────────────────────────────
  /// Initial zoom when first centring on the user's location.
  static const double initialZoom = 15.0;

  /// Default starting position before the first GPS fix is acquired.
  /// London (Russell Square area) — adjust if you'd prefer a different default.
  static const double defaultStartLat = 51.5246;
  static const double defaultStartLng = -0.1340;

  // ── Marker ──────────────────────────────────────────────────────────────
  /// Logical pixel size of the AQI marker bitmap.
  static const double markerLogicalSize = 56.0;

  // ── Dwell detection ─────────────────────────────────────────────────────
  /// Readings within this radius of the cluster anchor are treated
  /// as the same stationary spot. Spec §4.3.
  static const double dwellRadiusMetres = 30.0;

  /// A cluster collapses into a collection marker once it has been
  /// active for at least this many seconds. Spec §4.3.
  static const int dwellDurationSeconds = 60;
}