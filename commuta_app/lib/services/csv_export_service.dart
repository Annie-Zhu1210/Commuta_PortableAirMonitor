import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/models/air_quality_reading.dart';
import 'tfl_map_data.dart';

/// Generates a CSV file of persisted [AirQualityReading] rows and
/// writes it to a temporary file suitable for handoff to the iOS
/// share sheet via `share_plus`.
///
/// Output shape is fixed and documented at [_columnHeaders]. Every
/// row includes the full schema (minus the internal autoincrement
/// `id`) plus two resolved-name columns — `station_name` and
/// `line_name` — populated by looking up `stationId` / `lineId`
/// against [TflMapData]. Names are blank whenever the ID is null or
/// doesn't resolve against the bundled TfL dataset.
///
/// Dialect:
///   * Comma delimiter, CRLF row terminator (RFC 4180).
///   * UTF-8 encoding with BOM (`\uFEFF`) so Excel on Windows renders
///     non-ASCII characters correctly.
///   * Fields containing comma, double quote, CR, or LF are wrapped
///     in double quotes with embedded double quotes doubled.
///   * Null cells serialise as an empty string.
///
/// Timestamp cells are ISO 8601 with local timezone offset (e.g.
/// `2026-07-07T15:23:45.123+01:00`). Drift stores DateTimes as UTC
/// internally, so [_formatTimestamp] converts to local first and
/// appends the offset manually.
///
/// The service is stateless; the singleton pattern matches
/// [TflMapData.instance] for consistency with the rest of the codebase.
class CsvExportService {
  CsvExportService._();
  static final CsvExportService instance = CsvExportService._();

  // ── RFC 4180 dialect constants ────────────────────────────────
  static const String _delimiter = ',';
  static const String _lineEnding = '\r\n';
  static const String _bom = '\uFEFF';

  /// Column headers, snake_case matching the Drift SQL column names
  /// plus two resolved-name columns interleaved next to their IDs.
  ///
  /// The internal autoincrement `id` is deliberately omitted — it has
  /// no analytical value and would bloat downstream joins.
  static const List<String> _columnHeaders = [
    'sequence_number',
    'timestamp',
    'pm1',
    'pm25',
    'pm10',
    'co2',
    'temperature',
    'humidity',
    'pressure',
    'pressure_change_pa_per_sec',
    'nox',
    'tvoc',
    'voc_raw',
    'nox_raw',
    'source_flag',
    'station_id',
    'station_name',
    'line_id',
    'line_name',
    'gps_lat',
    'gps_lng',
  ];

  /// Build a CSV of [rows] and write it to a temporary file whose
  /// name encodes [rangeLabel] and the current local time. Returns
  /// the [File] for the caller to hand off to the iOS share sheet.
  ///
  /// [rangeLabel] must be a filename-safe short slug — typically
  /// `'all'` or `'today'`. The caller is responsible for filtering
  /// [rows] to that range; this method just labels the file.
  Future<File> exportReadings({
    required List<AirQualityReading> rows,
    required String rangeLabel,
  }) async {
    // TflMapData is loaded at app startup, but calling load() again
    // is idempotent and cheap — belt-and-braces for any code path
    // that reaches the export screen before the map tab is opened.
    await TflMapData.instance.load();
    final tflData = TflMapData.instance;

    final buffer = StringBuffer()
      ..write(_bom)
      ..write(_columnHeaders.join(_delimiter))
      ..write(_lineEnding);

    for (final r in rows) {
      final stationName = r.stationId == null
          ? ''
          : (tflData.stationById(r.stationId!)?.displayName ?? '');
      final lineName = r.lineId == null
          ? ''
          : (tflData.lineById(r.lineId!)?.name ?? '');

      final cells = <String>[
        _formatInt(r.sequenceNumber),
        _formatTimestamp(r.timestamp),
        _formatDouble(r.pm1),
        _formatDouble(r.pm25),
        _formatDouble(r.pm10),
        _formatDouble(r.co2),
        _formatDouble(r.temperature),
        _formatDouble(r.humidity),
        _formatDouble(r.pressure),
        _formatNullableDouble(r.pressureChangePaPerSec),
        _formatNullableDouble(r.nox),
        _formatNullableDouble(r.tvoc),
        _formatNullableInt(r.vocRaw),
        _formatNullableInt(r.noxRaw),
        _escape(r.sourceFlag),
        _escape(r.stationId ?? ''),
        _escape(stationName),
        _escape(r.lineId ?? ''),
        _escape(lineName),
        _formatNullableDouble(r.gpsLat),
        _formatNullableDouble(r.gpsLng),
      ];
      buffer
        ..write(cells.join(_delimiter))
        ..write(_lineEnding);
    }

    final now = DateTime.now();
    final stamp = _formatFilenameTimestamp(now);
    final filename = 'commuta_readings_${rangeLabel}_$stamp.csv';

    final tmpDir = await getTemporaryDirectory();
    final file = File('${tmpDir.path}/$filename');
    await file.writeAsString(buffer.toString(), flush: true);
    return file;
  }

  // ── Cell formatting helpers ───────────────────────────────────

  /// Dart's default `int.toString()` — no localisation, no commas.
  String _formatInt(int v) => v.toString();

  /// Dart's default `double.toString()` — shortest round-trippable
  /// representation. Integer-valued doubles print as `21.0`; very
  /// small values may use `e`-notation (pandas and Excel parse both).
  String _formatDouble(double v) => v.toString();

  String _formatNullableDouble(double? v) => v == null ? '' : v.toString();

  String _formatNullableInt(int? v) => v == null ? '' : v.toString();

  /// ISO 8601 with local timezone offset, e.g.
  /// `2026-07-07T15:23:45.123+01:00`.
  ///
  /// `DateTime.toIso8601String()` on a local (`!isUtc`) DateTime does
  /// not include the offset, so it's appended manually from
  /// `timeZoneOffset`. BST vs GMT stays traceable in the exported
  /// data — important for the dissertation's exhibition-window
  /// commutes that cross the DST boundary.
  String _formatTimestamp(DateTime ts) {
    final local = ts.toLocal();
    final base = local.toIso8601String();
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final absMinutes = offset.inMinutes.abs();
    final hours = (absMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absMinutes % 60).toString().padLeft(2, '0');
    return '$base$sign$hours:$minutes';
  }

  /// `yyyyMMdd_HHmmss` in local time. Filename-safe (no colons,
  /// spaces, or slashes) so the share sheet doesn't need to rewrite it.
  String _formatFilenameTimestamp(DateTime ts) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${ts.year}${pad(ts.month)}${pad(ts.day)}_'
        '${pad(ts.hour)}${pad(ts.minute)}${pad(ts.second)}';
  }

  /// RFC 4180 escaping: only quote when necessary (comma, double
  /// quote, CR, or LF present). Embedded double quotes are doubled.
  ///
  /// Station names like "King's Cross St. Pancras" contain
  /// apostrophes but no quote-worthy characters, so they pass
  /// through untouched.
  String _escape(String value) {
    if (value.isEmpty) return '';
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\r') ||
        value.contains('\n')) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }
    return value;
  }
}