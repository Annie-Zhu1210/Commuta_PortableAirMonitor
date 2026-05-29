import 'package:flutter/material.dart';
import '../core/constants/app_colours.dart';

enum DeviceConnectionState { connected, disconnected }

enum BatteryState { unknown, full, high, medium, low, veryLow, charging }

class TopStatusBar extends StatelessWidget implements PreferredSizeWidget {
  final DeviceConnectionState connectionState;
  final BatteryState batteryState;

  const TopStatusBar({
    super.key,
    this.connectionState = DeviceConnectionState.disconnected,
    this.batteryState = BatteryState.unknown,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  IconData get _batteryIcon {
    switch (batteryState) {
      case BatteryState.charging:
        return Icons.battery_charging_full;
      case BatteryState.full:
        return Icons.battery_full;
      case BatteryState.high:
        return Icons.battery_6_bar;
      case BatteryState.medium:
        return Icons.battery_3_bar;
      case BatteryState.low:
        return Icons.battery_2_bar;
      case BatteryState.veryLow:
        return Icons.battery_1_bar;
      case BatteryState.unknown:
        return Icons.battery_unknown;
    }
  }

  Color get _batteryColour {
    switch (batteryState) {
      case BatteryState.charging:
        return AppColours.accent;
      case BatteryState.full:
      case BatteryState.high:
      case BatteryState.medium:
        return AppColours.textPrimary;
      case BatteryState.low:
      case BatteryState.veryLow:
        return AppColours.daqiHigh; // muted coral — draws attention
      case BatteryState.unknown:
        return AppColours.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnected = connectionState == DeviceConnectionState.connected;

    return AppBar(
      backgroundColor: AppColours.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Left side: connection status only
      leading: Padding(
        padding: const EdgeInsets.only(left: 12.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth_disabled,
              color: isConnected ? AppColours.accent : AppColours.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 4),
            Text(
              isConnected ? 'Connected' : 'Unconnected',
              style: TextStyle(
                fontSize: 11,
                color: isConnected
                    ? AppColours.textPrimary
                    : AppColours.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      leadingWidth: 120,
      // Centre: app name
      title: const Text(
        'Commuta',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColours.textPrimary,
          letterSpacing: 0.5,
        ),
      ),
      centerTitle: true,
      // Right side: battery icon only
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Icon(_batteryIcon, color: _batteryColour, size: 22),
        ),
      ],
    );
  }
}
