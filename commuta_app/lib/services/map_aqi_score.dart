import '../core/utils/daqi_utils.dart';
import '../data/models/air_quality_reading.dart';
import 'hero_score_service.dart';

/// The Google Map's single entry point for marker scoring.
///
/// Both the marker colour band ([computeBand]) and the number shown
/// inside the marker ([displayValue]) delegate to [computeHeroScore]
/// — the same worst-metric-normalised, DAQI-band-aware scoring that
/// drives the Home screen's hero card. Because every marker on the
/// Map screen flows through these two functions, the map and the
/// Home hero can never disagree: a score of 62 shows the same number
/// and the same severity colour on both surfaces.
///
/// The descriptor-quarter → band mapping mirrors the hero card's
/// descriptor cutoffs exactly:
///
///   score ≥ 75  → [DaqiBand.low]       (Good — sage)
///   score 50–74 → [DaqiBand.moderate]  (Moderate Pollution — amber)
///   score 25–49 → [DaqiBand.high]      (High Pollution — coral)
///   score  0–24 → [DaqiBand.veryHigh]  (Severe Pollution — deep red)
///
/// TODO(Annie): replace the body of [computeHeroScore] (in
/// hero_score_service.dart) with the commuter-weighted AQI algorithm
/// proper once it has been researched and implemented. Because this
/// class delegates rather than reimplementing, that swap upgrades the
/// map markers and the Home hero in one move — no changes needed here.
class MapAqiScore {
  MapAqiScore._();

  /// Severity band for the marker colour, derived from the hero
  /// score's descriptor quarter (see class docstring for the mapping).
  static DaqiBand computeBand(AirQualityReading reading) {
    final score = computeHeroScore(reading).score ?? 0;
    if (score >= 75) return DaqiBand.low;
    if (score >= 50) return DaqiBand.moderate;
    if (score >= 25) return DaqiBand.high;
    return DaqiBand.veryHigh;
  }

  /// The 0–100 integer shown inside the marker — the same integer the
  /// Home hero card displays for this reading. Up to three digits;
  /// [AqiMarkerBuilder] shrinks the font in the 100 case so the number
  /// still sits comfortably inside the disc.
  static int displayValue(AirQualityReading reading) {
    return computeHeroScore(reading).score ?? 0;
  }
}