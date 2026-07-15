import '../../core/utils/daqi_utils.dart';

/// Immutable models for the Home screen's "Local context" cards.
///
/// Both carry a [fetchedAt] timestamp and round-trip through JSON so
/// `LocalContextService` can cache the last successful fetch in
/// SharedPreferences and re-seed the cards instantly on cold start.
///
/// `fromJson` returns null rather than throwing on malformed input, so
/// a corrupt or legacy cache entry degrades to "no cached value" (the
/// card shows "—" until the next successful fetch) instead of crashing
/// service start-up.

// ─────────────────────────────────────────────────────────────────────────────
// Local Weather (OpenWeather)
// ─────────────────────────────────────────────────────────────────────────────

class WeatherData {
  /// Current temperature, rounded to the nearest whole degree Celsius.
  final int tempCelsius;

  /// One-word condition from OpenWeather's `weather[0].main`
  /// (e.g. "Clear", "Clouds", "Rain").
  final String condition;

  /// When this value was fetched from the API.
  final DateTime fetchedAt;

  const WeatherData({
    required this.tempCelsius,
    required this.condition,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
    'tempCelsius': tempCelsius,
    'condition': condition,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  static WeatherData? fromJson(Map<String, dynamic> json) {
    final temp = json['tempCelsius'];
    final condition = json['condition'];
    final fetchedAt = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
    if (temp is! int || condition is! String || fetchedAt == null) {
      return null;
    }
    return WeatherData(
      tempCelsius: temp,
      condition: condition,
      fetchedAt: fetchedAt,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UK DAQI (LAQN)
// ─────────────────────────────────────────────────────────────────────────────

class DaqiData {
  /// Human-readable LAQN site name (e.g. "Camden - Bloomsbury").
  final String siteName;

  /// UK DAQI index 1–10 — the worst (maximum) valid species index at
  /// the site (Session decision 12).
  final int index;

  /// Severity band derived from [index] via [bandForIndex]. Reuses the
  /// app-wide [DaqiBand] scale so the card pill shares the existing
  /// Morandi severity colours.
  final DaqiBand band;

  /// When this value was fetched from the API.
  final DateTime fetchedAt;

  const DaqiData({
    required this.siteName,
    required this.index,
    required this.band,
    required this.fetchedAt,
  });

  /// UK DAQI 1–10 → severity band (Session decision, handoff item 7):
  /// 1–3 low, 4–6 moderate, 7–9 high, 10 very high.
  static DaqiBand bandForIndex(int index) {
    if (index <= 3) return DaqiBand.low;
    if (index <= 6) return DaqiBand.moderate;
    if (index <= 9) return DaqiBand.high;
    return DaqiBand.veryHigh;
  }

  // ── Info sheet copy ─────────────────────────────────────────────────
  // Static copy lives here beside the model rather than in widget code.
  // Sources: londonair.org.uk (LAQN, Imperial College London) and the
  // DEFRA / COMEAP Daily Air Quality Index definitions — paraphrased.

  /// "What is UK DAQI?" section, personalised with the current site.
  /// Paragraphs are separated with blank lines for readability on the
  /// info sheet (the sheet's body text renders '\n\n' as a paragraph
  /// break).
  static String description(String siteName) =>
      'The UK Daily Air Quality Index (DAQI) summarises outdoor air '
      'pollution on a 1–10 scale in four bands, Low to Very High — a '
      "system recommended by COMEAP, the UK's Committee on the Medical "
      'Effects of Air Pollutants.'
      '\n\n'
      'The index reflects whichever of five pollutants currently scores '
      'worst: nitrogen dioxide, sulphur dioxide, ozone, PM2.5 and PM10.'
      '\n\n'
      'Commuta shows the latest hourly index from **$siteName**, your '
      'nearest monitoring site in the London Air Quality Network '
      "(LAQN), run by Imperial College London's Environmental Research "
      'Group since 1993.';

  /// Band-aware health guidance, paraphrased from the official COMEAP
  /// health messages published alongside the DAQI. At-risk guidance
  /// and general-population guidance sit in separate paragraphs.
  static String healthAdviceForBand(DaqiBand band) {
    switch (band) {
      case DaqiBand.low:
        return 'Air pollution is low — enjoy your usual outdoor '
            'activities.';
      case DaqiBand.moderate:
        return 'Adults and children with lung problems, and adults '
            'with heart problems, should consider easing off strenuous '
            'outdoor exercise if they notice symptoms.'
            '\n\n'
            'Everyone else can carry on as normal.';
      case DaqiBand.high:
        return 'People with lung or heart problems should reduce '
            'strenuous exertion, particularly outdoors, and especially '
            'if symptomatic. Asthma sufferers may need their reliever '
            'inhaler more often.'
            '\n\n'
            'Older people should also take it easier.'
            '\n\n'
            'Anyone with sore eyes, a cough or a sore throat should '
            'consider cutting back on outdoor activity.';
      case DaqiBand.veryHigh:
        return 'People with lung or heart problems, and older people, '
            'should avoid strenuous physical activity. Asthma '
            'sufferers may need their reliever inhaler more often.'
            '\n\n'
            'Everyone should reduce physical exertion outdoors, '
            'particularly if they notice symptoms such as a cough or '
            'a sore throat.';
    }
  }

  Map<String, dynamic> toJson() => {
    'siteName': siteName,
    'index': index,
    // Band is derivable from index, but persisting it keeps the cache
    // self-describing and survives any future banding tweak debate.
    'band': band.name,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  static DaqiData? fromJson(Map<String, dynamic> json) {
    final siteName = json['siteName'];
    final index = json['index'];
    final fetchedAt = DateTime.tryParse(json['fetchedAt'] as String? ?? '');
    if (siteName is! String || index is! int || fetchedAt == null) {
      return null;
    }
    // Re-derive the band from the index rather than trusting the stored
    // string — immune to enum renames and stale cache entries.
    return DaqiData(
      siteName: siteName,
      index: index,
      band: bandForIndex(index),
      fetchedAt: fetchedAt,
    );
  }
}