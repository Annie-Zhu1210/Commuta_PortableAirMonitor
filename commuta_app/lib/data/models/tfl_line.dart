import 'package:flutter/painting.dart';
import 'lat_lng.dart';

/// A single TfL rail line: a Tube line, an Overground line, the DLR,
/// or the Elizabeth Line.
///
/// Each line is rendered as one or more polylines (branches — e.g. the
/// Northern line has the Bank and Charing Cross branches). Geometry is
/// stored in geographic (lat / lng) form and projected to canvas
/// coordinates at render time.
class TflLine {
  final String id;
  final String name;
  final String mode;
  final Color colour;
  final List<List<LatLng>> polylines;

  const TflLine({
    required this.id,
    required this.name,
    required this.mode,
    required this.colour,
    required this.polylines,
  });

  factory TflLine.fromJson(Map<String, dynamic> json) {
    // Hex → ARGB Color. Adds an opaque alpha channel ('FF') prefix.
    final hex = (json['colour'] as String).replaceFirst('#', '');
    final colour = Color(int.parse('FF$hex', radix: 16));

    final polylines = (json['polylines'] as List).map((pl) {
      return (pl as List).map((pt) {
        final pair = pt as List;
        return LatLng(
          (pair[0] as num).toDouble(),
          (pair[1] as num).toDouble(),
        );
      }).toList(growable: false);
    }).toList(growable: false);

    return TflLine(
      id: json['id'] as String,
      name: json['name'] as String,
      mode: json['mode'] as String,
      colour: colour,
      polylines: polylines,
    );
  }
}