import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/datasources/ble_manager.dart';
import '../services/app_services.dart';
import '../services/device_connection.dart';

/// Dev-only harness for observing the shared [BLEManager] owned by
/// [AppServices] and firing its action methods manually. Reached from
/// a debug-only FAB on the home screen; will be demoted to a
/// Settings → Diagnostics sub-page in Step 7b.
///
/// Post-cutover this screen no longer constructs its own BLEManager
/// — doing so ran a second manager instance in parallel with the
/// primary one that `AppServices` owns, and the two competed for the
/// same iOS peripheral, disrupting notifications and causing "buffered
/// frame arrived while not syncing" spam. The harness now purely
/// observes and controls the shared instance.
class BleDevHarnessScreen extends StatefulWidget {
  const BleDevHarnessScreen({super.key});

  @override
  State<BleDevHarnessScreen> createState() => _BleDevHarnessScreenState();
}

class _BleDevHarnessScreenState extends State<BleDevHarnessScreen> {
  /// Shared instance owned by [AppServices]. The cast to [BLEManager]
  /// is safe post-cutover — the harness is never entered while the
  /// mock is wired — and gives access to the diagnostic surface
  /// (`bufferedSyncProgressListenable`, `syncMaxAttempts`) that isn't
  /// on the [DeviceConnection] interface.
  final BLEManager _manager =
      AppServices.instance.deviceConnection as BLEManager;

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
            _syncSection(),
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

  Widget _syncSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Buffered sync',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Sync range is now driven by the real readings database — '
          'the manager queries ReadingsRepository.getHighestSequenceNumber '
          'on each (re)connect.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<BufferedSyncProgress?>(
          valueListenable: _manager.bufferedSyncProgressListenable,
          builder: (context, progress, _) {
            if (progress == null) {
              return const Text(
                'Buffered sync: not yet evaluated this connection',
              );
            }
            return Text(
              _formatSyncProgress(progress),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            );
          },
        ),
      ],
    );
  }

  String _formatSyncProgress(BufferedSyncProgress progress) {
    // Only show attempt suffix when a real attempt has happened
    // (attemptNumber > 0), and highlight it prominently when we're on
    // a resume (attemptNumber > 1) so retries are visible at a glance.
    final attemptSuffix = progress.attemptNumber > 0
        ? ' (attempt ${progress.attemptNumber}/${BLEManager.syncMaxAttempts})'
        : '';

    final buffer = StringBuffer()
      ..writeln('Buffered sync — ${progress.phase.name}$attemptSuffix')
      ..writeln('  started:   ${progress.startedAt.toIso8601String()}');

    if (progress.completedAt != null) {
      buffer.writeln(
        '  completed: ${progress.completedAt!.toIso8601String()}',
      );
    }
    buffer.writeln(
      '  records received: ${progress.recordsReceived}'
      '${progress.expectedTotal != null ? " / ~${progress.expectedTotal}" : ""}',
    );

    if (progress.requestedStartSeq != null) {
      buffer.writeln(
        '  requested: [${progress.requestedStartSeq}..'
        '0x${progress.requestedEndSeq!.toRadixString(16)}]',
      );
    }
    if (progress.sentCount != null) {
      buffer.writeln('  device sent: sent_count=${progress.sentCount}');
      if (progress.sentCount! > 0) {
        buffer.writeln(
          '    first_sent=${progress.firstSentSeq}, '
          'last_sent=${progress.lastSentSeq}',
        );
      }
    }
    if (progress.note != null) {
      buffer.writeln('  note: ${progress.note}');
    }

    return buffer.toString().trimRight();
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
