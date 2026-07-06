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
///
/// Step 6 addition: buffered sync needs to know "the highest sequence
/// number we already have" (normally supplied by
/// `ReadingsRepository.getHighestSequenceNumber`). Since this harness
/// deliberately has no repository, [_assumedHighestSeq] stands in for
/// it — a manually-editable value the tester sets before connecting, to
/// exercise the fresh-device, partial-catch-up, already-caught-up, and
/// sequence-reset paths without needing a real database.
class BleDevHarnessScreen extends StatefulWidget {
  const BleDevHarnessScreen({super.key});

  @override
  State<BleDevHarnessScreen> createState() => _BleDevHarnessScreenState();
}

class _BleDevHarnessScreenState extends State<BleDevHarnessScreen> {
  late final BLEManager _manager;
  final _assumedHighestSeqController = TextEditingController();

  /// Stand-in for `ReadingsRepository.getHighestSequenceNumber()`.
  /// Null means "simulate an empty database" — sync will request
  /// everything from sequence 0.
  int? _assumedHighestSeq;

  @override
  void initState() {
    super.initState();
    _manager = BLEManager();
    _manager.highestSequenceProvider = () async => _assumedHighestSeq;
    // Kick off start() so persisted-identifier auto-reconnect runs.
    _manager.start();
  }

  @override
  void dispose() {
    _assumedHighestSeqController.dispose();
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _assumedHighestSeqController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Assumed highest sequence we already have',
                  helperText: 'Blank = simulate an empty database',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _assumedHighestSeq = int.tryParse(value.trim());
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _assumedHighestSeqController.clear();
                setState(() => _assumedHighestSeq = null);
              },
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Applies on the next connect() — reconnect after changing this '
          'to see a different sync outcome.',
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
