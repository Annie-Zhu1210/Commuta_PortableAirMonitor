import 'package:flutter/material.dart';

import '../core/constants/app_colours.dart';
import '../services/device_connection.dart';

// Note: this file previously declared its own two-value
// `DeviceConnectionState { connected, disconnected }` enum, which
// silently shadowed the six-value enum in `device_connection.dart`.
// The status bar now uses the real enum, so callers should import
// `DeviceConnectionState` from `services/device_connection.dart`.

/// Battery band derived from a raw 0–100 percentage. Kept as an
/// enum (rather than switching on numbers inline) so the icon and
/// colour mappings can stay collocated and readable.
enum BatteryState {
  unknown,
  full,
  high,
  medium,
  low,
  veryLow,
  charging,
}

/// The top status bar shown across every tab of the main scaffold.
///
/// Left side: a tappable status chip showing the current connection
/// state. Right side: the device battery, banded from the raw
/// percentage. Centre: the app name.
///
/// Consumers should feed live values from [DeviceConnection.stateStream],
/// [DeviceConnection.pairingCompleteListenable], and
/// [DeviceConnection.statusStream] rather than passing static values
/// — the scaffold wires this up.
class TopStatusBar extends StatelessWidget implements PreferredSizeWidget {
  const TopStatusBar({
    super.key,
    required this.connectionState,
    required this.isPaired,
    this.batteryPercent,
    this.onTap,
  });

  /// Current lifecycle state of the connection to the physical
  /// Commuta device. Sourced from [DeviceConnection.stateStream].
  final DeviceConnectionState connectionState;

  /// True once a device has been paired to this app install, from
  /// [DeviceConnection.pairingCompleteListenable]. Combined with
  /// [connectionState] to distinguish "never paired" (grey, "Not
  /// paired") from "was paired, currently offline" (grey, "Offline").
  final bool isPaired;

  /// Raw battery percentage from the most recent status packet, or
  /// null if no status packet has arrived. Mapped to a [BatteryState]
  /// band internally.
  final int? batteryPercent;

  /// Tap handler on the leading status chip. Wired in the main
  /// scaffold to route to the scan/pair screen when unpaired, or
  /// to the Device sub-page when paired.
  final VoidCallback? onTap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  // ── Status chip visuals ─────────────────────────────────────────

  IconData get _statusIcon {
    switch (connectionState) {
      case DeviceConnectionState.scanning:
      case DeviceConnectionState.connecting:
        return Icons.bluetooth_searching;
      case DeviceConnectionState.connected:
        return Icons.bluetooth_connected;
      case DeviceConnectionState.syncingBuffered:
        return Icons.sync;
      case DeviceConnectionState.idle:
      case DeviceConnectionState.disconnected:
        return Icons.bluetooth_disabled;
    }
  }

  Color get _statusColour {
    switch (connectionState) {
      case DeviceConnectionState.scanning:
      case DeviceConnectionState.connecting:
      case DeviceConnectionState.connected:
      case DeviceConnectionState.syncingBuffered:
        return AppColours.accent;
      case DeviceConnectionState.idle:
      case DeviceConnectionState.disconnected:
        return AppColours.textSecondary;
    }
  }

  String get _statusLabel {
    switch (connectionState) {
      case DeviceConnectionState.scanning:
        return 'Searching…';
      case DeviceConnectionState.connecting:
        return 'Connecting…';
      case DeviceConnectionState.connected:
        return 'Connected';
      case DeviceConnectionState.syncingBuffered:
        return 'Syncing…';
      case DeviceConnectionState.idle:
      case DeviceConnectionState.disconnected:
        return isPaired ? 'Offline' : 'Not paired';
    }
  }

  Color get _statusLabelColour {
    switch (connectionState) {
      case DeviceConnectionState.idle:
      case DeviceConnectionState.disconnected:
        return AppColours.textSecondary;
      case DeviceConnectionState.scanning:
      case DeviceConnectionState.connecting:
      case DeviceConnectionState.connected:
      case DeviceConnectionState.syncingBuffered:
        return AppColours.textPrimary;
    }
  }

  // ── Battery visuals ────────────────────────────────────────────

  BatteryState get _batteryState {
    final pct = batteryPercent;
    if (pct == null) return BatteryState.unknown;
    if (pct >= 86) return BatteryState.full;
    if (pct >= 61) return BatteryState.high;
    if (pct >= 31) return BatteryState.medium;
    if (pct >= 16) return BatteryState.low;
    return BatteryState.veryLow;
  }

  IconData get _batteryIcon {
    switch (_batteryState) {
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
    switch (_batteryState) {
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
    return AppBar(
      backgroundColor: AppColours.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      // ── Leading: tappable status chip ────────────────────────
      leading: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_statusIcon, color: _statusColour, size: 20),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _statusLabel,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: _statusLabelColour,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // Slightly wider than before — labels like "Connecting…" need
      // room without ellipsing on the first character.
      leadingWidth: 130,
      // ── Centre: app name ─────────────────────────────────────
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
      // ── Right: battery icon ──────────────────────────────────
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Icon(_batteryIcon, color: _batteryColour, size: 22),
        ),
      ],
    );
  }
}