import 'package:flutter/material.dart';

import '../core/constants/app_colours.dart';
import '../data/models/air_quality_reading.dart';
import '../services/hero_score_service.dart';

/// Hero card at the top of the Home screen showing an overall
/// air-quality score for the latest [AirQualityReading].
///
/// Layout:
///   - Title row: "Overall Air Quality" (+ a small band-coloured dot)
///     on the left, "Updated HH:MM" on the right.
///   - Score body: a large numeric score coloured by band, with the
///     descriptor word ("Good" / "Moderate Pollution" / "High Pollution"
///     / "Severe Pollution") in the same colour underneath.
///
/// Pass `reading: null` to show the "Waiting for reading..." empty state.
/// The scoring formula lives in [computeHeroScore]; this widget only
/// renders whatever that function returns, so swapping the formula
/// doesn't require touching this file.
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
      padding: const EdgeInsets.all(24),
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
              // Subtle band-coloured indicator dot next to the title.
              // Reinforces the band beyond the coloured score number, and
              // gives colour-blind users a second cue paired with the
              // descriptor text below.
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
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColours.textPrimary,
                  letterSpacing: 0.1,
                ),
              ),
              const Spacer(),
              if (r != null)
                Text(
                  'Updated ${_formatTime(r.timestamp)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColours.textSecondary,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Score body ───────────────────────────────────────────────────
          Center(
            child: hasScore
                ? _ScoreBody(heroScore: heroScore)
                : const _WaitingBody(),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Populated state — big score number + descriptor word
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreBody extends StatelessWidget {
  final HeroScore heroScore;

  const _ScoreBody({required this.heroScore});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${heroScore.score}',
          style: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w600,
            color: heroScore.colour,
            height: 1.0,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          heroScore.descriptor ?? '',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: heroScore.colour,
            letterSpacing: 0.2,
          ),
        ),
      ],
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '—',
          style: TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w300,
            color: AppColours.textSecondary.withValues(alpha: 0.6),
            height: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Waiting for reading…',
          style: TextStyle(
            fontSize: 13,
            color: AppColours.textSecondary.withValues(alpha: 0.85),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}