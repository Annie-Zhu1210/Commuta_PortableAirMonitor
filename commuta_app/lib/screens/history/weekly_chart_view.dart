import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';

/// Weekly view of the History tab — Session 7b placeholder.
///
/// Session 7a builds the daily chart only; this widget keeps the
/// "Weekly" tab present in the switcher so the screen shell's layout
/// is final, while the aggregation view itself (daily min/max/average
/// lines, week picker) lands in Session 7b.
class WeeklyChartView extends StatelessWidget {
  const WeeklyChartView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_view_week_outlined,
            size: 44,
            color: AppColours.textSecondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          const Text(
            'Weekly view',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColours.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Coming soon',
            style: TextStyle(
              fontSize: 13,
              color: AppColours.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}