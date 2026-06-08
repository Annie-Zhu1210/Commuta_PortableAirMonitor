import 'package:flutter/material.dart';
import '../core/constants/app_colours.dart';
import '../core/utils/daqi_utils.dart';

/// Ruler-style visual band scale for a metric.
///
/// Layout (top → bottom):
///   1. Marker: value+unit text, centred above a downward triangle, positioned
///      proportionally within the band the reading falls into.
///   2. Bar: equal-width coloured segments; the band the reading falls into
///      is fully opaque, others are faded.
///   3. Boundary numbers: at the seams between segments (and on the edges if
///      requested), like ruler markings.
///   4. Band labels: one per segment, centred under the corresponding segment.
///
/// Pass [currentValue] = null when no reading is available (e.g. NOx/TVOC
/// before the SGP41 is connected) — the scale renders with no marker.
class BandScale extends StatelessWidget {
  final BandScaleSpec spec;
  final double? currentValue;
  final DaqiInfo? currentBand;

  const BandScale({
    super.key,
    required this.spec,
    this.currentValue,
    this.currentBand,
  });

  // ── Layout constants ───────────────────────────────────────────────────────
  static const double _barHeight          = 14;
  static const double _segmentGap         = 2;
  static const double _markerHeight       = 44;  // value text + triangle
  static const double _boundaryRowHeight  = 16;
  static const double _bandLabelRowHeight = 28;
  static const double _horizontalPadding  = 24;  // breathing room for marker overflow

  // Format a boundary value cleanly: drop trailing `.0` for whole numbers.
  String _formatBoundary(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  String _formatValue(double v) {
    // One decimal place for most metrics; integer for CO₂/pressure-like large numbers.
    if (v.abs() >= 100) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;

          // Compute marker position (0.0–1.0) along the bar
          double? markerPos;
          if (currentValue != null) {
            final segIdx = currentBand != null
                ? spec.segmentForLabel(currentBand!.label)
                : null;
            markerPos = spec.valueToPosition(
              currentValue!,
              segmentOverride: segIdx,
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. Marker ─────────────────────────────────────────────────
              SizedBox(
                height: _markerHeight,
                child: markerPos == null
                    ? null
                    : _buildMarker(barWidth, markerPos),
              ),

              // ── 2. Bar ────────────────────────────────────────────────────
              _buildBar(),

              const SizedBox(height: 6),

              // ── 3. Boundary numbers ───────────────────────────────────────
              SizedBox(
                height: _boundaryRowHeight,
                child: _buildBoundaryRow(barWidth),
              ),

              const SizedBox(height: 2),

              // ── 4. Band labels ────────────────────────────────────────────
              SizedBox(
                height: _bandLabelRowHeight,
                child: _buildBandLabelRow(),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Marker (value+unit text above downward triangle) ───────────────────────
  Widget _buildMarker(double barWidth, double position) {
    final value = currentValue!;
    final unit = spec.unit;
    final colour = currentBand?.colour ?? AppColours.textPrimary;

    final valueText = unit.isEmpty
        ? _formatValue(value)
        : '${_formatValue(value)} $unit';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: position * barWidth,
          top: 0,
          child: FractionalTranslation(
            translation: const Offset(-0.5, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Value + unit text
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    valueText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colour,
                      height: 1.2,
                    ),
                  ),
                ),

                const SizedBox(height: 2),

                // Downward triangle pointing at the bar
                CustomPaint(
                  size: const Size(10, 8),
                  painter: _TrianglePainter(colour: colour),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── Coloured segment bar ───────────────────────────────────────────────────
  Widget _buildBar() {
    final n = spec.segmentCount;
    final activeIndex = currentBand != null
        ? spec.segmentForLabel(currentBand!.label)
        : null;

    return Row(
      children: List.generate(n, (i) {
        final isActive = i == activeIndex;
        final isFirst = i == 0;
        final isLast = i == n - 1;
        final colour = spec.bandColours[i];

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left:  isFirst ? 0 : _segmentGap / 2,
              right: isLast  ? 0 : _segmentGap / 2,
            ),
            child: Container(
              height: _barHeight,
              decoration: BoxDecoration(
                color: isActive
                    ? colour
                    : colour.withValues(alpha: 0.35),
                borderRadius: BorderRadius.horizontal(
                  left:  isFirst ? const Radius.circular(6) : Radius.zero,
                  right: isLast  ? const Radius.circular(6) : Radius.zero,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ─── Boundary numbers row (ruler markings) ──────────────────────────────────
  Widget _buildBoundaryRow(double barWidth) {
    final List<_BoundaryLabel> labels = [];

    if (spec.showLeftEdge) {
      labels.add(_BoundaryLabel(
        position: 0.0,
        text:     _formatBoundary(spec.visualMin),
        alignAtEdge: _EdgeAlign.left,
      ));
    }

    for (int i = 0; i < spec.innerBoundaries.length; i++) {
      final pos = (i + 1) / spec.segmentCount;
      labels.add(_BoundaryLabel(
        position: pos,
        text:     _formatBoundary(spec.innerBoundaries[i]),
        alignAtEdge: _EdgeAlign.centre,
      ));
    }

    if (spec.showRightEdge) {
      labels.add(_BoundaryLabel(
        position: 1.0,
        text:     _formatBoundary(spec.visualMax),
        alignAtEdge: _EdgeAlign.right,
      ));
    }

    return Stack(
      clipBehavior: Clip.none,
      children: labels.map((bl) {
        // Use FractionalTranslation to centre text on its position,
        // except for the left/right edges which align to the edge.
        final translationX = switch (bl.alignAtEdge) {
          _EdgeAlign.left   => 0.0,
          _EdgeAlign.right  => -1.0,
          _EdgeAlign.centre => -0.5,
        };

        return Positioned(
          left: bl.position * barWidth,
          top:  0,
          child: FractionalTranslation(
            translation: Offset(translationX, 0),
            child: Text(
              bl.text,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColours.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Band labels row (centred under each segment) ───────────────────────────
  Widget _buildBandLabelRow() {
    final activeIndex = currentBand != null
        ? spec.segmentForLabel(currentBand!.label)
        : null;

    return Row(
      children: List.generate(spec.segmentCount, (i) {
        final isActive = i == activeIndex;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              spec.bandLabels[i],
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? spec.bandColours[i]
                    : AppColours.textSecondary,
                height: 1.2,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Private helpers
// ─────────────────────────────────────────────────────────────────────────────

enum _EdgeAlign { left, centre, right }

class _BoundaryLabel {
  final double position;
  final String text;
  final _EdgeAlign alignAtEdge;

  const _BoundaryLabel({
    required this.position,
    required this.text,
    required this.alignAtEdge,
  });
}

class _TrianglePainter extends CustomPainter {
  final Color colour;
  _TrianglePainter({required this.colour});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.colour != colour;
}