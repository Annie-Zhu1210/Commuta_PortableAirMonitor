import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../data/models/lat_lng.dart';
import '../../data/models/tfl_line.dart';
import '../../data/models/tfl_station.dart';

/// Renders the TfL rail map as a [CustomPainter].
///
/// Phase 4 — Step 3: lines only. Station dots and labels come in Step 4.
///
/// Coordinates use a simple equirectangular projection — linear in lat,
/// and linear in lng with a `cos(midLat)` correction so longitude degrees
/// have the right on-screen length relative to latitude degrees.
///
/// `viewScale` is the current scale factor from the surrounding
/// [InteractiveViewer]; the painter divides its stroke width by it so
/// lines stay a constant thickness on screen regardless of zoom.
class TflMapPainter extends CustomPainter {
  TflMapPainter({
    required this.lines,
    required this.stations,
    this.lineStrokeWidth = 2.5,
    this.padding = 24.0,
    this.viewScale = 1.0,
  })  : _bounds = _computeBounds(stations),
        _sortedLines = _sortLinesForRendering(lines);

  final List<TflLine> lines;
  final List<TflStation> stations;
  final double lineStrokeWidth;
  final double padding;

  /// The current [InteractiveViewer] scale. Used to keep strokes a
  /// constant on-screen thickness regardless of zoom.
  final double viewScale;

  final _LatLngBounds _bounds;
  final List<TflLine> _sortedLines;

  @override
  void paint(Canvas canvas, Size size) {
    if (stations.isEmpty || _sortedLines.isEmpty) return;

    final projector = _Projector(
      bounds: _bounds,
      size: size,
      padding: padding,
    );

    _drawLines(canvas, projector);
  }

  void _drawLines(Canvas canvas, _Projector projector) {
    // Strokes are painted into a canvas that the [InteractiveViewer] then
    // scales by `viewScale`, so divide here to keep on-screen width
    // constant. Guard against zero / tiny values just in case.
    final effectiveStrokeWidth =
        lineStrokeWidth / (viewScale > 0.01 ? viewScale : 1.0);

    for (final line in _sortedLines) {
      final paint = Paint()
        ..color = line.colour
        ..strokeWidth = effectiveStrokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      for (final polyline in line.polylines) {
        if (polyline.length < 2) continue;

        final path = Path();
        final first = projector.project(polyline.first);
        path.moveTo(first.dx, first.dy);
        for (var i = 1; i < polyline.length; i++) {
          final p = projector.project(polyline[i]);
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  /// Sorts lines so non-Tube modes paint first and Tube paints on top.
  /// Within a mode the original JSON order is preserved.
  static List<TflLine> _sortLinesForRendering(List<TflLine> lines) {
    int rank(TflLine l) {
      switch (l.mode) {
        case 'overground':
          return 0;
        case 'elizabeth-line':
          return 1;
        case 'dlr':
          return 2;
        case 'tube':
          return 3;
        default:
          return 4;
      }
    }

    // Stable-ish sort: indexed pairs keep original order on ties.
    final indexed = [
      for (var i = 0; i < lines.length; i++) (i, lines[i]),
    ];
    indexed.sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  static _LatLngBounds _computeBounds(List<TflStation> stations) {
    if (stations.isEmpty) {
      return const _LatLngBounds(0, 0, 0, 0);
    }
    var minLat = stations.first.position.latitude;
    var maxLat = minLat;
    var minLng = stations.first.position.longitude;
    var maxLng = minLng;
    for (final s in stations) {
      final lat = s.position.latitude;
      final lng = s.position.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }
    return _LatLngBounds(minLat, maxLat, minLng, maxLng);
  }

  @override
  bool shouldRepaint(covariant TflMapPainter oldDelegate) {
    return oldDelegate.lines != lines ||
        oldDelegate.stations != stations ||
        oldDelegate.lineStrokeWidth != lineStrokeWidth ||
        oldDelegate.padding != padding ||
        oldDelegate.viewScale != viewScale;
  }
}

class _LatLngBounds {
  const _LatLngBounds(this.minLat, this.maxLat, this.minLng, this.maxLng);
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
}

class _Projector {
  _Projector({
    required _LatLngBounds bounds,
    required Size size,
    required double padding,
  })  : _bounds = bounds,
        _lngScale =
            math.cos(((bounds.minLat + bounds.maxLat) / 2) * math.pi / 180) {
    final projectedWidth = (bounds.maxLng - bounds.minLng) * _lngScale;
    final projectedHeight = bounds.maxLat - bounds.minLat;

    final availableWidth = size.width - 2 * padding;
    final availableHeight = size.height - 2 * padding;

    final scaleX =
        projectedWidth > 0 ? availableWidth / projectedWidth : double.infinity;
    final scaleY = projectedHeight > 0
        ? availableHeight / projectedHeight
        : double.infinity;
    var scale = math.min(scaleX, scaleY);
    if (!scale.isFinite || scale <= 0) scale = 1.0;
    _scale = scale;

    _offsetX = (size.width - projectedWidth * _scale) / 2;
    _offsetY = (size.height - projectedHeight * _scale) / 2;
  }

  final _LatLngBounds _bounds;
  final double _lngScale;
  late final double _scale;
  late final double _offsetX;
  late final double _offsetY;

  Offset project(LatLng point) {
    final x =
        (point.longitude - _bounds.minLng) * _lngScale * _scale + _offsetX;
    // Flip y — latitude increases northward, canvas y increases downward.
    final y = (_bounds.maxLat - point.latitude) * _scale + _offsetY;
    return Offset(x, y);
  }
}