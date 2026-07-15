// API keys — EXAMPLE / TEMPLATE FILE
//
// Copy this file to `api_keys.dart` in the same directory, then replace
// the placeholder below with your real OpenWeather API key from
// https://home.openweathermap.org/api_keys. The real file is gitignored;
// this example is committed so cloners know what structure to fill in.
//
// A missing or invalid key causes OpenWeather to return HTTP 401, which
// `LocalContextService` treats as a failed fetch — the Local Weather
// card keeps showing its cached value (or "—" on a fresh install).
// Newly created OpenWeather keys can take up to an hour to activate.
//
// LAQN (London Air Quality Network) requires no key, so it has no
// entry here.

/// External API keys for the Commuta app.
///
/// Keys are stored as bare strings so this file has no dependencies.
/// `LocalContextService` interpolates them into request URLs at the
/// use site.
class ApiKeys {
  ApiKeys._();

  /// OpenWeather "Current Weather Data" API key.
  static const String openWeather = 'PASTE_YOUR_OPENWEATHER_KEY_HERE';
}