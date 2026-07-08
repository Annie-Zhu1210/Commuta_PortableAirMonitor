import 'package:flutter/material.dart';

import '../core/constants/app_colours.dart';
import '../core/utils/daqi_utils.dart';
import '../data/models/air_quality_reading.dart';

/// The result of scoring a single [AirQualityReading] for the Home
/// screen hero card.
///
/// The hero card shows two things prominently: a numeric score in the
/// range 0–100 and a descriptor word. Both are driven by the
/// worst-scoring metric in the reading. A score of 100 is the cleanest
/// air the formula can express; 0 means at least one metric has hit or
/// passed its "Very High" band boundary.
///
/// The [HeroScore.empty] singleton represents the waiting state (no
/// reading has arrived yet); everything on it is null.
class HeroScore {
  /// Overall score, 0–100, or null in the waiting state.
  final int? score;

  /// Descriptor word shown as the secondary line on the hero card
  /// ("Good", "Moderate Pollution", "High Pollution",
  /// "Severe Pollution"). Null in the waiting state.
  final String? descriptor;

  /// Colour to use for the score and descriptor. One of the
  /// [AppColours.daqi*] palette. Null in the waiting state.
  final Color? colour;

  /// DAQI band of the metric that drove the score (worst per Plan 2).
  /// Null in the waiting state.
  final DaqiBand? band;

  /// True when at least one SGP41-derived metric (NOx or TVOC) was
  /// null at compute time — i.e. the sensor was still conditioning.
  /// Exposed for future UI use; not surfaced in Session 6.
  final bool hasPartialData;

  const HeroScore({
    required this.score,
    required this.descriptor,
    required this.colour,
    required this.band,
    required this.hasPartialData,
  });

  /// Waiting state — no reading available yet.
  static const HeroScore empty = HeroScore(
    score:          null,
    descriptor:     null,
    colour:         null,
    band:           null,
    hasPartialData: false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Very-high-start anchors (Decision 1a)
// ─────────────────────────────────────────────────────────────────────────────
//
// The per-metric score is:
//     score = 100 × max(0, 1 − value / veryHighStart)
//
// so the anchors below are the points at which each metric's contribution
// drops to zero. They coincide with the top of the "High" DAQI band for the
// four-band metrics (PM2.5, PM10, NOx, TVOC) and with the top of "Adequate
// ventilation" for CO₂, which uses a three-band scale (Decision 1b).

const double _veryHighStartPm25 = 70;    // µg/m³ — DEFRA DAQI top of High
const double _veryHighStartPm10 = 100;   // µg/m³ — DEFRA DAQI top of High
const double _veryHighStartCo2  = 1500;  // ppm   — top of Adequate ventilation
const double _veryHighStartNox  = 300;   // SGP41 index — top of Moderate event
const double _veryHighStartTvoc = 400;   // SGP41 index — top of High

/// Computes the hero AQI score for a single [reading] (Plan 2:
/// worst-metric-normalised scoring).
///
/// Metrics considered: PM2.5, PM10, CO₂, NOx index, TVOC index.
/// PM1 is intentionally excluded (Decision 1c — no official DAQI band).
/// NOx and TVOC are excluded from the score while null, i.e. while the
/// SGP41 sensor is still conditioning (Decision 4).
///
/// The overall score is the minimum across per-metric scores; the
/// overall descriptor and colour come from the DAQI band of that
/// score-driving metric. Swapping to a different algorithm later
/// (e.g. a weighted-sum Plan 1) is a single-function replacement.
HeroScore computeHeroScore(AirQualityReading reading) {
  // Every entry that participates in the score, tagged with the DAQI
  // band of its source metric so we can look up the descriptor + colour
  // once we know which one drove the overall score.
  final entries = <({double score, DaqiBand band})>[];

  entries.add((
    score: _metricScore(reading.pm25, _veryHighStartPm25),
    band:  DaqiUtils.forPm25(reading.pm25).band,
  ));
  entries.add((
    score: _metricScore(reading.pm10, _veryHighStartPm10),
    band:  DaqiUtils.forPm10(reading.pm10).band,
  ));
  entries.add((
    score: _metricScore(reading.co2, _veryHighStartCo2),
    band:  DaqiUtils.forCo2(reading.co2).band,
  ));

  var hasPartialData = false;

  final nox = reading.nox;
  if (nox != null) {
    entries.add((
      score: _metricScore(nox, _veryHighStartNox),
      band:  DaqiUtils.forNox(nox)!.band,
    ));
  } else {
    hasPartialData = true;
  }

  final tvoc = reading.tvoc;
  if (tvoc != null) {
    entries.add((
      score: _metricScore(tvoc, _veryHighStartTvoc),
      band:  DaqiUtils.forTvoc(tvoc)!.band,
    ));
  } else {
    hasPartialData = true;
  }

  // Pick the worst-scoring entry. ties don't matter — any of the
  // tied metrics will be in an equally severe band by construction.
  var worst = entries.first;
  for (final e in entries.skip(1)) {
    if (e.score < worst.score) worst = e;
  }

  return HeroScore(
    score:          worst.score.round(),
    descriptor:     _descriptorForBand(worst.band),
    colour:         _colourForBand(worst.band),
    band:           worst.band,
    hasPartialData: hasPartialData,
  );
}

/// Per-metric score: 100 × max(0, 1 − value / anchor), clamped to
/// [0, 100]. Values at or above the anchor produce 0; a value of 0
/// produces the clean-end anchor of 100.
double _metricScore(double value, double anchor) {
  final raw = 100.0 * (1.0 - value / anchor);
  return raw.clamp(0.0, 100.0);
}

/// Descriptor word for the hero card's secondary line (Decision 2a).
String _descriptorForBand(DaqiBand band) {
  switch (band) {
    case DaqiBand.low:      return 'Good';
    case DaqiBand.moderate: return 'Moderate Pollution';
    case DaqiBand.high:     return 'High Pollution';
    case DaqiBand.veryHigh: return 'Severe Pollution';
  }
}

/// Score / descriptor colour, driven by the DAQI band of the worst
/// available metric. Matches the palette used elsewhere in the app
/// so the hero card and the metric grid speak the same visual
/// language.
Color _colourForBand(DaqiBand band) {
  switch (band) {
    case DaqiBand.low:      return AppColours.daqiLow;       // sage — good
    case DaqiBand.moderate: return AppColours.daqiModerate;  // amber
    case DaqiBand.high:     return AppColours.daqiHigh;      // coral
    case DaqiBand.veryHigh: return AppColours.daqiVeryHigh;  // deep coral-red — bad
  }
}