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

  // ── Dwell detection (Google Map reading clusters) ───────────────────────
  /// Readings within this radius of the cluster anchor are treated
  /// as the same stationary spot. Spec §4.3. Used by `DwellDetector`
  /// on the Google Map view — distinct from the station-classification
  /// constants below, which govern the TfL map's auto-tagging.
  static const double dwellRadiusMetres = 30.0;

  /// A cluster collapses into a collection marker once it has been
  /// active for at least this many seconds. Spec §4.3. Used by
  /// `DwellDetector` on the Google Map view.
  static const int dwellDurationSeconds = 60;

  // ── Station classification (TfL map auto-tagging, Phase 5 Step 2) ──────
  /// A station becomes a dwell candidate when the user's position is
  /// within this many metres of it. Also the "still in range" radius
  /// used by departure detection. Used by `StationClassificationService`.
  static const double stationDwellRadiusMetres = 100.0;

  /// A dwell candidate is confirmed (auto-tagged) once the user has
  /// remained within [stationDwellRadiusMetres] of it for this many
  /// seconds. Used by `StationClassificationService`.
  static const int stationDwellDurationSeconds = 60;

  /// An auto tag is released after this many consecutive position fixes
  /// outside [stationDwellRadiusMetres] of the tagged station. Temporal
  /// hysteresis only — there is deliberately no separate departure
  /// radius (Session 2, Decision 4). Used by
  /// `StationClassificationService`.
  static const int stationDepartureStreakSize = 3;

  // ── TfL map interaction (Phase 5 Step 3 + 4, Session 5) ────────────────
  /// On-screen tap radius (in logical pixels) around a TfL station dot
  /// that counts as a hit. Follows Apple HIG's 44 pt minimum tap target
  /// (22 px radius = 44 px diameter). The view converts this to scene
  /// space at hit-test time by dividing by the current `viewScale`, so
  /// the effective tap slop stays constant on screen regardless of the
  /// `InteractiveViewer`'s zoom level. Session 5, Decision 6.
  static const double tflMapTapRadiusPixels = 22.0;
}