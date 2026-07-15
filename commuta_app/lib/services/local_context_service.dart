import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/api_keys.dart';
import '../core/constants/map_constants.dart';
import '../data/models/local_context.dart';
import 'location_service.dart';

/// Fetches and publishes the Home screen's "Local context" data:
/// current weather (OpenWeather) and the UK DAQI at the nearest LAQN
/// monitoring site.
///
/// Lifecycle mirrors [StationClassificationService]: constructed in
/// `AppServices.init()`, `start()`ed once, `dispose()`d on shutdown.
///
/// ── Refresh triggers (handoff decision 4) ────────────────────────────
/// Three triggers funnel into one [refresh] method that fetches both
/// sources concurrently:
///   1. Foreground — [didChangeAppLifecycleState] on resume.
///   2. Periodic  — [Timer.periodic] every 15 minutes.
///   3. Manual    — the Home screen's pull-to-refresh awaits [refresh].
/// A [_refreshInFlight] flag debounces concurrent triggers: the second
/// trigger is a no-op while a fetch is already running.
///
/// ── Failure behaviour (handoff decisions 3 + 5) ──────────────────────
/// The two sources are independent: one API's outage never blanks the
/// other card. On any failure the affected notifier keeps whatever it
/// had — the cached value from a previous success, or null ("—") if
/// this device has never fetched successfully.
///
/// ── Cache (handoff decision 5) ───────────────────────────────────────
/// The last successful [WeatherData] and [DaqiData] are stored in
/// SharedPreferences as JSON. [start] seeds both notifiers from the
/// cache synchronously before the first fetch, so a cold start renders
/// cached values immediately instead of flashing "—".
class LocalContextService with WidgetsBindingObserver {
  LocalContextService(this._prefs);

  // ── Tunables ────────────────────────────────────────────────────────

  /// How often the periodic refresh fires.
  static const Duration refreshInterval = Duration(minutes: 15);

  /// Per-request HTTP timeout (handoff decision 3).
  static const Duration requestTimeout = Duration(seconds: 10);

  /// How long a one-shot GPS fix may take before falling back to the
  /// platform's last-known position (session decision 13).
  static const Duration positionTimeout = Duration(seconds: 8);

  /// SharedPreferences cache keys (handoff decision 5).
  static const String weatherCacheKey = 'local_context_weather_v1';
  static const String daqiCacheKey = 'local_context_daqi_v1';

  /// LAQN hourly monitoring index for all London sites (Approach A —
  /// confirmed pre-session: every site entry carries decimal WGS84
  /// @Latitude / @Longitude, so no separate site-catalogue call is
  /// needed).
  static const String _laqnUrl =
      'https://api.erg.ic.ac.uk/AirQuality/Hourly/MonitoringIndex/'
      'GroupName=London/Json';

  // ── State ───────────────────────────────────────────────────────────

  final SharedPreferences _prefs;
  final http.Client _client = http.Client();

  Timer? _refreshTimer;
  bool _refreshInFlight = false;
  bool _disposed = false;

  final ValueNotifier<WeatherData?> _weather = ValueNotifier(null);
  final ValueNotifier<DaqiData?> _daqi = ValueNotifier(null);

  /// Latest weather, or null if never fetched on this device.
  ValueListenable<WeatherData?> get weather => _weather;

  /// Latest DAQI at the nearest valid LAQN site, or null if never
  /// fetched on this device.
  ValueListenable<DaqiData?> get daqi => _daqi;

  // ── Lifecycle ───────────────────────────────────────────────────────

  /// Seed the notifiers from the SharedPreferences cache, register the
  /// foreground observer, start the 15-minute periodic timer, and kick
  /// off the first fetch in the background.
  ///
  /// Cache seeding is synchronous ([SharedPreferences] reads are
  /// in-memory once the instance exists), so callers are guaranteed
  /// the cards render cached values on the very first frame.
  void start() {
    _seedFromCache();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(refreshInterval, (_) => refresh());
    unawaited(refresh());
  }

  /// Release resources. Called by `AppServices.dispose()`.
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _client.close();
    _weather.dispose();
    _daqi.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  // ── Refresh ─────────────────────────────────────────────────────────

  /// Fetch both sources concurrently. Safe to call from any trigger;
  /// concurrent calls while a fetch is in flight are no-ops.
  ///
  /// Never throws — each source catches and logs its own failures so
  /// the Home screen's `RefreshIndicator` always completes.
  Future<void> refresh() async {
    if (_refreshInFlight || _disposed) return;
    _refreshInFlight = true;
    try {
      final position = await _resolvePosition();
      await Future.wait([
        _refreshWeather(position),
        _refreshDaqi(position),
      ]);
    } finally {
      _refreshInFlight = false;
    }
  }

  /// One-shot GPS fix with a timeout, falling back to the platform's
  /// cached last-known position. Returns null when neither is
  /// available (permission denied, services off, fresh simulator...).
  ///
  /// Session decision 13: weather substitutes
  /// [MapConstants.defaultStartLat]/[defaultStartLng] for a null
  /// position (central-London weather is genuinely useful); DAQI skips
  /// its fetch entirely (a reading from a distant station isn't).
  Future<Position?> _resolvePosition() async {
    try {
      return await LocationService.getCurrentPosition().timeout(
        positionTimeout,
      );
    } catch (e) {
      debugPrint('[LocalContext] Current position unavailable: $e');
    }
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      debugPrint('[LocalContext] Last-known position unavailable: $e');
      return null;
    }
  }

  // ── Weather (OpenWeather) ───────────────────────────────────────────

  Future<void> _refreshWeather(Position? position) async {
    final lat = position?.latitude ?? MapConstants.defaultStartLat;
    final lng = position?.longitude ?? MapConstants.defaultStartLng;

    try {
      final uri = Uri.https('api.openweathermap.org', '/data/2.5/weather', {
        'lat': '$lat',
        'lon': '$lng',
        'units': 'metric',
        'appid': ApiKeys.openWeather,
      });
      final response = await _client.get(uri).timeout(requestTimeout);
      if (response.statusCode != 200) {
        debugPrint('[LocalContext] OpenWeather HTTP ${response.statusCode}');
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final temp = (json['main'] as Map<String, dynamic>?)?['temp'];
      final weatherList = json['weather'];
      final condition = (weatherList is List && weatherList.isNotEmpty)
          ? (weatherList.first as Map<String, dynamic>)['main']
          : null;
      if (temp is! num || condition is! String) {
        debugPrint('[LocalContext] OpenWeather response missing fields');
        return;
      }

      final data = WeatherData(
        tempCelsius: temp.round(),
        condition: condition,
        fetchedAt: DateTime.now(),
      );
      _weather.value = data;
      await _prefs.setString(weatherCacheKey, jsonEncode(data.toJson()));
    } catch (e) {
      // Cached value stays visible; next trigger is retry enough.
      debugPrint('[LocalContext] Weather fetch failed: $e');
    }
  }

  // ── UK DAQI (LAQN) ──────────────────────────────────────────────────

  Future<void> _refreshDaqi(Position? position) async {
    // No GPS → keep whatever the card already shows (decision 8: no
    // central-London fallback for DAQI).
    if (position == null) {
      debugPrint('[LocalContext] No position — skipping DAQI fetch');
      return;
    }

    try {
      final response = await _client
          .get(Uri.parse(_laqnUrl))
          .timeout(requestTimeout);
      if (response.statusCode != 200) {
        debugPrint('[LocalContext] LAQN HTTP ${response.statusCode}');
        return;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = _nearestValidSite(
        json,
        position.latitude,
        position.longitude,
      );
      if (data == null) {
        debugPrint('[LocalContext] LAQN: no site with a valid index');
        return;
      }

      _daqi.value = data;
      await _prefs.setString(daqiCacheKey, jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('[LocalContext] DAQI fetch failed: $e');
    }
  }

  /// Walk the LAQN response and return the nearest site that has at
  /// least one species with a valid (≥ 1) current index. The site's
  /// DAQI is the worst (maximum) valid species index (decision 12).
  ///
  /// Parser hardening (decision 11, from the verified live response):
  ///   - `Site` and `Species` may each be a single object rather than
  ///     an array — [_asList] normalises both.
  ///   - Local authorities without a `Site` key are skipped.
  ///   - All numeric fields arrive as strings; anything that fails
  ///     `tryParse` skips that site (or species) defensively.
  ///   - Index "0" / band "No data" is invalid and ignored, so the
  ///     nearest *valid* site may not be the nearest site.
  ///   - Duplicate species entries collapse harmlessly under max().
  DaqiData? _nearestValidSite(
    Map<String, dynamic> json,
    double userLat,
    double userLng,
  ) {
    final root = json['HourlyAirQualityIndex'];
    if (root is! Map<String, dynamic>) return null;

    DaqiData? best;
    var bestDistance = double.infinity;

    for (final authority in _asList(root['LocalAuthority'])) {
      if (authority is! Map<String, dynamic>) continue;

      for (final site in _asList(authority['Site'])) {
        if (site is! Map<String, dynamic>) continue;

        final lat = double.tryParse(site['@Latitude'] as String? ?? '');
        final lng = double.tryParse(site['@Longitude'] as String? ?? '');
        if (lat == null || lng == null) continue;

        var worstIndex = 0;
        for (final species in _asList(site['Species'])) {
          if (species is! Map<String, dynamic>) continue;
          final index = int.tryParse(
            species['@AirQualityIndex'] as String? ?? '',
          );
          if (index != null && index > worstIndex) worstIndex = index;
        }
        if (worstIndex < 1) continue; // all species "No data"

        final distance = _haversineMetres(userLat, userLng, lat, lng);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = DaqiData(
            siteName: (site['@SiteName'] as String? ?? 'Unknown site').trim(),
            index: worstIndex.clamp(1, 10),
            band: DaqiData.bandForIndex(worstIndex.clamp(1, 10)),
            fetchedAt: DateTime.now(),
          );
        }
      }
    }
    return best;
  }

  /// Normalise LAQN's object-or-array polymorphism: null → empty,
  /// single object → one-element list, list → itself.
  static List<dynamic> _asList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value;
    return [value];
  }

  /// Great-circle distance in metres between two WGS84 coordinates.
  static double _haversineMetres(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMetres = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusMetres * math.asin(math.sqrt(a));
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;

  // ── Cache ───────────────────────────────────────────────────────────

  /// Synchronously seed both notifiers from the last successful fetch
  /// persisted in SharedPreferences. Malformed entries degrade to null
  /// (see [WeatherData.fromJson] / [DaqiData.fromJson]).
  void _seedFromCache() {
    final weatherRaw = _prefs.getString(weatherCacheKey);
    if (weatherRaw != null) {
      try {
        _weather.value = WeatherData.fromJson(
          jsonDecode(weatherRaw) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('[LocalContext] Corrupt weather cache ignored: $e');
      }
    }

    final daqiRaw = _prefs.getString(daqiCacheKey);
    if (daqiRaw != null) {
      try {
        _daqi.value = DaqiData.fromJson(
          jsonDecode(daqiRaw) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('[LocalContext] Corrupt DAQI cache ignored: $e');
      }
    }
  }
}