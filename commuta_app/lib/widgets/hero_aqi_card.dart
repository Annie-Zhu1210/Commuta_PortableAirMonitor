import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/constants/app_colours.dart';
import '../data/models/air_quality_reading.dart';
import '../services/hero_score_service.dart';

/// Hero card at the top of the Home screen — a semicircular arc gauge
/// showing an overall air-quality score.
///
/// The arc is 20 rounded-line segments spanning a 180° sweep. All 20
/// segments take the score's own palette colour ([HeroScore.colour])
/// at any given moment; the fill split shows where the score sits,
/// with the leftmost N segments at full opacity and the rest at 50%,
/// where N = max(1, round(score / 5)). At score 0 the leftmost
/// segment stays at full opacity as a visible "worst end" marker.
///
/// The scoring logic lives in [computeHeroScore]; this widget only
/// renders the result. Pass `reading: null` for the waiting state.
class HeroAqiCard extends StatelessWidget {
  final AirQualityReading? reading;

  const HeroAqiCard({super.key, this.reading});

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final heroScore = r != null ? computeHeroScore(r) : HeroScore.empty;
    final hasScore = heroScore.score != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: AppColours.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row ────────────────────────────────────────────────────
          Row(
            children: [
              if (hasScore) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: heroScore.colour,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Text(
                'Overall Air Quality',
                style: TextStyle(
                  fontSize:      17,
                  fontWeight:    FontWeight.w700,
                  color:         AppColours.textPrimary,
                  letterSpacing: 0.1,
                ),
              ),
              const Spacer(),
              if (r != null)
                Text(
                  'Updated ${_formatTime(r.timestamp)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color:    AppColours.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Arc gauge region ─────────────────────────────────────────────
          SizedBox(
            height: 200,
            child: hasScore
                ? _ArcGaugeBody(heroScore: heroScore)
                : const _WaitingBody(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Arc geometry — shared by the painter and the overlay so the arc and
//  the number/pill always line up regardless of container size.
// ─────────────────────────────────────────────────────────────────────────────
//
// A generous `rOuter` pushes the arc peak high up the card, so the
// segments arc well above the number instead of crowding against it.
// `rInnerRatio` is back at 0.80 to keep the segments visibly long.

const double _bottomMargin   = 24;   // space at the bottom for 0/100 labels
const double _rInnerRatio    = 0.80; // fraction of rOuter left empty inside
const double _widthFraction  = 0.46; // arc width as a fraction of region width
const double _heightFraction = 0.85; // arc height cap as a fraction of region height

double _computeROuter(double w, double h) =>
    math.min(w * _widthFraction, h * _heightFraction);

// ─────────────────────────────────────────────────────────────────────────────
//  Populated state — arc + number + descriptor pill + endpoint labels
// ─────────────────────────────────────────────────────────────────────────────

class _ArcGaugeBody extends StatelessWidget {
  final HeroScore heroScore;

  const _ArcGaugeBody({required this.heroScore});

  /// Darker version of [base] for text against the white card.
  /// Fixing HSL lightness at 25% handles both very light yellows
  /// (which need aggressive darkening) and already-dark reds
  /// (which only need a nudge) with one consistent rule.
  static Color _darker(Color base) {
    return HSLColor.fromColor(base).withLightness(0.25).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final Color base   = heroScore.colour ?? AppColours.textSecondary;
    final Color darker = _darker(base);
    final Color pillBg = base.withValues(alpha: 0.28);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;

        // Arc geometry — matches _ArcGaugePainter so overlays line up.
        final double cx     = w / 2;
        final double cy     = h - _bottomMargin;
        final double rOuter = _computeROuter(w, h);
        final double rInner = rOuter * _rInnerRatio;

        // Number sizing — proportional to the inner radius so it fits
        // inside the arc's empty area on any screen size.
        final double numberFontSize = (rInner * 0.45).clamp(36.0, 54.0);
        final double numberTop      = cy - rInner + 20;
        final double pillTop        = numberTop + numberFontSize + 8;

        // Endpoint label positions — centred under the arc's horizontal
        // endpoints so they read as "the arc starts at 0 here".
        final double leftEndpointX  = cx - rOuter;
        final double rightEndpointX = cx + rOuter;

        return Stack(
          children: [
            // ── Arc ────────────────────────────────────────────────────
            Positioned.fill(
              child: CustomPaint(
                painter: _ArcGaugePainter(
                  score:      heroScore.score,
                  baseColour: base,
                ),
              ),
            ),

            // ── Number ─────────────────────────────────────────────────
            Positioned(
              top:   numberTop,
              left:  0,
              right: 0,
              child: Center(
                child: Text(
                  '${heroScore.score}',
                  style: TextStyle(
                    fontSize:      numberFontSize,
                    fontWeight:    FontWeight.w600,
                    color:         darker,
                    letterSpacing: -1.5,
                    height:        1.0,
                  ),
                ),
              ),
            ),

            // ── Descriptor pill ────────────────────────────────────────
            Positioned(
              top:   pillTop,
              left:  0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical:   5,
                  ),
                  decoration: BoxDecoration(
                    color:        pillBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    heroScore.descriptor ?? '',
                    style: TextStyle(
                      fontSize:      13,
                      fontWeight:    FontWeight.w600,
                      color:         darker,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),

            // ── Endpoint labels 0 and 100 ──────────────────────────────
            Positioned(
              bottom: 4,
              left:   math.max(0, leftEndpointX - 4),
              child: Text(
                '0',
                style: TextStyle(
                  fontSize: 11,
                  color:    AppColours.textSecondary.withValues(alpha: 0.75),
                ),
              ),
            ),
            Positioned(
              bottom: 4,
              left:   math.max(0, rightEndpointX - 10),
              child: Text(
                '100',
                style: TextStyle(
                  fontSize: 11,
                  color:    AppColours.textSecondary.withValues(alpha: 0.75),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Waiting state — no reading yet
// ─────────────────────────────────────────────────────────────────────────────

class _WaitingBody extends StatelessWidget {
  const _WaitingBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '—',
          style: TextStyle(
            fontSize:   56,
            fontWeight: FontWeight.w300,
            color:      AppColours.textSecondary.withValues(alpha: 0.6),
            height:     1.0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Waiting for reading…',
          style: TextStyle(
            fontSize:  13,
            color:     AppColours.textSecondary.withValues(alpha: 0.85),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Arc gauge painter — 20 rounded-line segments in a 180° sweep
// ─────────────────────────────────────────────────────────────────────────────

class _ArcGaugePainter extends CustomPainter {
  final int?  score;
  final Color baseColour;

  static const int _segmentCount = 20;

  const _ArcGaugePainter({
    required this.score,
    required this.baseColour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (score == null) return;

    // Geometry mirrors [_ArcGaugeBody] so the arc lines up with the
    // overlaid text and pill.
    final double cx          = size.width / 2;
    final double cy          = size.height - _bottomMargin;
    final double rOuter      = _computeROuter(size.width, size.height);
    final double rInner      = rOuter * _rInnerRatio;
    final double strokeWidth = math.max(5.0, rOuter * 0.055);

    // Fill count: leftmost N segments at full opacity, the rest at
    // 50% opacity. score 0 is special-cased so the leftmost segment
    // stays visible as a "worst end" marker.
    int fillCount = (score! / 5).round();
    if (score == 0) fillCount = 1;
    fillCount = fillCount.clamp(1, _segmentCount);

    for (var i = 0; i < _segmentCount; i++) {
      // Segment angle, distributed evenly across a 180° arc from the
      // left endpoint (angle π) to the right (angle 0).
      final double t     = i / (_segmentCount - 1);
      final double theta = math.pi * (1 - t);
      final double cosT  = math.cos(theta);
      final double sinT  = math.sin(theta);

      // Canvas y grows downward, so we subtract sinT to move up.
      final Offset inner = Offset(cx + rInner * cosT, cy - rInner * sinT);
      final Offset outer = Offset(cx + rOuter * cosT, cy - rOuter * sinT);

      final bool  isFilled = i < fillCount;
      final Paint paint    = Paint()
        ..color       = baseColour.withValues(alpha: isFilled ? 1.0 : 0.5)
        ..strokeCap   = StrokeCap.round
        ..strokeWidth = strokeWidth;

      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcGaugePainter oldDelegate) {
    return oldDelegate.score      != score ||
           oldDelegate.baseColour != baseColour;
  }
}