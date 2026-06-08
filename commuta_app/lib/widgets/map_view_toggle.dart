import 'package:flutter/material.dart';
import '../core/constants/app_colours.dart';

/// Which of the two map views is currently shown.
enum MapViewType { google, tfl }

/// Bottom-right toggle for switching between the Google Map and the
/// TfL Underground map. Spec §2.
class MapViewToggle extends StatelessWidget {
  final MapViewType selected;
  final ValueChanged<MapViewType> onChanged;

  const MapViewToggle({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColours.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            icon: Icons.account_tree_outlined,
            label: 'Tube',
            isSelected: selected == MapViewType.tfl,
            onTap: () => onChanged(MapViewType.tfl),
          ),
          _ToggleButton(
            icon: Icons.public_outlined,
            label: 'Map',
            isSelected: selected == MapViewType.google,
            onTap: () => onChanged(MapViewType.google),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? Colors.white : AppColours.textPrimary;
    final background = isSelected ? AppColours.accent : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}