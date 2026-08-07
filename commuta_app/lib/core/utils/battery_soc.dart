/// App-side battery state-of-charge (SOC) utility.
///
/// Replaces the firmware-computed `battery_pct` byte in the Status
/// packet (which uses a simple linear map) with an interpolation
/// against a lookup table calibrated from a real drain-to-dead test
/// on the Commuta device. See `docs/battery_report.md` for the full
/// methodology.
///
/// Calibration source (Annie, 2026-08-01 → 2026-08-02):
///   • 24.00 h continuous drain from full charge to firmware
///     brown-out, single boot session (no reboots).
///   • Fully-charged peak observed at ~3931 mV (this cell's peak
///     sits below the 4200 mV nominal of a bare LiPo — the anchor
///     used here is 3900 mV so any reading above it clamps to 100 %).
///   • Terminal reading at 2377 mV (device could no longer boot).
///   • LOWESS smoother, frac = 0.05, evaluated at 50 mV steps.
///
/// Known limitations documented in the report:
///   • The mid-plateau region (~3.55–3.70 V) is intrinsically flat —
///     a single voltage reading in there is a poor estimator of
///     remaining charge. Callers who need a stable display should
///     feed a rolling window of recent `vbat_mv` samples into
///     [smoothedPercentFromWindow] rather than calling
///     [vbatMvToPercent] once per Live packet.
///   • Percentages are relative to *this test's* runtime under the
///     observed load and ambient temperature. Real-world runtime
///     will vary with BLE activity, cell ageing, and temperature.
///
/// The public functions are pure — no state, no side effects — so
/// they are trivially unit-testable against fixed byte fixtures.
library;

// ── Calibration constants ────────────────────────────────────────────────

/// Highest voltage in the calibration table. `vbat_mv` at or above
/// this value maps to 100 %.
const int _peakMv = 3900;

/// Lowest voltage in the calibration table. `vbat_mv` at or below
/// this value maps to 0 %. The test recorded voltages down to
/// 2377 mV, but the fitted curve is essentially zero from ~2700 mV
/// onward, so this is the practical floor.
const int _terminalMv = 2700;

/// Voltage → percentage-remaining anchor points, from the 50 mV
/// LOWESS lookup. Ordered by descending `vbatMv` so interpolation
/// walks the list once from index 0 downward.
///
/// Percentages are stored as doubles for precision through the
/// interpolation; the public [vbatMvToPercent] rounds to an int on
/// return.
const List<({int vbatMv, double percent})> _lookupTable = [
  (vbatMv: 3900, percent: 100.0),
  (vbatMv: 3850, percent: 98.9),
  (vbatMv: 3800, percent: 97.3),
  (vbatMv: 3750, percent: 95.3),
  (vbatMv: 3700, percent: 92.2),
  (vbatMv: 3650, percent: 88.6),
  (vbatMv: 3600, percent: 71.7),
  (vbatMv: 3550, percent: 39.1),
  (vbatMv: 3500, percent: 35.7),
  (vbatMv: 3450, percent: 32.8),
  (vbatMv: 3400, percent: 29.5),
  (vbatMv: 3350, percent: 25.5),
  (vbatMv: 3300, percent: 21.1),
  (vbatMv: 3250, percent: 16.2),
  (vbatMv: 3200, percent: 8.6),
  (vbatMv: 3150, percent: 6.4),
  (vbatMv: 3100, percent: 5.4),
  (vbatMv: 3050, percent: 4.5),
  (vbatMv: 3000, percent: 3.5),
  (vbatMv: 2950, percent: 2.6),
  (vbatMv: 2900, percent: 1.7),
  (vbatMv: 2850, percent: 1.2),
  (vbatMv: 2800, percent: 0.7),
  (vbatMv: 2750, percent: 0.3),
  (vbatMv: 2700, percent: 0.0),
];

// ── Public API ───────────────────────────────────────────────────────────

/// Maps a single `vbat_mv` reading to an integer state-of-charge
/// percentage using piecewise-linear interpolation against
/// [_lookupTable].
///
/// Boundary handling (Decision 4c, clamp at both ends):
///   • [vbatMv] ≥ [_peakMv] → 100
///   • [vbatMv] ≤ [_terminalMv] → 0
///   • Otherwise → interpolated within the bracketing pair.
///
/// Returns `null` if [vbatMv] is `null`.
///
/// Callers displaying a live gauge should almost always prefer
/// [smoothedPercentFromWindow], since a raw per-sample percentage
/// jitters visibly under BLE-TX voltage sag.
int? vbatMvToPercent(int? vbatMv) {
  if (vbatMv == null) return null;
  if (vbatMv >= _peakMv) return 100;
  if (vbatMv <= _terminalMv) return 0;

  for (var i = 0; i < _lookupTable.length - 1; i++) {
    final upper = _lookupTable[i];
    final lower = _lookupTable[i + 1];
    if (vbatMv <= upper.vbatMv && vbatMv >= lower.vbatMv) {
      final span = upper.vbatMv - lower.vbatMv;
      if (span == 0) return upper.percent.round();
      final frac = (upper.vbatMv - vbatMv) / span;
      final interpolated =
          upper.percent + frac * (lower.percent - upper.percent);
      return interpolated.round().clamp(0, 100);
    }
  }

  // Unreachable given the boundary guards above, but return null
  // rather than throwing so a malformed calibration table can't crash
  // the BLE handler.
  return null;
}

/// Rounds a percentage to the nearest 5 for display stability and
/// clamps into `[0, 100]`. Returns `null` for a null input.
///
/// A snap step of 5 hides the single-percent wobble that the median
/// filter leaves behind while still giving the user meaningful
/// resolution (twenty distinguishable levels — the same as most
/// phone battery indicators).
int? snapToNearestFive(int? percent) {
  if (percent == null) return null;
  final snapped = (percent / 5).round() * 5;
  return snapped.clamp(0, 100);
}

/// Computes the display-ready battery percentage from a rolling
/// window of recent `vbat_mv` samples (Decision 3e):
///
///   1. Median of [recentVbatMv] — rejects the ~30 mV BLE-TX sag
///      spike without lagging the underlying discharge.
///   2. Lookup via [vbatMvToPercent].
///   3. Snap to the nearest 5 % via [snapToNearestFive].
///
/// Returns `null` when the window is empty (no Live sample has
/// arrived this session yet), letting the caller fall back to the
/// firmware value from the Status packet.
///
/// The window is expected to hold up to six samples (≈ 60 s of Live
/// at the 10 s cadence), but this function does not enforce a size
/// — bounded pruning belongs to the caller so ownership of the
/// buffer stays in one place.
int? smoothedPercentFromWindow(List<int> recentVbatMv) {
  if (recentVbatMv.isEmpty) return null;
  final median = _medianOfInts(recentVbatMv);
  return snapToNearestFive(vbatMvToPercent(median));
}

// ── Internal helpers ─────────────────────────────────────────────────────

/// Median of a non-empty list of ints. Even-length inputs return the
/// rounded mean of the two middle elements.
int _medianOfInts(List<int> values) {
  final sorted = List<int>.of(values)..sort();
  final n = sorted.length;
  final mid = n ~/ 2;
  if (n.isOdd) return sorted[mid];
  return ((sorted[mid - 1] + sorted[mid]) / 2).round();
}