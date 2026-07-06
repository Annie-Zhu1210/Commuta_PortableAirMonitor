import 'package:flutter/material.dart';

import '../../../core/constants/app_colours.dart';
import '../../../services/app_services.dart';
import '../../../services/device_connection.dart';
import '../../../services/device_persistence_service.dart';
import '../../../widgets/adapter_state_banner.dart';
import '../../scan_pair/scan_pair_screen.dart';

/// Profile → Device sub-page. Reached from:
///   * The "Device" tile on the Profile tab.
///   * A tap on the top-bar status chip when a device is paired.
///
/// Renders both paired and unpaired states so forget/re-pair
/// happens in-place without navigating away.
class DeviceSectionScreen extends StatefulWidget {
  const DeviceSectionScreen({super.key});

  @override
  State<DeviceSectionScreen> createState() =>
      _DeviceSectionScreenState();
}

class _DeviceSectionScreenState extends State<DeviceSectionScreen> {
  final DeviceConnection _connection =
      AppServices.instance.deviceConnection;
  final DevicePersistenceService _persistence =
      AppServices.instance.devicePersistence;

  bool _busy = false;
  String? _errorMessage;

  Future<void> _reconnect() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await _connection.reconnect();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Reconnect failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmForget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget device?'),
        content: const Text(
          'The app will stop connecting automatically. You can pair '
          'again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColours.daqiHigh,
            ),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await _connection.forget();
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Forget failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPairScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanPairScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColours.background,
      appBar: AppBar(
        backgroundColor: AppColours.surface,
        elevation: 0,
        title: const Text(
          'Sensor device',
          style: TextStyle(
            color: AppColours.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColours.textPrimary),
      ),
      body: SafeArea(
        child: StreamBuilder<BluetoothAvailability>(
          stream: _connection.adapterStateStream,
          builder: (context, adapterSnap) {
            final adapter =
                adapterSnap.data ?? _connection.adapterState;
            return ValueListenableBuilder<bool>(
              valueListenable: _connection.pairingCompleteListenable,
              builder: (context, isPaired, _) {
                return ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    AdapterStateBanner(availability: adapter),
                    const SizedBox(height: 8),
                    if (!isPaired)
                      _NotPairedSection(
                        adapterReady:
                            adapter == BluetoothAvailability.on,
                        onPairTap: _openPairScreen,
                      )
                    else
                      _PairedSection(
                        connection: _connection,
                        persistence: _persistence,
                        busy: _busy,
                        adapterReady:
                            adapter == BluetoothAvailability.on,
                        onReconnect: _reconnect,
                        onForget: _confirmForget,
                      ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColours.daqiHigh,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Not-paired state — empty state + "Pair a device" button
// ─────────────────────────────────────────────────────────────────

class _NotPairedSection extends StatelessWidget {
  const _NotPairedSection({
    required this.adapterReady,
    required this.onPairTap,
  });

  final bool adapterReady;
  final VoidCallback onPairTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.sensors_off,
            size: 40,
            color: AppColours.textSecondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          const Text(
            'No device paired',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColours.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pair your Commuta sensor to start recording readings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColours.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: adapterReady ? onPairTap : null,
            icon: const Icon(Icons.bluetooth_searching, size: 18),
            label: const Text('Pair a device'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColours.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppColours.textSecondary.withValues(alpha: 0.2),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Paired state — status rows + reconnect / forget actions
// ─────────────────────────────────────────────────────────────────

class _PairedSection extends StatelessWidget {
  const _PairedSection({
    required this.connection,
    required this.persistence,
    required this.busy,
    required this.adapterReady,
    required this.onReconnect,
    required this.onForget,
  });

  final DeviceConnection connection;
  final DevicePersistenceService persistence;
  final bool busy;
  final bool adapterReady;
  final VoidCallback onReconnect;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Connection row ─────────────────────────────────────
        StreamBuilder<DeviceConnectionState>(
          stream: connection.stateStream,
          builder: (context, snap) {
            final state = snap.data ?? DeviceConnectionState.idle;
            return _StatusRow(
              icon: _iconForState(state),
              iconColour: _colourForState(state),
              label: 'Connection',
              value: _labelForState(state),
            );
          },
        ),
        // ── Battery ────────────────────────────────────────────
        // Prefer the value from the most recent status packet;
        // fall back to the manager's synchronous getter so the
        // very first frame after entry shows *something*.
        StreamBuilder<DeviceStatus>(
          stream: connection.statusStream,
          builder: (context, snap) {
            final pct = snap.data?.batteryPercent ??
                connection.batteryPercent;
            return _StatusRow(
              icon: Icons.battery_std,
              iconColour: AppColours.accent,
              label: 'Battery',
              value: pct == null ? '—' : '$pct%',
            );
          },
        ),
        // ── Last seen ──────────────────────────────────────────
        // Live value from the manager takes precedence; if it's
        // null (fresh session, no packets yet), fall back to the
        // persisted value from prefs so the row isn't empty for
        // the entire reconnect window.
        ValueListenableBuilder<DateTime?>(
          valueListenable: connection.lastSeenListenable,
          builder: (context, liveLastSeen, _) {
            return ValueListenableBuilder<DateTime?>(
              valueListenable: persistence.lastSeen,
              builder: (context, persistedLastSeen, __) {
                final effective = liveLastSeen ?? persistedLastSeen;
                return _StatusRow(
                  icon: Icons.access_time,
                  iconColour: AppColours.accentSecondary,
                  label: 'Last seen',
                  value: _formatRelative(effective),
                );
              },
            );
          },
        ),
        // ── Buffered count ─────────────────────────────────────
        StreamBuilder<DeviceStatus>(
          stream: connection.statusStream,
          builder: (context, snap) {
            final count = snap.data?.bufferedCount ??
                connection.bufferedCount;
            return _StatusRow(
              icon: Icons.storage_outlined,
              iconColour: AppColours.accentSecondary,
              label: 'Buffered on device',
              value: count == null ? '—' : '$count',
            );
          },
        ),
        // ── Samples not yet synced — conditional row ───────────
        // Only shown when the persisted "shutdown pending" flag is
        // set AND the device is currently reporting a non-zero
        // buffered count. The flag itself is cleared inside
        // DevicePersistenceService as soon as bufferedCount → 0.
        ValueListenableBuilder<bool>(
          valueListenable: persistence.shutdownPending,
          builder: (context, shutdownPending, _) {
            return StreamBuilder<DeviceStatus>(
              stream: connection.statusStream,
              builder: (context, snap) {
                final bufferedCount = snap.data?.bufferedCount ??
                    connection.bufferedCount;
                if (!shutdownPending ||
                    bufferedCount == null ||
                    bufferedCount == 0) {
                  return const SizedBox.shrink();
                }
                return const _StatusRow(
                  icon: Icons.info_outline,
                  iconColour: AppColours.daqiModerate,
                  label: 'Samples not yet synced',
                  value: 'Waiting for the device to reconnect and '
                      'upload.',
                  emphasise: true,
                );
              },
            );
          },
        ),
        const SizedBox(height: 16),
        // ── Actions ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed:
                    busy || !adapterReady ? null : onReconnect,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: const Text('Reconnect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColours.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColours.textSecondary
                      .withValues(alpha: 0.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : onForget,
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Forget device'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColours.daqiHigh,
                  side: BorderSide(
                    color:
                        AppColours.daqiHigh.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconForState(DeviceConnectionState s) {
    switch (s) {
      case DeviceConnectionState.connected:
        return Icons.bluetooth_connected;
      case DeviceConnectionState.scanning:
      case DeviceConnectionState.connecting:
        return Icons.bluetooth_searching;
      case DeviceConnectionState.syncingBuffered:
        return Icons.sync;
      case DeviceConnectionState.idle:
      case DeviceConnectionState.disconnected:
        return Icons.bluetooth_disabled;
    }
  }

  Color _colourForState(DeviceConnectionState s) {
    switch (s) {
      case DeviceConnectionState.connected:
      case DeviceConnectionState.syncingBuffered:
        return AppColours.accent;
      case DeviceConnectionState.scanning:
      case DeviceConnectionState.connecting:
        return AppColours.accentSecondary;
      case DeviceConnectionState.idle:
      case DeviceConnectionState.disconnected:
        return AppColours.textSecondary;
    }
  }

  String _labelForState(DeviceConnectionState s) {
    switch (s) {
      case DeviceConnectionState.connected:
        return 'Connected';
      case DeviceConnectionState.scanning:
        return 'Searching…';
      case DeviceConnectionState.connecting:
        return 'Connecting…';
      case DeviceConnectionState.syncingBuffered:
        return 'Syncing buffered data…';
      case DeviceConnectionState.idle:
        return 'Idle';
      case DeviceConnectionState.disconnected:
        return 'Offline';
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Shared status row — icon + label + value, with optional emphasis
// ─────────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.iconColour,
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final IconData icon;
  final Color iconColour;
  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: emphasise
            ? AppColours.daqiModerate.withValues(alpha: 0.08)
            : AppColours.surface,
        borderRadius: BorderRadius.circular(12),
        border: emphasise
            ? Border.all(
                color:
                    AppColours.daqiModerate.withValues(alpha: 0.3),
                width: 1,
              )
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColour),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColours.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: emphasise
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: AppColours.textPrimary,
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

/// Formats a wall-clock timestamp as a coarse relative string:
///   "Just now" / "42 sec ago" / "5 min ago" / "3 hr ago" /
///   "Yesterday" / "4 days ago" / "2026-07-06" (fallback).
///
/// Not refreshed on a timer — the parent rebuilds on every status
/// packet (≈10 s while connected), which is enough resolution for
/// this coarse-grained scale.
String _formatRelative(DateTime? dt) {
  if (dt == null) return 'Not yet';
  final delta = DateTime.now().difference(dt);
  if (delta.isNegative) return 'Just now'; // clock skew safety
  if (delta.inSeconds < 15) return 'Just now';
  if (delta.inMinutes < 1) return '${delta.inSeconds} sec ago';
  if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
  if (delta.inHours < 24) return '${delta.inHours} hr ago';
  final days = delta.inDays;
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}