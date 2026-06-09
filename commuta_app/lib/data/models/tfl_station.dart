import 'lat_lng.dart';

/// A TfL rail station, identified by its Naptan ATCO code (e.g.
/// "940GZZLUOXC" for Oxford Circus).
///
/// A station may serve multiple lines and even multiple modes — Stratford,
/// for example, serves the Central line, the Jubilee line, the DLR, the
/// Overground, and the Elizabeth Line. `isInterchange` is true whenever
/// the station serves more than one line.
class TflStation {
  final String id;
  final String name;
  final LatLng position;
  final List<String> lineIds;
  final List<String> modes;
  final bool isInterchange;

  const TflStation({
    required this.id,
    required this.name,
    required this.position,
    required this.lineIds,
    required this.modes,
    required this.isInterchange,
  });

  factory TflStation.fromJson(Map<String, dynamic> json) {
    return TflStation(
      id: json['id'] as String,
      name: json['name'] as String,
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      lineIds: (json['lineIds'] as List).cast<String>(),
      modes: (json['modes'] as List).cast<String>(),
      isInterchange: json['isInterchange'] as bool,
    );
  }
}