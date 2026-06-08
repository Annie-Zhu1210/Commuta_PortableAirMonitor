import 'package:flutter/material.dart';
import '../../core/constants/app_colours.dart';

/// Placeholder for the TfL Underground map view.
/// Built out in Phase 4 (base rendering) and Phase 5 (auto-classification).
class TflMapView extends StatelessWidget {
  const TflMapView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColours.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 48,
              color: AppColours.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'Tube map',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColours.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Coming in Phase 4',
              style: TextStyle(
                fontSize: 13,
                color: AppColours.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}