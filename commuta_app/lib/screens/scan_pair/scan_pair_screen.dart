import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colours.dart';
import '../../services/app_services.dart';
import '../../services/device_connection.dart';
import '../../widgets/adapter_state_banner.dart';

/// Full-screen scan/pair flow. Reached from:
///   * A tap on the top-bar status chip when no device is paired.
///   * The "Pair a device" button on the Device sub-page.
///
/// Scanning starts automatically on entry (only if the adapter is
/// ready) and stops on dispose. Pops with `true` on a successful
/// pair.
class ScanPairScreen extends StatefulWidget {
  const ScanPairScreen({super.key});

  @override
  State<ScanPairScreen> createState() => _ScanPairScreenState();
}

class _ScanPairScreenState extends State<ScanPairScreen> {
  final DeviceConnection _connection =
      AppServices.instance.deviceConnection;

  StreamSubscription<DeviceConnectionState>? _stateSubscription;
  bool _pairing = false;
  String? _pairError;

  @override
  void initState() {
    super.initState();
    // Watch state transitions so we can auto-pop the moment pairing
    // completes. The tile handler kicks off `pair()` and sets the
    // `_pairing` flag; when the manager transitions into `connected`
    // or `syncingBuffered` we know the handshake succeeded.
    _stateSubscription =
        _connection.stateStream.listen(_onStateChanged);
    _autoStartScan();
  }

  Future<void> _autoStartScan() async {
    // Only kick off a scan if the adapter is ready. If it isn't, the
    // inline banner takes over and the user has to open Settings.
    // Skipping the "already connected" guard on purpose — the top-bar
    // tap routes elsewhere when a device is already paired, so
    // arriving here while connected is unusual, and `startScan()` on
    // a live manager is a safe no-op on the platform side.
    if (_connection.adapterState != BluetoothAvailability.on) return;
    try {
      await _connection.startScan();
    } catch (e) {
      if (mounted) {
        setState(() => _pairError = 'Failed to start scan: $e');
      }
    }
  }

  void _onStateChanged(DeviceConnectionState state) {
    if (!mounted) return;
    if (_pairing &&
        (state == DeviceConnectionState.connected ||
            state == DeviceConnectionState.syncingBuffered)) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    // Best-effort stop scan on exit. Ignore errors — the manager
    // handles its own lifecycle.
    unawaited(_connection.stopScan());
    super.dispose();
  }

  Future<void> _pair(DiscoveredDevice device) async {
    setState(() {
      _pairing = true;
      _pairError = null;
    });
    try {
      await _connection.pair(device);
      // Auto-pop happens via `_onStateChanged` once the connection
      // completes. If `pair()` returns without triggering a state
      // change (defensive fallback), the screen sits with the
      // "Pairing…" indicator until the user backs out — safer than
      // popping optimistically.
    } catch (e) {
      if (mounted) {
        setState(() {
          _pairing = false;
          _pairError = 'Pair failed: $e';
        });
      }
    }
  }

  Future<void> _rescan() async {
    setState(() => _pairError = null);
    try {
      await _connection.stopScan();
    } catch (_) {
      // Best-effort — a failure here shouldn't block a fresh scan.
    }
    await _autoStartScan();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColours.background,
      appBar: AppBar(
        backgroundColor: AppColours.surface,
        elevation: 0,
        title: const Text(
          'Pair a device',
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
          initialData: _connection.adapterState,
          builder: (context, adapterSnap) {
            final adapter =
                adapterSnap.data ?? BluetoothAvailability.unknown;

            if (adapter != BluetoothAvailability.on) {
              // Inline treatment — banner replaces the scan controls
              // entirely, so users can't tap into a flow that can't
              // proceed.
              return Column(
                children: [
                  AdapterStateBanner(availability: adapter),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Scanning is paused until Bluetooth is ready.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColours.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'DISCOVERED DEVICES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColours.textSecondary,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      _RescanButton(
                        onTap: _rescan,
                        connection: _connection,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<DiscoveredDevice>>(
                    stream: _connection.scanResults,
                    initialData: const <DiscoveredDevice>[],
                    builder: (context, snapshot) {
                      final devices =
                          snapshot.data ?? const <DiscoveredDevice>[];
                      if (devices.isEmpty) {
                        return _EmptyScanState(connection: _connection);
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        itemCount: devices.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final d = devices[i];
                          return _DeviceTile(
                            device: d,
                            enabled: !_pairing,
                            onTap: () => _pair(d),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_pairError != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _pairError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColours.daqiHigh,
                      ),
                    ),
                  ),
                if (_pairing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 24, top: 8),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: AppColours.accent,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Pairing…',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColours.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.enabled,
    required this.onTap,
  });

  final DiscoveredDevice device;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColours.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColours.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sensors,
                  color: AppColours.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      device.name.isEmpty ? '(no name)' : device.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColours.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.identifier} · ${device.rssi} dBm',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColours.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled
                    ? AppColours.textSecondary
                    : AppColours.textSecondary.withValues(alpha: 0.4),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RescanButton extends StatelessWidget {
  const _RescanButton({required this.onTap, required this.connection});

  final VoidCallback onTap;
  final DeviceConnection connection;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DeviceConnectionState>(
      stream: connection.stateStream,
      builder: (context, snapshot) {
        final scanning =
            snapshot.data == DeviceConnectionState.scanning;
        return TextButton.icon(
          onPressed: scanning ? null : onTap,
          icon: scanning
              ? const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    color: AppColours.accent,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.refresh, size: 16),
          label: Text(scanning ? 'Scanning…' : 'Rescan'),
          style: TextButton.styleFrom(
            foregroundColor: AppColours.accent,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        );
      },
    );
  }
}

class _EmptyScanState extends StatelessWidget {
  const _EmptyScanState({required this.connection});

  final DeviceConnection connection;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DeviceConnectionState>(
      stream: connection.stateStream,
      builder: (context, snapshot) {
        final scanning =
            snapshot.data == DeviceConnectionState.scanning;
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                scanning
                    ? Icons.bluetooth_searching
                    : Icons.search_off,
                size: 40,
                color: AppColours.textSecondary.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 12),
              Text(
                scanning
                    ? 'Searching for nearby devices…'
                    : 'No devices found nearby.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColours.textSecondary,
                ),
              ),
              if (scanning) ...[
                const SizedBox(height: 12),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: AppColours.accent,
                    strokeWidth: 2,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}