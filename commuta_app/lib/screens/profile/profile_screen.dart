import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';
import '../../dev/ble_dev_harness_screen.dart';
import 'data_export/data_export_screen.dart';
import 'device/device_section_screen.dart';

/// Profile tab.
///
/// Scaffolded as a simple sectioned list. The Device section
/// (Sensor device) and the Data section (Export data) are both
/// functional; the Preferences section (Alerts, Account) is
/// stubbed with "coming soon" tiles so the layout is visible but
/// the tiles aren't tappable. The Developer section only exists in
/// debug builds and is where the BLE dev harness now lives after
/// being demoted from its Step 6 spot on the Home FAB.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColours.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            // ── Device ───────────────────────────────────────────
            const _SectionHeader('Device'),
            _ProfileTile(
              icon: Icons.sensors,
              iconColour: AppColours.accent,
              title: 'Sensor device',
              subtitle:
                  'Pair, reconnect, and check battery and buffered data.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DeviceSectionScreen(),
                ),
              ),
            ),

            // ── Data ─────────────────────────────────────────────
            const SizedBox(height: 16),
            const _SectionHeader('Data'),
            _ProfileTile(
              icon: Icons.download_outlined,
              iconColour: AppColours.accent,
              title: 'Export data',
              subtitle:
                  'Save readings as a CSV to share or open elsewhere.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DataExportScreen(),
                ),
              ),
            ),

            // ── Preferences (placeholders for future work) ──────
            const SizedBox(height: 16),
            const _SectionHeader('Preferences'),
            const _ComingSoonTile(
              icon: Icons.notifications_outlined,
              title: 'Alerts',
              subtitle: 'Threshold-based notifications — coming soon.',
            ),
            const _ComingSoonTile(
              icon: Icons.person_outline,
              title: 'Account',
              subtitle: 'Sign-in and cloud sync — coming soon.',
            ),

            // ── Developer (debug builds only) ───────────────────
            // `kDebugMode` is a const tree-shaken to false in
            // release builds, so this whole section vanishes from
            // the production binary.
            if (kDebugMode) ...[
              const SizedBox(height: 16),
              const _SectionHeader('Developer'),
              _ProfileTile(
                icon: Icons.bug_report_outlined,
                iconColour: AppColours.accentSecondary,
                title: 'Diagnostics',
                subtitle:
                    'BLE dev harness — observe and control the shared BLE manager.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BleDevHarnessScreen(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColours.textSecondary,
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.iconColour,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColour;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColours.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColour.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 18, color: iconColour),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColours.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColours.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColours.textSecondary,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  const _ComingSoonTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColours.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColours.textSecondary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: AppColours.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColours.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColours.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}