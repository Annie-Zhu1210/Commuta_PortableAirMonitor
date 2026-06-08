import 'package:flutter/material.dart';
import '../constants/app_colours.dart';

/// Air quality band info shown as a coloured pill on metric cards.
///
/// Different metrics use different band labels (e.g. "Comfortable" for
/// temperature, "Good ventilation" for CO₂, "Baseline" for NOx Index),
/// but they all share the same severity scale ([DaqiBand]) and colour palette.
enum DaqiBand {
  low,       // sage     — comfortable / safe
  moderate,  // amber    — mildly outside ideal range
  high,      // coral    — notable concern
  veryHigh,  // deep red — major concern
}

class DaqiInfo {
  final DaqiBand band;
  final String label;
  final Color colour;

  const DaqiInfo({
    required this.band,
    required this.label,
    required this.colour,
  });
}

/// Banding functions for every metric.
///
/// Thresholds and labels reflect Annie's research:
///   PM2.5, PM10            — UK DAQI breakpoints (DEFRA, gov.uk)
///   PM1                    — custom thresholds (no official DAQI band)
///   CO₂                    — indoor ventilation guidance (3 bands)
///   Temperature, Humidity  — comfort thresholds (Goldilocks zone)
///   Pressure (absolute)    — meteorological norm range
///   Pressure (gradient)    — rate-of-change discomfort scale
///   VOC Index, NOx Index   — Sensirion SGP41 index ranges (1–500)
class DaqiUtils {
  DaqiUtils._();

  // ───────────────────────── Particulate matter ─────────────────────────────
  // Source: gov.uk DAQI tables. PM2.5 and PM10 use the official DEFRA bands.
  // PM1 uses custom thresholds (no official DAQI band exists for PM1).

  static DaqiInfo forPm25(double value) {
    // Note: gov.uk table shows level 10 (Very High) starts at 71 µg/m³.
    if (value <= 35)  return _low('Low');
    if (value <= 53)  return _moderate('Moderate');
    if (value <= 70)  return _high('High');
    return                   _veryHigh('Very High');
  }

  static DaqiInfo forPm10(double value) {
    if (value <= 50)   return _low('Low');
    if (value <= 75)   return _moderate('Moderate');
    if (value <= 100)  return _high('High');
    return                    _veryHigh('Very High');
  }

  static DaqiInfo forPm1(double value) {
    if (value <= 21)  return _low('Low');
    if (value <= 32)  return _moderate('Moderate');
    if (value <= 42)  return _high('High');
    return                   _veryHigh('Very High');
  }

  // ───────────────────────── CO₂ (3 bands) ──────────────────────────────────
  // Indoor ventilation guidance — not part of DAQI.
  static DaqiInfo forCo2(double value) {
    if (value < 800)   return _low('Good ventilation');
    if (value <= 1500) return _moderate('Adequate ventilation');
    return                    _high('Poor ventilation');
  }

  // ───────────────────────── Temperature (Goldilocks) ───────────────────────
  // Both Cold and Hot are flagged. Comfortable sits in the middle as "low".
  static DaqiInfo forTemperature(double value) {
    if (value < 17)   return _moderate('Cold');
    if (value <= 25)  return _low('Comfortable');
    if (value <= 30)  return _moderate('Warm');
    return                   _high('Hot');
  }

  // ───────────────────────── Humidity (Goldilocks) ──────────────────────────
  // Both Very dry and Too humid are flagged as high (problematic for health).
  static DaqiInfo forHumidity(double value) {
    if (value < 20)   return _high('Very dry');
    if (value <= 40)  return _moderate('Dry');
    if (value <= 70)  return _low('Comfortable');
    return                   _high('Too humid');
  }

  // ───────────────────────── Pressure (absolute) ────────────────────────────
  static DaqiInfo forPressure(double value) {
    if (value < 990)   return _moderate('Unusually low');
    if (value <= 1030) return _low('Normal');
    return                    _moderate('Unusually high');
  }

  // ───────────────────────── Pressure (rate of change) ──────────────────────
  // Pa/s. Sign-insensitive — both rising and falling pressure can be
  // uncomfortable. Used for future pressure-change indicator on the card.
  // TODO: Pressure change requires comparing successive readings over time —
  //       wire this up once the data layer supports rate computation.
  static DaqiInfo forPressureGradient(double paPerSec) {
    final abs = paPerSec.abs();
    if (abs < 50)    return _low('Calm');
    if (abs <= 175)  return _moderate('Mild');
    if (abs <= 600)  return _high('Noticeable');
    return                  _veryHigh('Uncomfortable');
  }

  // ───────────────────────── VOC Index (Sensirion, 1–500) ───────────────────
  // Returns null when the SGP41 is not connected.
  // TODO: Labels are placeholders ("Low/Moderate/High/Very High") — replace
  //       with finalised band names once decided.
  static DaqiInfo? forTvoc(double? value) {
    if (value == null) return null;
    if (value <= 150)  return _low('Low');
    if (value <= 250)  return _moderate('Moderate');
    if (value <= 400)  return _high('High');
    return                    _veryHigh('Very High');
  }

  // ───────────────────────── NOx Index (Sensirion, 1–500) ───────────────────
  // Returns null when the SGP41 is not connected.
  static DaqiInfo? forNox(double? value) {
    if (value == null) return null;
    if (value <= 30)   return _low('Baseline');
    if (value <= 150)  return _moderate('Mild event');
    if (value <= 300)  return _high('Moderate event');
    return                    _veryHigh('Strong event');
  }

  // ───────────────────────── UK DAQI (1–10 from API) ────────────────────────
  // Used by the UK DAQI card. Maps the official 1–10 index to a band.
  // 1–3 Low, 4–6 Moderate, 7–9 High, 10 Very High.
  static DaqiInfo forUkDaqiIndex(int index) {
    if (index <= 3) return _low('Low');
    if (index <= 6) return _moderate('Moderate');
    if (index <= 9) return _high('High');
    return                 _veryHigh('Very High');
  }

  // ───────────────────────── Internal helpers ───────────────────────────────
  // Construct a DaqiInfo with the correct severity colour and a metric-specific label.
  static DaqiInfo _low(String label)      => DaqiInfo(band: DaqiBand.low,      label: label, colour: AppColours.daqiLow);
  static DaqiInfo _moderate(String label) => DaqiInfo(band: DaqiBand.moderate, label: label, colour: AppColours.daqiModerate);
  static DaqiInfo _high(String label)     => DaqiInfo(band: DaqiBand.high,     label: label, colour: AppColours.daqiHigh);
  static DaqiInfo _veryHigh(String label) => DaqiInfo(band: DaqiBand.veryHigh, label: label, colour: AppColours.daqiVeryHigh);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Band scale visual specification
// ─────────────────────────────────────────────────────────────────────────────

/// Everything the [BandScale] widget needs to draw a ruler-style scale
/// for a given metric. Segments are rendered with equal width regardless
/// of the numeric range each band covers; the marker's position within
/// a segment is computed proportionally from the segment's numeric range.
class BandScaleSpec {
  /// The value at the very left edge of the visual scale.
  final double visualMin;

  /// The value at the very right edge of the visual scale.
  final double visualMax;

  /// Inner boundary values between segments (length = segmentCount − 1).
  /// For PM2.5 these are [35, 53, 70]; segments are 0→35, 35→53, 53→70, 70→visualMax.
  final List<double> innerBoundaries;

  /// One label per segment (e.g. "Low", "Moderate", "High", "Very High").
  final List<String> bandLabels;

  /// One colour per segment, in segment order.
  final List<Color> bandColours;

  /// Unit string shown next to the value on the marker (e.g. "µg/m³", "ppm").
  /// Empty for dimensionless metrics like VOC Index.
  final String unit;

  /// Show the [visualMin] number under the left edge of the bar.
  final bool showLeftEdge;

  /// Show the [visualMax] number under the right edge of the bar.
  /// Usually `false` for metrics whose top band is open-ended (e.g. PM "Very High >70").
  final bool showRightEdge;

  const BandScaleSpec({
    required this.visualMin,
    required this.visualMax,
    required this.innerBoundaries,
    required this.bandLabels,
    required this.bandColours,
    required this.unit,
    this.showLeftEdge = true,
    this.showRightEdge = false,
  });

  int get segmentCount => bandLabels.length;

  /// Default segment lookup using `value <= boundary` semantics.
  /// Metrics with different boundary semantics (e.g. Temperature uses
  /// `< 17`) should pass [segmentOverride] to [valueToPosition].
  int _defaultSegment(double value) {
    for (int i = 0; i < innerBoundaries.length; i++) {
      if (value <= innerBoundaries[i]) return i;
    }
    return segmentCount - 1;
  }

  /// Returns a position 0.0–1.0 along the bar for a given [value].
  /// If the classification function for the metric uses different
  /// boundary semantics than `<=`, pass the segment index via
  /// [segmentOverride] so the marker lands in the correct band.
  double valueToPosition(double value, {int? segmentOverride}) {
    if (value <= visualMin) return 0.0;
    if (value >= visualMax) return 1.0;
    final segment = segmentOverride ?? _defaultSegment(value);
    final segStart = segment == 0 ? visualMin : innerBoundaries[segment - 1];
    final segEnd   = segment == segmentCount - 1
        ? visualMax
        : innerBoundaries[segment];
    final segWidth = 1.0 / segmentCount;
    final posInSeg = ((value - segStart) / (segEnd - segStart)).clamp(0.0, 1.0);
    return segment * segWidth + posInSeg * segWidth;
  }

  /// Looks up the segment index for a [DaqiInfo] by matching the label
  /// against [bandLabels]. Returns `null` if no match.
  int? segmentForLabel(String label) {
    final idx = bandLabels.indexOf(label);
    return idx >= 0 ? idx : null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Per-metric scale specs
//  Used by the BandScale visual on info-sheet "Air quality scale" sections.
// ─────────────────────────────────────────────────────────────────────────────

class MetricScales {
  MetricScales._();

  static const List<Color> _fourBandColours = [
    AppColours.daqiLow,
    AppColours.daqiModerate,
    AppColours.daqiHigh,
    AppColours.daqiVeryHigh,
  ];

  // ── Particulate matter ─────────────────────────────────────────────────────
  static const BandScaleSpec pm25 = BandScaleSpec(
    visualMin:        0,
    visualMax:        100,
    innerBoundaries:  [35, 53, 70],
    bandLabels:       ['Low', 'Moderate', 'High', 'Very High'],
    bandColours:      _fourBandColours,
    unit:             'µg/m³',
    showLeftEdge:     true,
    showRightEdge:    false,
  );

  static const BandScaleSpec pm10 = BandScaleSpec(
    visualMin:        0,
    visualMax:        150,
    innerBoundaries:  [50, 75, 100],
    bandLabels:       ['Low', 'Moderate', 'High', 'Very High'],
    bandColours:      _fourBandColours,
    unit:             'µg/m³',
    showLeftEdge:     true,
    showRightEdge:    false,
  );

  static const BandScaleSpec pm1 = BandScaleSpec(
    visualMin:        0,
    visualMax:        60,
    innerBoundaries:  [21, 32, 42],
    bandLabels:       ['Low', 'Moderate', 'High', 'Very High'],
    bandColours:      _fourBandColours,
    unit:             'µg/m³',
    showLeftEdge:     true,
    showRightEdge:    false,
  );

  // ── CO₂ (3 bands) ──────────────────────────────────────────────────────────
  static const BandScaleSpec co2 = BandScaleSpec(
    visualMin:        400,
    visualMax:        2500,
    innerBoundaries:  [800, 1500],
    bandLabels:       ['Good ventilation', 'Adequate ventilation', 'Poor ventilation'],
    bandColours: [
      AppColours.daqiLow,
      AppColours.daqiModerate,
      AppColours.daqiHigh,
    ],
    unit:             'ppm',
    showLeftEdge:     true,
    showRightEdge:    false,
  );

  // ── Temperature (Goldilocks) ───────────────────────────────────────────────
  // Device measurement range: -10°C to 45°C — both edges shown.
  // Colours: amber → sage → amber → coral (Cold/Comfortable/Warm/Hot).
  static const BandScaleSpec temperature = BandScaleSpec(
    visualMin:        -10,
    visualMax:        45,
    innerBoundaries:  [17, 25, 30],
    bandLabels:       ['Cold', 'Comfortable', 'Warm', 'Hot'],
    bandColours: [
      AppColours.daqiModerate, // Cold
      AppColours.daqiLow,      // Comfortable
      AppColours.daqiModerate, // Warm
      AppColours.daqiHigh,     // Hot
    ],
    unit:             '°C',
    showLeftEdge:     true,
    showRightEdge:    true,
  );

  // ── Humidity (Goldilocks) ──────────────────────────────────────────────────
  // Natural range 0–100% — both edges shown.
  // Colours: coral → amber → sage → coral (Very dry/Dry/Comfortable/Too humid).
  static const BandScaleSpec humidity = BandScaleSpec(
    visualMin:        0,
    visualMax:        100,
    innerBoundaries:  [20, 40, 70],
    bandLabels:       ['Very dry', 'Dry', 'Comfortable', 'Too humid'],
    bandColours: [
      AppColours.daqiHigh,     // Very dry
      AppColours.daqiModerate, // Dry
      AppColours.daqiLow,      // Comfortable
      AppColours.daqiHigh,     // Too humid
    ],
    unit:             '%',
    showLeftEdge:     true,
    showRightEdge:    true,
  );

  // ── Pressure (absolute) ────────────────────────────────────────────────────
  // DPS368 sensor sensing range: 300–1200 hPa.
  // Colours: amber → sage → amber (Unusually low/Normal/Unusually high).
  static const BandScaleSpec pressure = BandScaleSpec(
    visualMin:        300,
    visualMax:        1200,
    innerBoundaries:  [990, 1030],
    bandLabels:       ['Unusually low', 'Normal', 'Unusually high'],
    bandColours: [
      AppColours.daqiModerate, // Unusually low
      AppColours.daqiLow,      // Normal
      AppColours.daqiModerate, // Unusually high
    ],
    unit:             'hPa',
    showLeftEdge:     true,
    showRightEdge:    true,
  );

  // ── Pressure change (rate of change, Pa/s) ─────────────────────────────────
  // Always shown as absolute value (rising and falling are equally uncomfortable).
  // Top band ("Uncomfortable") is open-ended; visualMax 1000 gives sensible headroom.
  static const BandScaleSpec pressureChange = BandScaleSpec(
    visualMin:        0,
    visualMax:        1000,
    innerBoundaries:  [50, 175, 600],
    bandLabels:       ['Calm', 'Mild', 'Noticeable', 'Uncomfortable'],
    bandColours:      _fourBandColours,
    unit:             'Pa/s',
    showLeftEdge:     true,
    showRightEdge:    false,
  );

  // ── VOC Index (Sensirion, 1–500) ───────────────────────────────────────────
  static const BandScaleSpec vocIndex = BandScaleSpec(
    visualMin:        1,
    visualMax:        500,
    innerBoundaries:  [150, 250, 400],
    bandLabels:       ['Low', 'Moderate', 'High', 'Very High'],
    bandColours:      _fourBandColours,
    unit:             '',
    showLeftEdge:     true,
    showRightEdge:    true,
  );

  // ── NOx Index (Sensirion, 1–500) ───────────────────────────────────────────
  static const BandScaleSpec noxIndex = BandScaleSpec(
    visualMin:        1,
    visualMax:        500,
    innerBoundaries:  [30, 150, 300],
    bandLabels:       ['Baseline', 'Mild event', 'Moderate event', 'Strong event'],
    bandColours:      _fourBandColours,
    unit:             '',
    showLeftEdge:     true,
    showRightEdge:    true,
  );
}