import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colours.dart';
import '../../data/models/lat_lng.dart';
import '../../data/models/tfl_line.dart';
import '../../data/models/tfl_station.dart';

/// Renders the TfL rail map as a [CustomPainter].
///
/// Phase 4 — Step 5: lines, a sage halo around the currently classified
/// station (when one is set), station dots (interchanges as
/// white-filled rings with a dark outline; non-interchanges as small
/// solid dots), and zoom-aware station labels with multi-anchor
/// placement and greedy collision avoidance.
///
/// Session 4 (visited-station colouring): the painter accepts a
/// [visitedStationColours] map keyed by Naptan station ID. For each
/// entry, the station is treated as "visited today" and its dot is
/// coloured by the resolved DAQI band colour:
///   • Non-interchange visited → dot fill replaced with the band colour,
///     and the dot radius grows from [_singleDotRadius] to
///     [_singleDotVisitedRadius] so the colour is legible.
///   • Interchange visited     → existing white-filled ring kept intact,
///     with the ring stroke recoloured from the default dark stroke to
///     the band colour. Same radius and stroke width as an unvisited
///     interchange — only the stroke colour changes.
/// The classified-station sage halo and visited-station colouring are
/// orthogonal layers — both can apply to the same station at once
/// (typical mid-commute: the user is currently at a station that also
/// has readings from earlier).
///
/// Coordinates use a simple equirectangular projection — linear in lat,
/// and linear in lng with a `cos(midLat)` correction so longitude
/// degrees have the right on-screen length relative to latitude
/// degrees.
///
/// `viewScale` is the current scale factor from the surrounding
/// [InteractiveViewer]; the painter divides all on-screen dimensions
/// (stroke width, dot radius, halo radius, label gap) by it so the
/// rendered sizes stay constant regardless of zoom.
///
/// Session 5 (station tap → timestamp list → reading detail):
/// [TflMapProjector] and [TflMapBounds] were pulled out from the
/// painter's private [_Projector] / `_LatLngBounds` types so the
/// [TflMapView] can reconstruct the same projection at tap time and
/// hit-test station dots without duplicating the projection maths.
/// The painter's internal usage is unchanged.
class TflMapPainter extends CustomPainter {
  TflMapPainter({
    required this.lines,
    required this.stations,
    this.lineStrokeWidth = 2.5,
    this.padding = defaultPadding,
    this.viewScale = 1.0,
    this.classifiedStation,
    this.visitedStationColours = const {},
  }) : _bounds = TflMapBounds.forStations(stations),
       _sortedLines = _sortLinesForRendering(lines);

  final List<TflLine> lines;
  final List<TflStation> stations;
  final double lineStrokeWidth;
  final double padding;
  final double viewScale;

  /// The station the user is currently classified to, or null if no
  /// station is detected. When non-null, a sage halo is painted
  /// behind that station's dot.
  ///
  /// Resolved from a `ValueNotifier<String?>` in [TflMapView] before
  /// being passed in — the painter stays decoupled from
  /// `TflMapData`.
  final TflStation? classifiedStation;

  /// Stations that have collected data today, mapped to the DAQI band
  /// colour their dot should be painted in (worst PM band observed).
  /// Empty means no station has data today — nothing extra is drawn.
  ///
  /// Resolved from a `ValueNotifier<Map<String, DaqiBand>>` in
  /// [TflMapView] before being passed in — the painter stays
  /// decoupled from `DaqiBand` and `AppColours`.
  final Map<String, Color> visitedStationColours;

  final TflMapBounds _bounds;
  final List<TflLine> _sortedLines;

  /// Default outer padding (in canvas units at `viewScale == 1`)
  /// between the station bounding box and the widget edge. Exposed
  /// as a `static const` so [TflMapView]'s hit-test can construct a
  /// [TflMapProjector] with the same padding the painter uses.
  static const double defaultPadding = 24.0;

  // === Station dot sizing ===
  static const double _singleDotRadius = 3.0;
  /// Radius of a non-interchange dot when the station has been visited
  /// today. Enlarged so the DAQI colour is legible at the default zoom
  /// (~1.67× the unvisited radius).
  static const double _singleDotVisitedRadius = 5.0;
  static const double _interchangeRingRadius = 4.0;
  static const double _interchangeRingStrokeWidth = 1.5;

  // === Halo around currently classified station ===
  static const double _haloRadius = 35.0;
  static const double _haloOpacity = 0.5;

  // === Label styling ===
  static const double _labelFontSize = 10.0;
  static const FontWeight _labelFontWeight = FontWeight.w500;
  static const double _labelGap = 4.0;

  // === Zoom thresholds for label visibility ===
  static const double _interchangeLabelMinScale = 2.0;
  static const double _stationLabelMinScale = 6.0;

  /// Order in which label anchor positions are attempted. The first
  /// position whose rectangle doesn't collide with already-painted
  /// labels wins; if none work the label is skipped this frame.
  static const List<_LabelAnchor> _labelAnchorOrder = [
    _LabelAnchor.right,
    _LabelAnchor.above,
    _LabelAnchor.below,
    _LabelAnchor.left,
  ];

  /// Cache of laid-out [TextPainter] instances keyed by display name.
  /// Static because the painter is rebuilt every frame by
  /// `AnimatedBuilder`; an instance field would be thrown away each
  /// rebuild. Each entry is laid out once at [_labelFontSize] and then
  /// counter-scaled at paint time, so the cache never invalidates.
  static final Map<String, TextPainter> _textPainterCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    if (stations.isEmpty || _sortedLines.isEmpty) return;

    final projector = TflMapProjector(
      bounds: _bounds,
      size: size,
      padding: padding,
    );

    _drawLines(canvas, projector);
    _drawHalo(canvas, projector);
    _drawStations(canvas, projector);
  }

  void _drawLines(Canvas canvas, TflMapProjector projector) {
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

  /// Paints a single sage circle behind the classified station's dot.
  /// No-op when [classifiedStation] is null. Constant size on screen
  /// (radius divided by [viewScale], matching the rest of the painter).
  void _drawHalo(Canvas canvas, TflMapProjector projector) {
    final station = classifiedStation;
    if (station == null) return;

    final effectiveScale = viewScale > 0.01 ? viewScale : 1.0;
    final radius = _haloRadius / effectiveScale;
    final centre = projector.project(station.position);

    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color.fromARGB(166, 85, 151, 109).withValues(alpha: _haloOpacity),
          AppColours.accent.withValues(alpha: 0.15),
        ],
      ).createShader(Rect.fromCircle(center: centre, radius: radius))
      ..isAntiAlias = true;

    canvas.drawCircle(centre, radius, paint);
  }

  void _drawStations(Canvas canvas, TflMapProjector projector) {
    final effectiveScale = viewScale > 0.01 ? viewScale : 1.0;
    final singleDotRadius = _singleDotRadius / effectiveScale;
    final singleDotVisitedRadius = _singleDotVisitedRadius / effectiveScale;
    final ringRadius = _interchangeRingRadius / effectiveScale;
    final ringStrokeWidth = _interchangeRingStrokeWidth / effectiveScale;
    final gap = _labelGap / effectiveScale;

    // Reusable Paint objects for the unvisited case. Visited dots build
    // their own per-colour Paint since the colour differs by station.
    final defaultDotPaint = Paint()
      ..color = AppColours.textPrimary
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final ringFillPaint = Paint()
      ..color = AppColours.surface
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final defaultRingStrokePaint = Paint()
      ..color = AppColours.textPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringStrokeWidth
      ..isAntiAlias = true;

    // Pass 1 — dots.
    for (final station in stations) {
      final pos = projector.project(station.position);
      final visitedColour = visitedStationColours[station.id];

      if (station.isInterchange) {
        // Interchange: white fill (always), stroke recoloured to the
        // DAQI band when visited, else the default dark stroke.
        canvas.drawCircle(pos, ringRadius, ringFillPaint);
        final strokePaint = visitedColour == null
            ? defaultRingStrokePaint
            : (Paint()
              ..color = visitedColour
              ..style = PaintingStyle.stroke
              ..strokeWidth = ringStrokeWidth
              ..isAntiAlias = true);
        canvas.drawCircle(pos, ringRadius, strokePaint);
      } else {
        // Non-interchange: visited dots grow to
        // [_singleDotVisitedRadius] and take the DAQI colour; unvisited
        // dots stay small and dark.
        if (visitedColour == null) {
          canvas.drawCircle(pos, singleDotRadius, defaultDotPaint);
        } else {
          final fillPaint = Paint()
            ..color = visitedColour
            ..style = PaintingStyle.fill
            ..isAntiAlias = true;
          canvas.drawCircle(pos, singleDotVisitedRadius, fillPaint);
        }
      }
    }

    if (effectiveScale <= _interchangeLabelMinScale) return;

    // Pass 2 — labels with multi-anchor placement + collision avoidance.
    final paintedRects = <Rect>[];

    /// Try each anchor in [_labelAnchorOrder]; return the first
    /// rectangle that doesn't overlap anything already painted, or
    /// null if all of them collide.
    Rect? tryPlace(TflStation s, double dotEdge, TextPainter tp) {
      final pos = projector.project(s.position);
      final w = tp.width / effectiveScale;
      final h = tp.height / effectiveScale;
      for (final anchor in _labelAnchorOrder) {
        final rect = anchor.rectFor(pos, dotEdge, gap, w, h);
        if (!_anyOverlaps(rect, paintedRects)) return rect;
      }
      return null;
    }

    // Interchanges first, biggest first. Visited interchanges have the
    // same footprint as unvisited ones (same radius, only stroke colour
    // differs), so [ringRadius] applies unconditionally.
    final interchanges = stations.where((s) => s.isInterchange).toList()
      ..sort((a, b) => b.lineIds.length.compareTo(a.lineIds.length));
    for (final station in interchanges) {
      final tp = _getTextPainter(station.displayName);
      final rect = tryPlace(station, ringRadius, tp);
      if (rect == null) continue;
      _paintLabel(canvas, tp, rect.topLeft, effectiveScale);
      paintedRects.add(rect);
    }

    // Single-line stations — only above the higher threshold. Visited
    // non-interchanges use the larger [singleDotVisitedRadius] as the
    // label edge so the label sits outside the enlarged dot.
    if (effectiveScale > _stationLabelMinScale) {
      for (final station in stations) {
        if (station.isInterchange) continue;
        final tp = _getTextPainter(station.displayName);
        final dotEdge = visitedStationColours.containsKey(station.id)
            ? singleDotVisitedRadius
            : singleDotRadius;
        final rect = tryPlace(station, dotEdge, tp);
        if (rect == null) continue;
        _paintLabel(canvas, tp, rect.topLeft, effectiveScale);
        paintedRects.add(rect);
      }
    }
  }

  /// Looks up (or lazily builds and caches) a [TextPainter] for the
  /// given display name.
  static TextPainter _getTextPainter(String displayName) {
    final cached = _textPainterCache[displayName];
    if (cached != null) return cached;
    final tp = TextPainter(
      text: TextSpan(
        text: displayName,
        style: const TextStyle(
          fontSize: _labelFontSize,
          fontWeight: _labelFontWeight,
          color: AppColours.textPrimary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _textPainterCache[displayName] = tp;
    return tp;
  }

  static bool _anyOverlaps(Rect candidate, List<Rect> existing) {
    for (final other in existing) {
      if (candidate.overlaps(other)) return true;
    }
    return false;
  }

  static void _paintLabel(
    Canvas canvas,
    TextPainter tp,
    Offset topLeft,
    double effectiveScale,
  ) {
    canvas.save();
    canvas.translate(topLeft.dx, topLeft.dy);
    canvas.scale(1.0 / effectiveScale);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
  }

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

    final indexed = [for (var i = 0; i < lines.length; i++) (i, lines[i])];
    indexed.sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  @override
  bool shouldRepaint(covariant TflMapPainter oldDelegate) {
    return oldDelegate.lines != lines ||
        oldDelegate.stations != stations ||
        oldDelegate.lineStrokeWidth != lineStrokeWidth ||
        oldDelegate.padding != padding ||
        oldDelegate.viewScale != viewScale ||
        oldDelegate.classifiedStation != classifiedStation ||
        oldDelegate.visitedStationColours != visitedStationColours;
  }
}

/// Axis-aligned geographic bounding box in degrees (WGS84).
///
/// Session 5: promoted from the painter-private `_LatLngBounds` so
/// [TflMapView] can reconstruct the exact same projection at tap time
/// and hit-test against the projected station positions. The painter's
/// use of it is unchanged.
class TflMapBounds {
  const TflMapBounds(this.minLat, this.maxLat, this.minLng, this.maxLng);

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  /// Convenience constructor: computes the tight axis-aligned bounding
  /// box over [stations]. Returns `TflMapBounds(0, 0, 0, 0)` when the
  /// input is empty, matching the painter's prior behaviour — an empty
  /// stations list means the painter early-returns from `paint()` and
  /// the projector is never actually queried.
  factory TflMapBounds.forStations(List<TflStation> stations) {
    if (stations.isEmpty) {
      return const TflMapBounds(0, 0, 0, 0);
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
    return TflMapBounds(minLat, maxLat, minLng, maxLng);
  }
}

/// Equirectangular geographic → canvas projection used by the TfL map.
///
/// Linear in latitude, and linear in longitude with a `cos(midLat)`
/// correction so a degree of longitude has the correct on-screen
/// length relative to a degree of latitude at London's latitude.
/// The projection preserves aspect ratio and centres the map inside
/// [size] with [padding] on each edge.
///
/// Session 5: promoted from the painter-private `_Projector` so
/// [TflMapView] can construct an identical projector at tap-handling
/// time to convert station positions to canvas coordinates for
/// hit-testing. The painter's use of it (via `TflMapPainter.paint`)
/// is unchanged — same construction arguments, same `project(LatLng)`
/// behaviour.
class TflMapProjector {
  TflMapProjector({
    required TflMapBounds bounds,
    required Size size,
    required double padding,
  }) : _bounds = bounds,
       _lngScale = math.cos(
         ((bounds.minLat + bounds.maxLat) / 2) * math.pi / 180,
       ) {
    final projectedWidth = (bounds.maxLng - bounds.minLng) * _lngScale;
    final projectedHeight = bounds.maxLat - bounds.minLat;

    final availableWidth = size.width - 2 * padding;
    final availableHeight = size.height - 2 * padding;

    final scaleX = projectedWidth > 0
        ? availableWidth / projectedWidth
        : double.infinity;
    final scaleY = projectedHeight > 0
        ? availableHeight / projectedHeight
        : double.infinity;
    var scale = math.min(scaleX, scaleY);
    if (!scale.isFinite || scale <= 0) scale = 1.0;
    _scale = scale;

    _offsetX = (size.width - projectedWidth * _scale) / 2;
    _offsetY = (size.height - projectedHeight * _scale) / 2;
  }

  final TflMapBounds _bounds;
  final double _lngScale;
  late final double _scale;
  late final double _offsetX;
  late final double _offsetY;

  /// Project a geographic [LatLng] to a canvas offset. Y is flipped
  /// so increasing latitude moves upward on the canvas even though
  /// canvas y grows downward.
  Offset project(LatLng point) {
    final x =
        (point.longitude - _bounds.minLng) * _lngScale * _scale + _offsetX;
    // Flip y — latitude increases northward, canvas y increases downward.
    final y = (_bounds.maxLat - point.latitude) * _scale + _offsetY;
    return Offset(x, y);
  }
}

/// Where a label sits relative to its station dot. Tried in the order
/// declared in [TflMapPainter._labelAnchorOrder].
enum _LabelAnchor {
  right,
  above,
  below,
  left;

  Rect rectFor(
    Offset dotCentre,
    double dotEdge,
    double gap,
    double width,
    double height,
  ) {
    switch (this) {
      case _LabelAnchor.right:
        return Rect.fromLTWH(
          dotCentre.dx + dotEdge + gap,
          dotCentre.dy - height / 2,
          width,
          height,
        );
      case _LabelAnchor.above:
        return Rect.fromLTWH(
          dotCentre.dx - width / 2,
          dotCentre.dy - dotEdge - gap - height,
          width,
          height,
        );
      case _LabelAnchor.below:
        return Rect.fromLTWH(
          dotCentre.dx - width / 2,
          dotCentre.dy + dotEdge + gap,
          width,
          height,
        );
      case _LabelAnchor.left:
        return Rect.fromLTWH(
          dotCentre.dx - dotEdge - gap - width,
          dotCentre.dy - height / 2,
          width,
          height,
        );
    }
  }
}