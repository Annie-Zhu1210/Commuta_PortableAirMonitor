import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/datasources/ble_manager.dart';
import '../services/device_connection.dart';

/// Dev-only harness for exercising [BLEManager] in isolation before the
/// Step 7 cutover. Reached from a debug-only FAB on the home screen;
/// removed (or feature-flagged off) in Step 7 once the real pair UI and
/// Settings device section exist.
///
/// This screen constructs its own [BLEManager] instance, independent of
/// `AppServices`. Nothing here talks to the mock or to the readings
/// repository — the purpose is purely to drive the BLE code paths and
/// observe the connection-state lifecycle.
class BleDevHarnessScreen extends StatefulWidget {
  const BleDevHarnessScreen({super.key});

  @override
  State<BleDevHarnessScreen> createState() => _BleDevHarnessScreenState();
}

class _BleDevHarnessScreenState extends State<BleDevHarnessScreen> {
  late final BLEManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = BLEManager();
    // Kick off start() so persisted-identifier auto-reconnect runs.
    _manager.start();
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Dev harness disabled in release builds.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('BLE dev harness')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _stateSection(),
            const Divider(height: 32),
            _actionsSection(),
            const Divider(height: 32),
            _scanResultsSection(),
          ],
        ),
      ),
    );
  }

  Widget _stateSection() {
    return StreamBuilder<DeviceConnectionState>(
      stream: _manager.stateStream,
      initialData: _manager.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? DeviceConnectionState.idle;
        return ValueListenableBuilder<bool>(
          valueListenable: _manager.pairingCompleteListenable,
          builder: (context, paired, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('State', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Connection: ${state.name}'),
                Text('Paired: $paired'),
                Text('Battery: ${_manager.batteryPercent ?? "—"}'),
                Text('Buffered: ${_manager.bufferedCount ?? "—"}'),
                ValueListenableBuilder<DateTime?>(
                  valueListenable: _manager.lastSeenListenable,
                  builder: (context, lastSeen, _) =>
                      Text('Last seen: ${lastSeen ?? "—"}'),
                ),
                Text('Shutting-down flag received: '
                    '${_manager.shuttingDownReceived}'),
              ],
            );
          },
        );
      },
    );
  }

  Widget _actionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Actions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: () => _manager.startScan(),
              child: const Text('Start scan'),
            ),
            ElevatedButton(
              onPressed: () => _manager.stopScan(),
              child: const Text('Stop scan'),
            ),
            ElevatedButton(
              onPressed: () => _manager.reconnect(),
              child: const Text('Reconnect'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _manager.forget();
                if (mounted) setState(() {});
              },
              child: const Text('Forget'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _scanResultsSection() {
    return StreamBuilder<List<DiscoveredDevice>>(
      stream: _manager.scanResults,
      initialData: const <DiscoveredDevice>[],
      builder: (context, snapshot) {
        final devices = snapshot.data ?? const <DiscoveredDevice>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scan results (${devices.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              const Text('—')
            else
              ...devices.map(
                (d) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.name),
                  subtitle: Text('${d.identifier}\nRSSI ${d.rssi}'),
                  isThreeLine: true,
                  onTap: () async {
                    // Capture messenger synchronously before the await
                    // so the analyser doesn't flag a BuildContext use
                    // across an async gap.
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await _manager.pair(d);
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Pair failed: $e')),
                      );
                    }
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}