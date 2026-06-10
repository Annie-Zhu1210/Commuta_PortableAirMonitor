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
import 'dart:math' as math;
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

/// Distance below which two StopPoints with identical line sets are
/// treated as the same physical platform group. Paddington's two
/// Elizabeth Line StopPoints sit 82m apart; Canary Wharf DLR and
/// Heron Quays DLR (also same line, also close) sit 165m apart and
/// are genuinely different stations. 100m cleanly separates the two
/// cases.
const _dedupRadiusMetres = 100.0;

/// Distance below which a polyline point is considered to be "at" a
/// merged-away StopPoint's old position and gets snapped to the
/// surviving position. Kept small so that only genuine stop
/// coincidences are caught — at 30m, an intermediate polyline curve
/// passing near the old position by chance won't be snapped.
const _polylineSnapRadiusMetres = 30.0;

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

  // Step 3: finalise stations from the accumulator.
  final stationsFromApi = stationsById.values.map((s) {
    final lineIds = s.lineIds.toList()..sort();
    final modes = s.modes.toList()..sort();
    return {
      'id': s.id,
      'name': s.name,
      'lat': s.lat,
      'lng': s.lng,
      'lineIds': lineIds,
      'modes': modes,
    };
  }).toList()
    ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

  // Step 3.5: dedupe StopPoints that represent the same platform group,
  // and record displacements for the polyline snap pass below.
  //
  // TfL's data sometimes contains two Naptan IDs for what's
  // operationally one platform group — most notably at Paddington,
  // where "London Paddington Rail Station" (910GPADTON) and
  // "Paddington" (910GPADTLL) both refer to the same Elizabeth Line
  // platforms.
  //
  // Criterion: identical lineIds AND within [_dedupRadiusMetres]. This
  // catches the Paddington case (82m, both [elizabeth]) without
  // merging genuinely-different close stations like Canary Wharf DLR
  // and Heron Quays DLR (165m, both [dlr]).
  final stationsOutput = <Map<String, dynamic>>[];
  final displacements = <_Displacement>[];
  var mergeCount = 0;
  for (final s in stationsFromApi) {
    Map<String, dynamic>? match;
    for (final d in stationsOutput) {
      if (!_setEquals(s['lineIds'] as List, d['lineIds'] as List)) continue;
      final dist = _haversine(
        s['lat'] as double,
        s['lng'] as double,
        d['lat'] as double,
        d['lng'] as double,
      );
      if (dist < _dedupRadiusMetres) {
        match = d;
        break;
      }
    }
    if (match != null) {
      final sLat = s['lat'] as double;
      final sLng = s['lng'] as double;
      final dLat = match['lat'] as double;
      final dLng = match['lng'] as double;
      final sName = s['name'] as String;
      final dName = match['name'] as String;
      stdout.writeln('  merging "$sName" into "$dName"');

      if (_isCleanerName(sName, dName)) {
        // s wins. match's old position is displaced to s's position.
        displacements.add(_Displacement(
          oldLat: dLat,
          oldLng: dLng,
          newLat: sLat,
          newLng: sLng,
        ));
        match['id'] = s['id'];
        match['name'] = sName;
        match['lat'] = sLat;
        match['lng'] = sLng;
      } else {
        // match wins. s's position is displaced to match's position.
        displacements.add(_Displacement(
          oldLat: sLat,
          oldLng: sLng,
          newLat: dLat,
          newLng: dLng,
        ));
      }

      final modesSet = <String>{
        ...(match['modes'] as List).cast<String>(),
        ...(s['modes'] as List).cast<String>(),
      };
      match['modes'] = modesSet.toList()..sort();
      mergeCount++;
    } else {
      stationsOutput.add(Map<String, dynamic>.from(s));
    }
  }

  // Mark interchanges (line count > 1) post-dedup.
  for (final s in stationsOutput) {
    s['isInterchange'] = (s['lineIds'] as List).length > 1;
  }

  // Re-sort by name in case the cleaner-name swap changed any.
  stationsOutput
      .sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

  // Step 3.6: snap polyline points near merged-away StopPoint positions
  // to the surviving StopPoint's position. Without this, orphaned
  // polyline endpoints draw into empty space where the merged-away
  // dot used to be (visible as a "stub" line track with no station).
  var snappedCount = 0;
  if (displacements.isNotEmpty) {
    for (final line in linesOutput) {
      final polylines = line['polylines'] as List;
      for (final polyline in polylines) {
        final pts = polyline as List;
        for (var i = 0; i < pts.length; i++) {
          final pt = pts[i] as List;
          final ptLat = (pt[0] as num).toDouble();
          final ptLng = (pt[1] as num).toDouble();
          for (final d in displacements) {
            if (_haversine(ptLat, ptLng, d.oldLat, d.oldLng) <
                _polylineSnapRadiusMetres) {
              pt[0] = d.newLat;
              pt[1] = d.newLng;
              snappedCount++;
              break;
            }
          }
        }
      }
    }
  }

  final interchanges =
      stationsOutput.where((s) => s['isInterchange'] == true).length;
  stdout.writeln(
    '\nMerged $mergeCount duplicate StopPoint(s); '
    'snapped $snappedCount polyline point(s).',
  );
  stdout.writeln(
    'Aggregated ${stationsOutput.length} unique stations '
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

/// True if two lists contain the same set of strings (order-independent).
bool _setEquals(List a, List b) {
  if (a.length != b.length) return false;
  final sa = a.cast<String>().toSet();
  final sb = b.cast<String>().toSet();
  return sa.length == sb.length && sa.containsAll(sb);
}

/// Great-circle distance between two coordinates in metres (Haversine).
double _haversine(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * earthRadius * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// True if `candidate` looks like a cleaner station name than `current`
/// — i.e. fewer cosmetic markers like parenthesised disambiguation,
/// "London " prefix, or "Rail Station"/"Underground Station" suffix.
bool _isCleanerName(String candidate, String current) {
  int score(String s) {
    var n = 0;
    if (s.contains('(')) n++;
    if (s.startsWith('London ')) n++;
    if (s.endsWith(' Rail Station')) n++;
    if (s.endsWith(' Underground Station')) n++;
    return n;
  }

  return score(candidate) < score(current);
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

/// Records a position displacement created by a StopPoint merge — used
/// in Step 3.6 to snap orphaned polyline endpoints onto the surviving
/// station's position.
class _Displacement {
  _Displacement({
    required this.oldLat,
    required this.oldLng,
    required this.newLat,
    required this.newLng,
  });

  final double oldLat;
  final double oldLng;
  final double newLat;
  final double newLng;
}