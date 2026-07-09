import 'package:flutter/material.dart';

import '../data/models/air_quality_reading.dart';

/// Result of scoring a single [AirQualityReading] for the Home
/// screen hero card.
///
/// The hero card shows two things prominently: a numeric score in the
/// range 0–100 and a plain-English descriptor. Under the arc-gauge
/// design, both derive from the score itself: [descriptor] comes from
/// a quarter-based cutoff (Good, Moderate Pollution, High Pollution,
/// Severe Pollution) and [colour] from a ten-band palette that assigns
/// one hue to every 10-point score range. The arc widget applies that
/// palette colour uniformly across all 20 segments and uses opacity to
/// show where the score sits.
///
/// [HeroScore.empty] represents the waiting state (no reading yet).
class HeroScore {
  /// Overall score, 0–100, or null in the waiting state.
  final int? score;

  /// Descriptor word shown in the pill below the number.
  /// Null in the waiting state.
  final String? descriptor;

  /// Colour of the arc segments, number, and pill for this score.
  /// One of the ten palette entries in [_colourForScore]. Null in the
  /// waiting state.
  final Color? colour;

  /// True when at least one SGP41-derived metric (NOx or VOC) was
  /// null at compute time — i.e. the sensor was still conditioning.
  /// Not surfaced in the UI, but kept on the model for future use.
  final bool hasPartialData;

  const HeroScore({
    required this.score,
    required this.descriptor,
    required this.colour,
    required this.hasPartialData,
  });

  /// Waiting state — no reading available yet.
  static const HeroScore empty = HeroScore(
    score:          null,
    descriptor:     null,
    colour:         null,
    hasPartialData: false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  DAQI band boundaries per metric (upper bound of each named band)
// ─────────────────────────────────────────────────────────────────────────────
//
// Each metric's per-metric score is a piecewise-linear mapping from these
// boundaries to fixed anchors on the 0–100 score axis:
//
//     value = 0                → score = 100
//     value = "Low" band top   → score = 75  (top of Good descriptor range)
//     value = "Mod" band top   → score = 50  (top of Moderate Pollution)
//     value = "High" band top  → score = 25  (top of High Pollution)
//     value = 2 × "High" − "Mod" → score = 0 (top of Severe Pollution)
//
// This keeps every metric's DAQI band aligned with the same descriptor
// quarter, so "in Low DAQI band" always reads as "Good" regardless of
// which metric happens to be worst. CO₂ has only three DAQI bands and
// stops at 25 (Decision 1b — CO₂ alone can't push the card to Severe).

// PM2.5 (µg/m³): [0,35] Low, (35,53] Moderate, (53,70] High, (70,∞) Very High
const double _pm25BandLow  = 35;
const double _pm25BandMod  = 53;
const double _pm25BandHigh = 70;

// PM10 (µg/m³): [0,50] Low, (50,75] Moderate, (75,100] High, (100,∞) Very High
const double _pm10BandLow  = 50;
const double _pm10BandMod  = 75;
const double _pm10BandHigh = 100;

// CO₂ (ppm): [0,800] Good ventilation, (800,1500] Adequate, (1500,∞) Poor.
// No Very High band — CO₂'s score floors at 25.
const double _co2BandLow = 800;
const double _co2BandMod = 1500;

// NOx (SGP41 index): [0,30] Baseline, (30,150] Mild event,
//                    (150,300] Moderate, (300,∞) High
const double _noxBandLow  = 30;
const double _noxBandMod  = 150;
const double _noxBandHigh = 300;

// VOC (SGP41 index): [0,150] Low, (150,250] Moderate, (250,400] High,
//                    (400,∞) Very High
const double _vocBandLow  = 150;
const double _vocBandMod  = 250;
const double _vocBandHigh = 400;

/// Computes the hero AQI score from a single [reading].
///
/// Per-metric score maps the value into 0–100 using a piecewise linear
/// scale keyed to that metric's DAQI band boundaries. The overall
/// score is the minimum across available metrics. PM1 is intentionally
/// excluded, and NOx / VOC drop out while the SGP41 is conditioning.
///
/// The final integer is produced by `.floor()` rather than `.round()`:
/// this keeps the displayed descriptor aligned with the DAQI band the
/// worst metric is actually in. A metric that has just crossed a band
/// boundary (say PM2.5 at 53.2, which lands in the High DAQI band and
/// has a raw sub-score of 49.7) should read as the higher-pollution
/// descriptor, not be rounded back to the boundary and flip category.
HeroScore computeHeroScore(AirQualityReading reading) {
  final scores = <double>[];

  scores.add(_metricScore(
    reading.pm25,
    vLow:  _pm25BandLow,
    vMod:  _pm25BandMod,
    vHigh: _pm25BandHigh,
  ));
  scores.add(_metricScore(
    reading.pm10,
    vLow:  _pm10BandLow,
    vMod:  _pm10BandMod,
    vHigh: _pm10BandHigh,
  ));
  scores.add(_metricScore(
    reading.co2,
    vLow: _co2BandLow,
    vMod: _co2BandMod,
    // vHigh omitted — CO₂ is a three-band metric.
  ));

  var hasPartialData = false;

  final nox = reading.nox;
  if (nox != null) {
    scores.add(_metricScore(
      nox,
      vLow:  _noxBandLow,
      vMod:  _noxBandMod,
      vHigh: _noxBandHigh,
    ));
  } else {
    hasPartialData = true;
  }

  final tvoc = reading.tvoc;
  if (tvoc != null) {
    scores.add(_metricScore(
      tvoc,
      vLow:  _vocBandLow,
      vMod:  _vocBandMod,
      vHigh: _vocBandHigh,
    ));
  } else {
    hasPartialData = true;
  }

  var worst = scores.first;
  for (final s in scores.skip(1)) {
    if (s < worst) worst = s;
  }

  final overallScore = worst.floor();

  return HeroScore(
    score:          overallScore,
    descriptor:     _descriptorForScore(overallScore),
    colour:         _colourForScore(overallScore),
    hasPartialData: hasPartialData,
  );
}

/// Piecewise-linear score for a single metric. Each DAQI band maps to
/// a specific quarter of the 0–100 score range:
///
///   [0..vLow]   Low          →  100 down to 75  (Good)
///   (vLow..vMod]  Moderate   →   75 down to 50  (Moderate Pollution)
///   (vMod..vHigh] High       →   50 down to 25  (High Pollution)
///   (vHigh..∞)  Very High    →   25 down to 0   (Severe Pollution)
///
/// Pass [vHigh] as null for three-band metrics like CO₂. In that case
/// the score floors at 25 — the metric can't push the card into
/// Severe Pollution on its own.
double _metricScore(
  double value, {
  required double vLow,
  required double vMod,
  double? vHigh,
}) {
  if (value <= 0)    return 100.0;
  if (value <= vLow) return 100.0 - 25.0 * (value / vLow);
  if (value <= vMod) {
    return 75.0 - 25.0 * ((value - vLow) / (vMod - vLow));
  }

  if (vHigh == null) {
    // Three-band metric (CO₂): extrapolate past vMod at the same slope
    // as the Moderate band, and floor at 25.
    final range = vMod - vLow;
    final raw   = 50.0 - 25.0 * ((value - vMod) / range);
    return raw.clamp(25.0, 50.0);
  }

  if (value <= vHigh) {
    return 50.0 - 25.0 * ((value - vMod) / (vHigh - vMod));
  }

  // Very High band: extrapolate past vHigh at the same slope as High.
  final range = vHigh - vMod;
  final raw   = 25.0 - 25.0 * ((value - vHigh) / range);
  return raw.clamp(0.0, 25.0);
}

/// Descriptor word for the hero card's pill. Cutoffs are chosen so
/// each DAQI band lands cleanly in its descriptor quarter:
///
///   [ 0..24]  → "Severe Pollution"
///   [25..49]  → "High Pollution"
///   [50..74]  → "Moderate Pollution"
///   [75..100] → "Good"
String _descriptorForScore(int score) {
  if (score >= 75) return 'Good';
  if (score >= 50) return 'Moderate Pollution';
  if (score >= 25) return 'High Pollution';
  return 'Severe Pollution';
}

/// Ten-band colour palette, one colour per 10-point score range.
/// Applied uniformly to all 20 arc segments at any given moment; the
/// fill/fade split (rendered by the widget) shows where within the
/// arc the current score sits.
Color _colourForScore(int score) {
  if (score <= 10) return const Color.fromARGB(255, 155,  74,  66); //   0–10
  if (score <= 20) return const Color.fromARGB(255, 172,  92,  92); //  11–20
  if (score <= 30) return const Color.fromARGB(255, 204, 122, 111); //  21–30
  if (score <= 40) return const Color.fromARGB(255, 204, 150, 111); //  31–40
  if (score <= 50) return const Color.fromARGB(255, 212, 169, 106); //  41–50
  if (score <= 60) return const Color.fromARGB(255, 226, 212, 106); //  51–60
  if (score <= 70) return const Color.fromARGB(255, 212, 198, 106); //  61–70
  if (score <= 80) return const Color.fromARGB(255, 180, 196, 135); //  71–80
  if (score <= 90) return const Color.fromARGB(255, 142, 196, 135); //  81–90
  return const Color.fromARGB(255, 122, 196, 135);                   //  91–100
}