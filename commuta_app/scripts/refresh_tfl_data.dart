/// One-off data prep script for Commuta's Map screen.
///
/// Fetches line geometry and station metadata from the TfL Unified API
/// for all four rail modes (Tube, Overground, DLR, Elizabeth Line) and
/// writes the consolidated data to:
///   - assets/tfl/lines.json
///   - assets/tfl/stations.json
///
/// These files are bundled into the app via pubspec.yaml's `assets:`
/// declaration, so the Map screen renders fully offline at runtime.
///
/// Run with:
///   dart run scripts/refresh_tfl_data.dart
///
/// Re-run only when TfL launches a new line or significantly restructures
/// the network (happens on the order of years, not months). Commit the
/// generated JSON files to git.

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// ── Configuration ─────────────────────────────────────────────────────────

const _baseUrl = 'https://api.tfl.gov.uk';
const _railModes = ['tube', 'overground', 'dlr', 'elizabeth-line'];

/// Official TfL line colours (hex). Add new entries here if TfL launches
/// new lines or rebrands existing ones. Unknown line ids fall back to
/// `_fallbackColour` and emit a warning at run time.
///
/// As of the 2024 Overground rebrand, the single 'london-overground' line
/// was split into six named lines (Lioness, Mildmay, Windrush, Weaver,
/// Suffragette, Liberty). Both old and new ids are included below in case
/// the API exposes either form.
const _lineColours = <String, String>{
  // London Underground
  'bakerloo': '#B36305',
  'central': '#E32017',
  'circle': '#FFD300',
  'district': '#00782A',
  'hammersmith-city': '#F3A9BB',
  'jubilee': '#A0A5A9',
  'metropolitan': '#9B0056',
  'northern': '#000000',
  'piccadilly': '#003688',
  'victoria': '#0098D4',
  'waterloo-city': '#95CDBA',
  // Elizabeth Line
  'elizabeth': '#6950A1',
  // DLR
  'dlr': '#00A4A7',
  // London Overground (legacy single line + 2024 rebrand names)
  'london-overground': '#EE7C0E',
  'liberty': '#5D6061',
  'lioness': '#FAA61A',
  'mildmay': '#0093D2',
  'suffragette': '#76C04E',
  'weaver': '#A8569B',
  'windrush': '#DC241F',
};

const _fallbackColour = '#808080';

// ── Entry point ───────────────────────────────────────────────────────────

void main() async {
  stdout.writeln('Commuta TfL data refresh\n');

  final apiKey = _loadApiKey();
  if (apiKey == null) {
    stderr.writeln('TFL_API_KEY not found in .env');
    stderr.writeln('Add a line: TFL_API_KEY=your_key_here');
    exit(1);
  }

  // Step 1: list all lines across our four rail modes.
  stdout.writeln('Fetching lines for modes: ${_railModes.join(", ")}');
  final lines = await _fetchLines(apiKey);
  stdout.writeln('  ${lines.length} lines returned.\n');

  // Step 2: for each line, fetch its route sequence (geometry + stops).
  final linesOutput = <Map<String, dynamic>>[];
  final stationsById = <String, _StationAccumulator>{};

  for (final line in lines) {
    final lineId = line['id'] as String;
    final lineName = line['name'] as String;
    final modeName = line['modeName'] as String;

    stdout.write('  $lineName ($lineId) ... ');
    final sequence = await _fetchRouteSequence(lineId, apiKey);
    if (sequence == null) {
      stdout.writeln('skipped (no data)');
      continue;
    }

    // Parse line geometry. TfL returns `lineStrings` as a list of
    // JSON-encoded strings. Each string decodes to *either*:
    //   a) a single segment: [[lng, lat], [lng, lat], ...]   — rare
    //   b) a list of segments: [[[lng, lat], ...], [[lng, lat], ...], ...]
    // We handle both. TfL uses [lng, lat]; we flip to [lat, lng] in
    // our own JSON.
    final polylines = <List<List<double>>>[];
    for (final ls in (sequence['lineStrings'] as List? ?? const [])) {
      try {
        final raw = json.decode(ls as String) as List;
        if (raw.isEmpty) continue;
        final firstElem = raw.first;
        final isNestedSegments = firstElem is List &&
            firstElem.isNotEmpty &&
            firstElem.first is List;
        if (isNestedSegments) {
          for (final segment in raw) {
            final coords = _parseSegment(segment as List);
            if (coords.isNotEmpty) polylines.add(coords);
          }
        } else {
          final coords = _parseSegment(raw);
          if (coords.isNotEmpty) polylines.add(coords);
        }
      } catch (e) {
        stderr.writeln('    parse error in lineString for $lineId: $e');
      }
    }

    final colour = _lineColours[lineId] ?? _fallbackColour;
    if (_lineColours[lineId] == null) {
      stderr.writeln('    no colour mapping for "$lineId", using fallback');
    }

    linesOutput.add({
      'id': lineId,
      'name': lineName,
      'mode': modeName,
      'colour': colour,
      'polylines': polylines,
    });

    // Aggregate stations from this line's stopPointSequences.
    final sequences = sequence['stopPointSequences'] as List? ?? const [];
    var stopsAdded = 0;
    for (final sps in sequences) {
      final stops = (sps as Map)['stopPoint'] as List? ?? const [];
      for (final sp in stops) {
        final sm = sp as Map<String, dynamic>;
        final sid = sm['id'] as String?;
        final lat = sm['lat'];
        final lng = sm['lon'];
        if (sid == null || lat == null || lng == null) continue;

        final acc = stationsById.putIfAbsent(
          sid,
          () => _StationAccumulator(
            id: sid,
            name: sm['name'] as String? ?? sid,
            lat: (lat as num).toDouble(),
            lng: (lng as num).toDouble(),
          ),
        );
        acc.lineIds.add(lineId);
        final modes = (sm['modes'] as List?)?.cast<String>() ?? const [];
        acc.modes.addAll(modes);
        stopsAdded++;
      }
    }

    stdout.writeln(
      '${polylines.length} polyline(s), $stopsAdded stop entries',
    );
  }

  // Step 3: finalise stations. Deduped already; sort, mark interchanges.
  final stationsOutput = stationsById.values.map((s) {
    final lineIds = s.lineIds.toList()..sort();
    final modes = s.modes.toList()..sort();
    return {
      'id': s.id,
      'name': s.name,
      'lat': s.lat,
      'lng': s.lng,
      'lineIds': lineIds,
      'modes': modes,
      'isInterchange': lineIds.length > 1,
    };
  }).toList()
    ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

  final interchanges =
      stationsOutput.where((s) => s['isInterchange'] == true).length;
  stdout.writeln(
    '\nAggregated ${stationsOutput.length} unique stations '
    '($interchanges interchanges).',
  );

  // Step 4: write the JSON files.
  await _writeJson('assets/tfl/lines.json', linesOutput);
  await _writeJson('assets/tfl/stations.json', stationsOutput);

  stdout.writeln('\nDone.');
  stdout.writeln('  assets/tfl/lines.json    (${linesOutput.length} lines)');
  stdout.writeln(
    '  assets/tfl/stations.json (${stationsOutput.length} stations)',
  );
  stdout.writeln('\nCommit both files to git.');
}

// ── Helpers ───────────────────────────────────────────────────────────────

/// Reads the TfL API key from the project's `.env` file. We don't use
/// `flutter_dotenv` here because this script runs under plain `dart`,
/// not Flutter — no AssetBundle exists.
String? _loadApiKey() {
  final envFile = File('.env');
  if (!envFile.existsSync()) return null;
  for (final line in envFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (trimmed.startsWith('TFL_API_KEY=')) {
      return trimmed.substring('TFL_API_KEY='.length).trim();
    }
  }
  return null;
}

Future<List<Map<String, dynamic>>> _fetchLines(String apiKey) async {
  final url = Uri.parse('$_baseUrl/Line/Mode/${_railModes.join(",")}')
      .replace(queryParameters: {'app_key': apiKey});
  final response = await http.get(url);
  if (response.statusCode != 200) {
    throw Exception(
      'Lines fetch failed: HTTP ${response.statusCode}\n${response.body}',
    );
  }
  return (json.decode(response.body) as List).cast<Map<String, dynamic>>();
}

Future<Map<String, dynamic>?> _fetchRouteSequence(
  String lineId,
  String apiKey,
) async {
  final url = Uri.parse('$_baseUrl/Line/$lineId/Route/Sequence/outbound')
      .replace(queryParameters: {
    'serviceTypes': 'Regular',
    'app_key': apiKey,
  });
  final response = await http.get(url);
  if (response.statusCode != 200) {
    stderr.writeln(
      '    route sequence fetch failed for $lineId: HTTP ${response.statusCode}',
    );
    return null;
  }
  return json.decode(response.body) as Map<String, dynamic>;
}

Future<void> _writeJson(String path, Object data) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final pretty = const JsonEncoder.withIndent('  ').convert(data);
  await file.writeAsString(pretty);
}

/// Parses a single polyline segment (a list of [lng, lat] pairs in TfL's
/// order) into a list of [lat, lng] pairs in our own order.
List<List<double>> _parseSegment(List segment) {
  return segment.map<List<double>>((p) {
    final pair = p as List;
    return [
      (pair[1] as num).toDouble(), // lat
      (pair[0] as num).toDouble(), // lng
    ];
  }).toList();
}

/// Mutable accumulator used while we walk every line's stopPointSequences.
/// Converted to plain JSON-friendly maps in the final output step.
class _StationAccumulator {
  _StationAccumulator({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final double lat;
  final double lng;
  final Set<String> lineIds = <String>{};
  final Set<String> modes = <String>{};
}