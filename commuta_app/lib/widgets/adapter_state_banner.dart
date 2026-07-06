import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/app_colours.dart';
import '../services/device_connection.dart';

/// Full-width banner shown when the phone's Bluetooth adapter is
/// either off or lacks permission. Renders below the top status bar
/// and above the tab content in the main scaffold, and inline on
/// the scan/pair and Device screens.
///
/// When visible, the pair-flow affordances on the destination
/// screens switch to an inline treatment — this banner is the
/// always-visible cue that something needs attention regardless of
/// which tab is open.
///
/// Requires `permission_handler` in pubspec.yaml. Used to jump
/// straight to the app's own settings page, which shows the
/// Bluetooth toggle on iOS once the runtime permission has been
/// requested at least once. If the package isn't yet in the project,
/// replace the [_openSettings] body with a snackbar showing manual
/// instructions.
class AdapterStateBanner extends StatelessWidget {
  const AdapterStateBanner({
    super.key,
    required this.availability,
  });

  final BluetoothAvailability availability;

  bool get _visible =>
      availability == BluetoothAvailability.off ||
      availability == BluetoothAvailability.unauthorised;

  String get _title => availability == BluetoothAvailability.off
      ? 'Bluetooth is off'
      : 'Bluetooth permission needed';

  String get _subtitle => availability == BluetoothAvailability.off
      ? 'Turn Bluetooth on to connect to your Commuta sensor.'
      : 'Grant Commuta permission to use Bluetooth.';

  IconData get _icon => availability == BluetoothAvailability.off
      ? Icons.bluetooth_disabled
      : Icons.privacy_tip_outlined;

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return Material(
      color: AppColours.daqiHigh.withValues(alpha: 0.08),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          child: Row(
            children: [
              Icon(_icon, color: AppColours.daqiHigh, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColours.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColours.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _openSettings(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColours.daqiHigh,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    // Capture messenger synchronously so the analyser doesn't flag
    // a BuildContext use across an async gap.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final opened = await openAppSettings();
      if (!opened) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't open Settings automatically — open it "
              'manually and find Commuta.',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to open Settings: $e')),
      );
    }
  }
}