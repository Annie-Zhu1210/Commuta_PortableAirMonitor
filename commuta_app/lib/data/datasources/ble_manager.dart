import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/ble_uuids.dart';
import '../../services/device_connection.dart';
import '../models/air_quality_reading.dart';
import 'air_quality_datasource.dart';
import 'ble_packet_parser.dart';

// ── Buffered sync progress (dev-only surface) ────────────────────────────

/// Life-cycle phase of a buffered catch-up sync attempt.
///
/// Deliberately just two states: `active` while records are flowing (or
/// while a resume attempt is being kicked off), `completed` for every
/// terminal outcome (success, skipped, timed out after all attempts).
/// Detail lives in the other fields of [BufferedSyncProgress] —
/// [BufferedSyncProgress.sentCount] and the reconciliation seqs on
/// success, or [BufferedSyncProgress.note] on a skip or a giveup.
enum BufferedSyncPhase { active, completed }

/// Snapshot of buffered-sync state, published on
/// [BLEManager.bufferedSyncProgressListenable] for the dev harness.
///
/// Not part of the [DeviceConnection] interface — production UI reads
/// the coarser [DeviceConnection.stateStream] (`syncingBuffered` vs
/// `connected`) and doesn't need this level of detail. Kept public so
/// the harness screen (which imports `BLEManager` directly) can render
/// a diagnostic panel without additional plumbing.
class BufferedSyncProgress {
  const BufferedSyncProgress({
    required this.phase,
    required this.startedAt,
    required this.recordsReceived,
    required this.attemptNumber,
    this.expectedTotal,
    this.completedAt,
    this.sentCount,
    this.firstSentSeq,
    this.lastSentSeq,
    this.requestedStartSeq,
    this.requestedEndSeq,
    this.note,
  });

  final BufferedSyncPhase phase;
  final DateTime startedAt;
  final DateTime? completedAt;

  /// Records received on the Buffered stream since [startedAt], counted
  /// across every resume attempt in this session.
  final int recordsReceived;

  /// Best guess at the total records to be sent, computed at first
  /// sync start as `newestBufferedSeq − startSeq + 1`. Approximate —
  /// the device may clamp the range, and buffered records don't
  /// necessarily occupy every integer sequence value.
  final int? expectedTotal;

  /// `sent_count` field of the EOS frame. Populated on successful
  /// [BufferedSyncPhase.completed]; null on active or on skip/timeout.
  final int? sentCount;
  final int? firstSentSeq;
  final int? lastSentSeq;

  /// Range as requested by the phone in the sync-request write for the
  /// current or most recent attempt.
  final int? requestedStartSeq;
  final int? requestedEndSeq;

  /// Diagnostic message. Set for skipped syncs (e.g. "already caught
  /// up", "firmware sequence reset detected") and for the final
  /// give-up after every retry attempt is exhausted. Null on active
  /// and on clean success.
  final String? note;

  /// The attempt number of the current (or final) sync attempt this
  /// session. Starts at 1 for the initial attempt; increments each
  /// time [BLEManager] resumes after a heartbeat timeout, up to a
  /// maximum of [BLEManager.syncMaxAttempts]. Zero for skipped syncs
  /// that never issued a request.
  final int attemptNumber;
}

/// Real BLE implementation of [AirQualityDataSource] and [DeviceConnection].
///
/// See BLE_Integration_Plan.md for the full context. Step 6 adds the
/// catch-up sync protocol: on `connected`, once both a first Live
/// packet (anchor set) and a first Status packet (`newest_buffered_seq`
/// known) have landed, the manager decides whether to request the
/// device's flash buffer. Records arriving on the Buffered
/// characteristic are time-stamped by projecting backwards from the
/// most recent live-arrival anchor and emitted on the buffered-only
/// stream so UI surfaces showing "current reading" are not disturbed.
///
/// Auto-resume: if the buffered stream goes silent for
/// [_syncHeartbeatTimeout] before EOS arrives (usually because the
/// firmware's outgoing notification queue back-pressured a frame we
/// never see the retry of), the manager writes a fresh sync request
/// starting from just after the last record it did receive, up to
/// [syncMaxAttempts] times per session before giving up. This makes the
/// phone side robust to firmware-side drops even if the firmware fix
/// isn't perfect.
class BLEManager implements AirQualityDataSource, DeviceConnection {
  static const String _prefsKey = 'commuta_paired_peripheral_id';

  static const Duration _scanTimeout = Duration(seconds: 10);
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const Duration _autoReconnectTimeout = Duration(seconds: 10);
  static const Duration _autoReconnectScanTimeout = Duration(seconds: 12);
  static const int _targetMtu = 247;

  /// Device sample cadence (matches the firmware). Used to convert
  /// hPa deltas into Pa/s for `pressureChangePaPerSec` and to project
  /// buffered timestamps back from the live anchor.
  static const double _samplingIntervalSec = 10.0;
  static const int _samplingIntervalSecInt = 10;

  /// Sentinel written for `end_seq` in a sync request meaning "to
  /// newest available". Matches the firmware's interpretation in
  /// `firmware/ble.h`.
  static const int _syncEndSeqSentinel = 0xFFFFFFFF;

  /// Silence tolerance for a single sync attempt. If no Buffered frame
  /// arrives for this long, the manager treats the current attempt as
  /// stalled and either resumes (if [syncMaxAttempts] not yet
  /// exhausted) or gives up for the session.
  static const Duration _syncHeartbeatTimeout = Duration(seconds: 30);

  /// Maximum number of sync attempts per connection session. Each
  /// attempt gets its own [_syncHeartbeatTimeout] window; on timeout,
  /// the manager writes a fresh sync request starting from just after
  /// the highest sequence received across any prior attempt. Chosen at
  /// 3 to bound wasted airtime while still recovering from a couple of
  /// transient firmware drops.
  static const int syncMaxAttempts = 3;

  bool _started = false;
  DeviceConnectionState _currentState = DeviceConnectionState.idle;
  final _stateController = StreamController<DeviceConnectionState>.broadcast();

  final ValueNotifier<bool> _pairingComplete = ValueNotifier<bool>(false);
  final ValueNotifier<DateTime?> _lastSeenNotifier = ValueNotifier<DateTime?>(
    null,
  );
  bool _shuttingDownReceived = false;

  int? _batteryPercent;
  int? _bufferedCount;
  AirQualityReading? _latestReading;
  DeviceStatus? _latestStatus;

  /// Previous Live-packet pressure in hPa, used to compute
  /// `pressureChangePaPerSec` on the following sample. Nulled on
  /// teardown so the first sample of each fresh (re)connect emits
  /// `pressureChangePaPerSec = null`, per the plan.
  double? _previousPressure;

  /// Most recent (sequence, wall-clock) pair for a Live packet.
  /// Updated on every valid Live notification. Step 6 reads this
  /// fresh at back-fill time (Decision 8A) to time-stamp each
  /// buffered record:
  ///   buffered_ts = anchor.arrival − (anchor.seq − buffered.seq) × 10 s
  /// Nulled on teardown so a stale anchor from a previous connection
  /// cannot be applied to a fresh sync.
  ({int seq, DateTime arrival})? _liveArrivalAnchor;

  String? _persistedIdentifier;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _liveCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;
  BluetoothCharacteristic? _bufferedCharacteristic;

  final _liveReadingsController =
      StreamController<AirQualityReading>.broadcast();
  final _bufferedReadingsController =
      StreamController<AirQualityReading>.broadcast();
  final _statusController = StreamController<DeviceStatus>.broadcast();
  final _scanResultsController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  /// Broadcast controller for [adapterStateStream]. Populated from
  /// `FlutterBluePlus.adapterState` in [start], mapped through
  /// [_mapAdapterState] onto our library-agnostic
  /// [BluetoothAvailability] enum. Never emits until `start()` runs,
  /// so `pumpAndSettle` in tests doesn't wait on it.
  final _adapterStateController =
      StreamController<BluetoothAvailability>.broadcast();
  BluetoothAvailability _currentAdapterState = BluetoothAvailability.unknown;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _liveNotificationSubscription;
  StreamSubscription<List<int>>? _statusNotificationSubscription;
  StreamSubscription<List<int>>? _bufferedNotificationSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  // ── Sync state (all cleared in _teardownConnection) ────────────────────

  /// Provides the largest `sequenceNumber` currently in the readings
  /// DB (or null if empty). Wired in by `AppServices` in Step 7 as
  /// `bleManager.highestSequenceProvider = repo.getHighestSequenceNumber`.
  /// If left null (e.g. the dev harness didn't wire it), sync is
  /// skipped with a diagnostic log and the connection continues to
  /// deliver Live readings normally.
  Future<int?> Function()? highestSequenceProvider;

  /// True once the first Live notification of the current connection
  /// has arrived. Together with [_firstStatusReceived] this gates the
  /// sync-decision step.
  bool _firstLiveReceived = false;
  bool _firstStatusReceived = false;

  /// Latches once [_maybeStartSync] has run so its DB query and
  /// request write happen at most once per connection.
  bool _syncEvaluated = false;

  /// True once EOS has been received (or a terminal skip / giveup
  /// occurred). Prevents any re-evaluation within the same session.
  /// Cleared in `_teardownConnection` so a fresh reconnect syncs again.
  bool _syncCompletedThisSession = false;

  /// Range last written to the Buffered characteristic. Updated on
  /// each resume attempt so EOS reconciliation logs reflect the most
  /// recent request, not the original one.
  ({int start, int end})? _lastRequestedRange;

  /// Records received on the Buffered stream since sync began, counted
  /// across every resume attempt this session.
  int _recordsReceivedThisSync = 0;

  /// Highest sequence number seen across any attempt this session.
  /// Auto-resume uses `_lastReceivedBufferedSeq + 1` as the new
  /// startSeq to avoid re-fetching records already received.
  int? _lastReceivedBufferedSeq;

  /// 1-based attempt counter within the current session. Zero when
  /// no sync has been attempted yet (e.g. skipped or before evaluation).
  int _syncAttemptNumber = 0;

  /// When the first attempt of this session started, preserved across
  /// resume attempts so the harness shows total elapsed time.
  DateTime? _syncSessionStartedAt;

  /// `expectedTotal` computed at the first attempt, preserved across
  /// resumes so the progress ratio doesn't reset every retry.
  int? _syncExpectedTotal;

  /// Watchdog: cancelled and re-armed on every Buffered notification.
  /// Fires only after [_syncHeartbeatTimeout] of silence.
  Timer? _syncHeartbeatTimer;

  /// Progress snapshot for the dev harness. Kept after sync ends so
  /// the harness can render "last sync" details until the next attempt.
  final ValueNotifier<BufferedSyncProgress?> _syncProgressNotifier =
      ValueNotifier<BufferedSyncProgress?>(null);

  // ── DeviceConnection: read-only surfaces ───────────────────────────────

  @override
  Stream<DeviceConnectionState> get stateStream => _stateController.stream;

  @override
  DeviceConnectionState get currentState => _currentState;

  @override
  Stream<DeviceStatus> get statusStream => _statusController.stream;

  @override
  DeviceStatus? get latestStatus => _latestStatus;

  @override
  int? get batteryPercent => _batteryPercent;

  @override
  int? get bufferedCount => _bufferedCount;

  @override
  DateTime? get lastSeen => _lastSeenNotifier.value;

  @override
  ValueListenable<DateTime?> get lastSeenListenable => _lastSeenNotifier;

  @override
  ValueListenable<bool> get pairingCompleteListenable => _pairingComplete;

  @override
  bool get shuttingDownReceived => _shuttingDownReceived;

  @override
  Stream<List<DiscoveredDevice>> get scanResults =>
      _scanResultsController.stream;

  @override
  Stream<BluetoothAvailability> get adapterStateStream =>
      _adapterStateController.stream;

  @override
  BluetoothAvailability get adapterState => _currentAdapterState;

  /// Diagnostic sync-progress notifier consumed by the dev harness.
  /// Not on the [DeviceConnection] interface — production UI uses the
  /// coarser [stateStream] instead.
  ValueListenable<BufferedSyncProgress?> get bufferedSyncProgressListenable =>
      _syncProgressNotifier;

  // ── AirQualityDataSource surfaces ──────────────────────────────────────

  @override
  Stream<AirQualityReading> subscribeToLiveReadings() =>
      _liveReadingsController.stream;

  @override
  Stream<AirQualityReading> subscribeToBufferedReadings() =>
      _bufferedReadingsController.stream;

  @override
  Future<List<AirQualityReading>> getHistoricalReadings({
    required DateTime from,
    required DateTime to,
  }) async {
    return const <AirQualityReading>[];
  }

  @override
  Future<AirQualityReading?> getLatestReading() async => _latestReading;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Persistent adapter-state subscription for the UI. Kept
    // separate from the one-shot `.first` waits inside
    // _attemptAutoReconnect and startScan — those check "is the
    // adapter on right now?", this publishes changes for as long
    // as the app is running. FlutterBluePlus.adapterState is a
    // broadcast stream, so both listeners coexist without conflict.
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen(
      (s) {
        final mapped = _mapAdapterState(s);
        _currentAdapterState = mapped;
        if (!_adapterStateController.isClosed) {
          _adapterStateController.add(mapped);
        }
      },
      onError: (Object e) {
        debugPrint('[BLEManager] Adapter-state stream error: $e');
      },
    );

    final prefs = await SharedPreferences.getInstance();
    _persistedIdentifier = prefs.getString(_prefsKey);
    _pairingComplete.value = _persistedIdentifier != null;

    if (_persistedIdentifier != null) {
      debugPrint(
        '[BLEManager] start(): persisted identifier found '
        '($_persistedIdentifier); auto-reconnect will run.',
      );
      unawaited(_attemptAutoReconnect(_persistedIdentifier!));
    } else {
      debugPrint(
        '[BLEManager] start(): no persisted identifier, staying idle.',
      );
    }
  }

  Future<void> _attemptAutoReconnect(String identifier) async {
    debugPrint('[BLEManager] Auto-reconnect starting for $identifier');
    _transitionTo(DeviceConnectionState.connecting);

    // Wait for iOS's CBCentralManager to settle into poweredOn.
    // Attempting connect() during CBManagerStateUnknown throws
    // immediately.
    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      debugPrint(
        '[BLEManager] Bluetooth adapter not ready within 5 s; '
        'attempting auto-reconnect anyway.',
      );
    }

    // Scan-then-connect. Direct connect on a persisted identifier
    // reliably hangs on iOS after an app force-quit — the peripheral
    // is still in "connected" state from its own side (BLE supervision
    // timeout hasn't fired yet) and iOS's cached peripheral reference
    // is stale. Scanning first refreshes iOS's cache and yields a
    // fresh peripheral handle that connect() can talk to. Same
    // workaround nRF Connect uses under the hood.
    final device = await _findPeripheralByScan(identifier);
    if (device == null) {
      debugPrint(
        '[BLEManager] Auto-reconnect: peripheral not found via scan '
        '(out of range, powered off, or not advertising).',
      );
      _transitionTo(DeviceConnectionState.disconnected);
      return;
    }
    debugPrint(
      '[BLEManager] Auto-reconnect: peripheral discovered via scan, '
      'attempting connect().',
    );

    try {
      await device.connect(timeout: _autoReconnectTimeout);
      await _completeConnectFlow(device);
      debugPrint('[BLEManager] Auto-reconnect succeeded.');
    } catch (e) {
      debugPrint('[BLEManager] Auto-reconnect failed: $e');
      _transitionTo(DeviceConnectionState.disconnected);
    }
  }

  /// Scans (filtered by the Commuta service UUID) up to
  /// [_autoReconnectScanTimeout] for a peripheral whose remoteId
  /// matches [identifier]. Returns the peripheral if found (scan
  /// stopped early), null on timeout.
  Future<BluetoothDevice?> _findPeripheralByScan(String identifier) async {
    final completer = Completer<BluetoothDevice?>();
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (r.device.remoteId.str == identifier) {
          if (!completer.isCompleted) completer.complete(r.device);
          return;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(BleUuids.service)],
        timeout: _autoReconnectScanTimeout,
      );
    } catch (e) {
      debugPrint('[BLEManager] Reconnect-scan failed to start: $e');
      if (!completer.isCompleted) completer.complete(null);
    }

    final result = await completer.future.timeout(
      _autoReconnectScanTimeout + const Duration(seconds: 1),
      onTimeout: () => null,
    );

    await sub.cancel();
    if (FlutterBluePlus.isScanningNow) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    return result;
  }

  // ── Scanning ───────────────────────────────────────────────────────────

  @override
  Future<void> startScan() async {
    if (_currentState == DeviceConnectionState.scanning) return;
    if (_currentState == DeviceConnectionState.connected ||
        _currentState == DeviceConnectionState.syncingBuffered) {
      debugPrint('[BLEManager] Ignoring startScan: already connected.');
      return;
    }

    // iOS reports CBManagerStateUnknown briefly at process start.
    // Wait for the adapter to settle into poweredOn before scanning.
    // Bounded wait so a genuinely-off adapter still surfaces the error.
    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      debugPrint(
        '[BLEManager] Bluetooth adapter not ready within 3 s; '
        'attempting scan anyway.',
      );
    }

    _transitionTo(DeviceConnectionState.scanning);

    _scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        final devices = results
            .map(
              (r) => DiscoveredDevice(
                identifier: r.device.remoteId.str,
                name: r.device.platformName.isNotEmpty
                    ? r.device.platformName
                    : (r.advertisementData.advName.isNotEmpty
                          ? r.advertisementData.advName
                          : 'Unknown'),
                rssi: r.rssi,
              ),
            )
            .toList(growable: false);
        if (!_scanResultsController.isClosed) {
          _scanResultsController.add(devices);
        }
      },
      onError: (Object e) {
        debugPrint('[BLEManager] Scan stream error: $e');
      },
    );

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(BleUuids.service)],
        timeout: _scanTimeout,
      );
    } catch (e) {
      debugPrint('[BLEManager] startScan failed: $e');
      await stopScan();
    }
  }

  @override
  Future<void> stopScan() async {
    if (FlutterBluePlus.isScanningNow) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (e) {
        debugPrint('[BLEManager] stopScan failed: $e');
      }
    }
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (!_scanResultsController.isClosed) {
      _scanResultsController.add(const <DiscoveredDevice>[]);
    }
    if (_currentState == DeviceConnectionState.scanning) {
      _transitionTo(
        _connectedDevice != null
            ? DeviceConnectionState.connected
            : DeviceConnectionState.idle,
      );
    }
  }

  // ── Pairing / connecting ───────────────────────────────────────────────

  @override
  Future<void> pair(DiscoveredDevice device) async {
    await stopScan();
    _transitionTo(DeviceConnectionState.connecting);

    try {
      final btDevice = BluetoothDevice.fromId(device.identifier);
      await btDevice.connect(timeout: _connectTimeout);
      await _completeConnectFlow(btDevice);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, device.identifier);
      _persistedIdentifier = device.identifier;
      _pairingComplete.value = true;
      debugPrint(
        '[BLEManager] pair(): identifier persisted (${device.identifier}).',
      );
    } catch (e) {
      debugPrint('[BLEManager] pair(${device.identifier}) failed: $e');
      _transitionTo(DeviceConnectionState.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> reconnect() async {
    if (_persistedIdentifier == null) {
      debugPrint('[BLEManager] reconnect: nothing persisted, no-op.');
      return;
    }
    await _attemptAutoReconnect(_persistedIdentifier!);
  }

  Future<void> _completeConnectFlow(BluetoothDevice device) async {
    _connectedDevice = device;

    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        debugPrint('[BLEManager] Peer initiated disconnect.');
        unawaited(_teardownConnection());
        _transitionTo(DeviceConnectionState.disconnected);
      }
    });

    if (Platform.isAndroid) {
      try {
        await device.requestMtu(_targetMtu);
      } catch (e) {
        debugPrint('[BLEManager] requestMtu failed (non-fatal): $e');
      }
    } else {
      // iOS negotiates MTU asynchronously after connect() returns.
      // Reading mtuNow immediately gives the pre-negotiation value
      // (23). Log the true value after a short delay for diagnostics.
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (_connectedDevice == device) {
          debugPrint('[BLEManager] iOS negotiated MTU: ${device.mtuNow}');
        }
      });
    }

    final services = await device.discoverServices();
    BluetoothService? commutaService;
    for (final s in services) {
      if (s.uuid == Guid(BleUuids.service)) {
        commutaService = s;
        break;
      }
    }
    if (commutaService == null) {
      throw StateError(
        'Commuta service ${BleUuids.service} not found on peripheral.',
      );
    }

    for (final c in commutaService.characteristics) {
      if (c.uuid == Guid(BleUuids.liveCharacteristic)) {
        _liveCharacteristic = c;
      } else if (c.uuid == Guid(BleUuids.statusCharacteristic)) {
        _statusCharacteristic = c;
      } else if (c.uuid == Guid(BleUuids.bufferedCharacteristic)) {
        _bufferedCharacteristic = c;
      }
    }
    if (_liveCharacteristic == null ||
        _statusCharacteristic == null ||
        _bufferedCharacteristic == null) {
      throw StateError(
        'One or more Commuta characteristics missing on peripheral.',
      );
    }

    await _liveCharacteristic!.setNotifyValue(true);
    _liveNotificationSubscription = _liveCharacteristic!.lastValueStream.listen(
      _onLivePacket,
    );

    await _statusCharacteristic!.setNotifyValue(true);
    _statusNotificationSubscription = _statusCharacteristic!.lastValueStream
        .listen(_onStatusPacket);

    // Buffered characteristic subscription — must be enabled before
    // any sync request is written, otherwise the device's data / EOS
    // frames vanish into the void.
    await _bufferedCharacteristic!.setNotifyValue(true);
    _bufferedNotificationSubscription = _bufferedCharacteristic!.lastValueStream
        .listen(_onBufferedPacket);

    _transitionTo(DeviceConnectionState.connected);
  }

  // ── Notification handlers ──────────────────────────────────────────────

  void _onLivePacket(List<int> bytes) {
    // `lastValueStream` emits an empty list on first subscribe, before
    // any real notification. Ignore those — they're not real packets.
    if (bytes.isEmpty) return;

    final packet = BlePacketParser.parseLivePacket(bytes);
    if (packet == null) {
      debugPrint(
        '[BLEManager] Live packet: unexpected length '
        '${bytes.length} B (expected ${BlePacketParser.liveLength}); '
        'skipping.',
      );
      return;
    }

    final now = DateTime.now();
    _lastSeenNotifier.value = now;

    // Pressure change: |current − previous| in Pa/s. Device reports
    // hPa; ×100 → Pa; ÷10 s → per-second. First sample after a fresh
    // connection has no previous → null.
    double? pressureChangePaPerSec;
    if (_previousPressure != null) {
      final deltaHpa = (packet.pressure - _previousPressure!).abs();
      pressureChangePaPerSec = (deltaHpa * 100.0) / _samplingIntervalSec;
    }
    _previousPressure = packet.pressure;

    // Conditioning nulls only the processed indices (Option B): the
    // raw SGP41 ticks are diagnostically useful even during warm-up
    // and are preserved for the dissertation's JSON export.
    final reading = AirQualityReading(
      timestamp: now,
      pm1: packet.pm1,
      pm25: packet.pm25,
      pm10: packet.pm10,
      co2: packet.co2.toDouble(),
      temperature: packet.temperature,
      humidity: packet.humidity,
      pressure: packet.pressure,
      pressureChangePaPerSec: pressureChangePaPerSec,
      tvoc: packet.conditioning ? null : packet.vocIndex.toDouble(),
      nox: packet.conditioning ? null : packet.noxIndex.toDouble(),
      vocRaw: packet.srawVoc,
      noxRaw: packet.srawNox,
      sourceFlag: 'live',
      sequenceNumber: packet.sequence,
    );

    _latestReading = reading;
    _liveArrivalAnchor = (seq: packet.sequence, arrival: now);

    if (!_liveReadingsController.isClosed) {
      _liveReadingsController.add(reading);
    }

    debugPrint(
      '[BLEManager] Live #${packet.sequence} '
      'pm2.5=${packet.pm25.toStringAsFixed(1)} '
      'co2=${packet.co2} '
      'batt=${packet.batteryPercent}%'
      '${packet.conditioning ? ' cond' : ''}',
    );

    // Gate for the buffered sync-decision step: both a first Live and
    // a first Status must have arrived (Decision 2A). Fire-and-forget
    // — DB query and sync-request write happen async.
    if (!_firstLiveReceived) {
      _firstLiveReceived = true;
      unawaited(_maybeStartSync());
    }
  }

  void _onStatusPacket(List<int> bytes) {
    if (bytes.isEmpty) return;

    final now = DateTime.now();
    final status = BlePacketParser.parseStatusPacket(bytes, now);
    if (status == null) {
      debugPrint(
        '[BLEManager] Status packet: unexpected length '
        '${bytes.length} B (expected ${BlePacketParser.statusLength}); '
        'skipping.',
      );
      return;
    }

    _lastSeenNotifier.value = now;
    _latestStatus = status;
    _batteryPercent = status.batteryPercent;
    _bufferedCount = status.bufferedCount;

    // SHUTTING_DOWN is a one-way latch: once observed, we keep the
    // flag set for the rest of the session so shutdown UI (Step 7)
    // doesn't flicker if a stray subsequent Status arrives before the
    // device actually powers off.
    if (status.shuttingDown) {
      _shuttingDownReceived = true;
    }

    if (!_statusController.isClosed) {
      _statusController.add(status);
    }

    debugPrint(
      '[BLEManager] Status uptime=${status.uptimeSeconds}s '
      'buffered=${status.bufferedCount} '
      'batt=${status.batteryPercent}%'
      '${status.conditioning ? ' cond' : ''}'
      '${status.shuttingDown ? ' SHUTDOWN' : ''}',
    );

    if (!_firstStatusReceived) {
      _firstStatusReceived = true;
      unawaited(_maybeStartSync());
    }
  }

  // ── Buffered sync ──────────────────────────────────────────────────────

  /// Called from both Live and Status handlers once the corresponding
  /// "first" flag has flipped. Guarded by [_syncEvaluated] so at most
  /// one decision runs per connection. Auto-resume attempts are driven
  /// by [_onSyncHeartbeatFired] rather than this method.
  Future<void> _maybeStartSync() async {
    if (_syncEvaluated) return;
    if (!_firstLiveReceived || !_firstStatusReceived) return;
    _syncEvaluated = true;

    final status = _latestStatus;
    if (status == null) {
      debugPrint(
        '[BLEManager] Sync: no Status snapshot cached at decision '
        'time; giving up (should be unreachable).',
      );
      return;
    }

    // Skip: device has nothing buffered.
    if (status.bufferedCount == 0) {
      debugPrint(
        '[BLEManager] Sync: device reports zero buffered samples; '
        'nothing to do.',
      );
      _publishSkipped(note: 'Device has no buffered samples');
      _syncCompletedThisSession = true;
      return;
    }

    // Skip: no provider wired (dev harness path). Real app wires this
    // in Step 7 via AppServices.
    if (highestSequenceProvider == null) {
      debugPrint(
        '[BLEManager] Sync: highestSequenceProvider not wired; '
        'skipping sync. Wire it via `bleManager.highestSequenceProvider = '
        'repo.getHighestSequenceNumber` in AppServices, or set it on '
        'the harness before connecting to exercise sync.',
      );
      _publishSkipped(note: 'highestSequenceProvider not wired');
      _syncCompletedThisSession = true;
      return;
    }

    int? ourHighest;
    try {
      ourHighest = await highestSequenceProvider!();
    } catch (e) {
      debugPrint(
        '[BLEManager] Sync: highestSequenceProvider threw ($e); '
        'skipping sync for this session.',
      );
      _publishSkipped(note: 'highestSequenceProvider threw: $e');
      _syncCompletedThisSession = true;
      return;
    }

    // Skip: already caught up.
    if (ourHighest != null && ourHighest >= status.newestBufferedSeq) {
      if (ourHighest == status.newestBufferedSeq) {
        debugPrint(
          '[BLEManager] Sync: already caught up '
          '(ourHighest=$ourHighest == device newest_buffered_seq).',
        );
        _publishSkipped(note: 'Already caught up (ourHighest = device newest)');
      } else {
        // ourHighest > newestBufferedSeq — firmware sequence reset
        // (Decision 4A). Two "eras" of sequence numbers coexist in
        // the DB, separated by timestamps; skip sync rather than
        // attempt a full-range refetch.
        debugPrint(
          '[BLEManager] Sync: firmware sequence reset detected '
          '(device newest_buffered_seq=${status.newestBufferedSeq} < '
          'our highest=$ourHighest). Skipping sync (Decision 4A). '
          'New readings will flow via Live notifications; any records '
          'the device buffered before we reconnected are not being '
          'requested. If the buffer contains genuinely new data with '
          'reset sequence numbers, wipe the DB via the dev-only Clear '
          'action to recover them on next connect.',
        );
        _publishSkipped(note: 'Firmware sequence reset detected');
      }
      _syncCompletedThisSession = true;
      return;
    }

    // Request the range. Empty DB → start at 0 to include a possible
    // seq-0 record; otherwise start immediately after our highest.
    final startSeq = (ourHighest == null) ? 0 : ourHighest + 1;
    const endSeq = _syncEndSeqSentinel;
    final expectedTotal = status.newestBufferedSeq - startSeq + 1;

    _syncSessionStartedAt = DateTime.now();
    _syncExpectedTotal = expectedTotal > 0 ? expectedTotal : null;
    _syncAttemptNumber = 1;
    _lastRequestedRange = (start: startSeq, end: endSeq);
    _recordsReceivedThisSync = 0;
    _lastReceivedBufferedSeq = null;

    _syncProgressNotifier.value = BufferedSyncProgress(
      phase: BufferedSyncPhase.active,
      startedAt: _syncSessionStartedAt!,
      recordsReceived: 0,
      attemptNumber: 1,
      expectedTotal: _syncExpectedTotal,
      requestedStartSeq: startSeq,
      requestedEndSeq: endSeq,
    );

    _transitionTo(DeviceConnectionState.syncingBuffered);
    _armSyncHeartbeat();

    debugPrint(
      '[BLEManager] Sync: attempt 1/$syncMaxAttempts requesting '
      '[$startSeq..0x${endSeq.toRadixString(16)}] '
      '(ourHighest=$ourHighest, device newest=${status.newestBufferedSeq}, '
      'expected ~$expectedTotal records).',
    );

    try {
      final payload = BlePacketParser.encodeSyncRequest(startSeq, endSeq);
      await _bufferedCharacteristic!.write(payload, withoutResponse: false);
    } catch (e) {
      debugPrint(
        '[BLEManager] Sync: request write failed ($e); giving up for '
        'this session.',
      );
      _syncHeartbeatTimer?.cancel();
      _syncHeartbeatTimer = null;
      _publishTerminatedWithNote('Sync-request write failed: $e');
      _syncCompletedThisSession = true;
      _transitionTo(DeviceConnectionState.connected);
    }
  }

  /// Called from [_onSyncHeartbeatFired] when we've hit
  /// [_syncHeartbeatTimeout] without a Buffered frame but still have
  /// attempts left. Writes a fresh sync request starting from just
  /// after the last record we successfully received across any prior
  /// attempt this session.
  Future<void> _resumeSync() async {
    _syncAttemptNumber++;

    // Resume start: one past the highest seq we've received across all
    // attempts. If nothing was received at all, fall back to the
    // original start of the very first attempt so we're not re-inventing
    // where to begin.
    final int resumeStart;
    if (_lastReceivedBufferedSeq != null) {
      resumeStart = _lastReceivedBufferedSeq! + 1;
    } else if (_lastRequestedRange != null) {
      resumeStart = _lastRequestedRange!.start;
    } else {
      // Shouldn't happen — resume implies at least one prior request.
      // Belt and braces.
      resumeStart = 0;
    }
    const resumeEnd = _syncEndSeqSentinel;

    _lastRequestedRange = (start: resumeStart, end: resumeEnd);

    debugPrint(
      '[BLEManager] Sync resume: attempt '
      '$_syncAttemptNumber/$syncMaxAttempts after '
      '${_syncHeartbeatTimeout.inSeconds} s silence. '
      'Requesting [$resumeStart..0x${resumeEnd.toRadixString(16)}]. '
      'Records so far this session: $_recordsReceivedThisSync.',
    );

    _syncProgressNotifier.value = BufferedSyncProgress(
      phase: BufferedSyncPhase.active,
      startedAt: _syncSessionStartedAt ?? DateTime.now(),
      recordsReceived: _recordsReceivedThisSync,
      attemptNumber: _syncAttemptNumber,
      expectedTotal: _syncExpectedTotal,
      requestedStartSeq: resumeStart,
      requestedEndSeq: resumeEnd,
    );

    _armSyncHeartbeat();

    try {
      final payload = BlePacketParser.encodeSyncRequest(resumeStart, resumeEnd);
      await _bufferedCharacteristic!.write(payload, withoutResponse: false);
    } catch (e) {
      debugPrint(
        '[BLEManager] Sync resume: request write failed ($e); '
        'giving up for this session.',
      );
      _syncHeartbeatTimer?.cancel();
      _syncHeartbeatTimer = null;
      _publishTerminatedWithNote(
        'Resume attempt $_syncAttemptNumber failed to write: $e',
      );
      _syncCompletedThisSession = true;
      _transitionTo(DeviceConnectionState.connected);
    }
  }

  void _onBufferedPacket(List<int> bytes) {
    // `lastValueStream` emits [] on first subscribe. Ignore.
    if (bytes.isEmpty) return;

    if (_currentState != DeviceConnectionState.syncingBuffered) {
      debugPrint(
        '[BLEManager] Buffered frame arrived while not syncing '
        '(state=$_currentState, ${bytes.length} B); ignoring.',
      );
      return;
    }

    final frame = BlePacketParser.classifyBufferedFrame(bytes);
    if (frame == null) {
      debugPrint(
        '[BLEManager] Buffered frame: malformed '
        '(${bytes.length} B, first byte '
        '0x${bytes.isNotEmpty ? bytes[0].toRadixString(16) : "??"}); '
        'dropping. Heartbeat still armed — waiting for a valid frame.',
      );
      return;
    }

    // Any valid frame (data or EOS) is a heartbeat.
    _armSyncHeartbeat();

    switch (frame) {
      case BufferedDataFrame(:final records):
        _handleBufferedDataFrame(records);
      case BufferedEosFrame(
        :final firstSentSeq,
        :final lastSentSeq,
        :final sentCount,
      ):
        _handleBufferedEosFrame(
          firstSentSeq: firstSentSeq,
          lastSentSeq: lastSentSeq,
          sentCount: sentCount,
        );
    }
  }

  void _handleBufferedDataFrame(List<LivePacket> records) {
    for (final packet in records) {
      final timestamp = _computeBackfillTimestamp(packet.sequence);
      if (timestamp == null) {
        // Should be unreachable — sync only starts after the first
        // Live packet, so _liveArrivalAnchor is always populated by
        // the time buffered frames arrive.
        debugPrint(
          '[BLEManager] Buffered record #${packet.sequence}: no live '
          'anchor available for back-fill; dropping record.',
        );
        continue;
      }

      final reading = AirQualityReading(
        timestamp: timestamp,
        pm1: packet.pm1,
        pm25: packet.pm25,
        pm10: packet.pm10,
        co2: packet.co2.toDouble(),
        temperature: packet.temperature,
        humidity: packet.humidity,
        pressure: packet.pressure,
        // Pressure-change is a live-only concept — we don't back-fill
        // it for buffered records because doing so would require the
        // previous buffered record in the same run, which may or may
        // not be present in the DB. Leaving it null is honest.
        pressureChangePaPerSec: null,
        tvoc: packet.conditioning ? null : packet.vocIndex.toDouble(),
        nox: packet.conditioning ? null : packet.noxIndex.toDouble(),
        vocRaw: packet.srawVoc,
        noxRaw: packet.srawNox,
        sourceFlag: 'buffered',
        sequenceNumber: packet.sequence,
      );

      if (!_bufferedReadingsController.isClosed) {
        _bufferedReadingsController.add(reading);
      }
      _recordsReceivedThisSync++;

      // Track the highest sequence seen so auto-resume knows where to
      // pick up. Records within a frame arrive in ascending seq order,
      // but be conservative in case a future firmware change reorders.
      final currentHighest = _lastReceivedBufferedSeq;
      if (currentHighest == null || packet.sequence > currentHighest) {
        _lastReceivedBufferedSeq = packet.sequence;
      }
    }

    // Publish progress. `expectedTotal`, `startedAt`, and
    // `attemptNumber` are carried forward — set at sync start /
    // resume, never re-estimated per-frame.
    final prev = _syncProgressNotifier.value;
    _syncProgressNotifier.value = BufferedSyncProgress(
      phase: BufferedSyncPhase.active,
      startedAt: prev?.startedAt ?? _syncSessionStartedAt ?? DateTime.now(),
      recordsReceived: _recordsReceivedThisSync,
      attemptNumber: _syncAttemptNumber,
      expectedTotal: _syncExpectedTotal,
      requestedStartSeq: prev?.requestedStartSeq,
      requestedEndSeq: prev?.requestedEndSeq,
    );

    debugPrint(
      '[BLEManager] Buffered data frame: ${records.length} record(s) '
      '(seq ${records.first.sequence}..${records.last.sequence}); '
      'total this sync: $_recordsReceivedThisSync '
      '(attempt $_syncAttemptNumber/$syncMaxAttempts).',
    );
  }

  void _handleBufferedEosFrame({
    required int firstSentSeq,
    required int lastSentSeq,
    required int sentCount,
  }) {
    final requested = _lastRequestedRange;
    debugPrint(
      '[BLEManager] Buffered sync complete on attempt '
      '$_syncAttemptNumber/$syncMaxAttempts. '
      'Requested=${requested == null ? "n/a" : "[${requested.start}..0x${requested.end.toRadixString(16)}]"}. '
      'Device sent: first_sent=$firstSentSeq, last_sent=$lastSentSeq, '
      'sent_count=$sentCount. Total records received this session: '
      '$_recordsReceivedThisSync.',
    );

    if (_syncAttemptNumber == 1 && sentCount != _recordsReceivedThisSync) {
      // Only warn on mismatch for a first-attempt clean run. Under
      // resume, the EOS's sent_count counts only what came back in
      // *this* attempt, so it deliberately won't equal the
      // whole-session total.
      debugPrint(
        '[BLEManager] Buffered sync: reconciliation mismatch on first '
        'attempt — device reports $sentCount records, we counted '
        '$_recordsReceivedThisSync. Difference is usually zero on iOS; '
        'a non-zero delta suggests notification loss (rare) or a '
        'malformed frame that was dropped upstream.',
      );
    }

    _syncHeartbeatTimer?.cancel();
    _syncHeartbeatTimer = null;

    _bufferedCount = 0;
    _syncCompletedThisSession = true;

    final prev = _syncProgressNotifier.value;
    _syncProgressNotifier.value = BufferedSyncProgress(
      phase: BufferedSyncPhase.completed,
      startedAt: prev?.startedAt ?? _syncSessionStartedAt ?? DateTime.now(),
      completedAt: DateTime.now(),
      recordsReceived: _recordsReceivedThisSync,
      attemptNumber: _syncAttemptNumber,
      expectedTotal: _syncExpectedTotal,
      sentCount: sentCount,
      firstSentSeq: sentCount > 0 ? firstSentSeq : null,
      lastSentSeq: sentCount > 0 ? lastSentSeq : null,
      requestedStartSeq: prev?.requestedStartSeq,
      requestedEndSeq: prev?.requestedEndSeq,
    );

    _transitionTo(DeviceConnectionState.connected);
  }

  /// Reads the current live anchor and projects a wall-clock time for
  /// [recordSeq]. Applies the formula symmetrically (Decision 8A) —
  /// if a buffered record ever has a seq greater than the anchor's
  /// (shouldn't happen in normal operation), the formula projects
  /// forward without special-casing.
  DateTime? _computeBackfillTimestamp(int recordSeq) {
    final anchor = _liveArrivalAnchor;
    if (anchor == null) return null;
    final deltaSeconds = (anchor.seq - recordSeq) * _samplingIntervalSecInt;
    return anchor.arrival.subtract(Duration(seconds: deltaSeconds));
  }

  void _armSyncHeartbeat() {
    _syncHeartbeatTimer?.cancel();
    _syncHeartbeatTimer = Timer(_syncHeartbeatTimeout, _onSyncHeartbeatFired);
  }

  void _onSyncHeartbeatFired() {
    if (_currentState != DeviceConnectionState.syncingBuffered) return;

    // Auto-resume path: still have attempts left. Kick a fresh sync
    // request starting from just after the last record we did receive.
    if (_syncAttemptNumber < syncMaxAttempts) {
      debugPrint(
        '[BLEManager] Buffered sync heartbeat: no frame in '
        '${_syncHeartbeatTimeout.inSeconds} s on attempt '
        '$_syncAttemptNumber/$syncMaxAttempts. Auto-resuming.',
      );
      unawaited(_resumeSync());
      return;
    }

    // Max attempts exhausted — genuine give-up.
    debugPrint(
      '[BLEManager] Buffered sync: exhausted $syncMaxAttempts attempts '
      '(${_syncHeartbeatTimeout.inSeconds} s silence each). Giving up '
      'for this session; $_recordsReceivedThisSync records collected. '
      'Will retry from where we left off on the next reconnect.',
    );
    _syncCompletedThisSession = true;
    _publishTerminatedWithNote(
      'Sync incomplete after $syncMaxAttempts attempts '
      '(${_syncHeartbeatTimeout.inSeconds} s silence each); '
      '$_recordsReceivedThisSync records received. Will retry on next reconnect.',
    );
    _transitionTo(DeviceConnectionState.connected);
  }

  void _publishSkipped({required String note}) {
    _syncProgressNotifier.value = BufferedSyncProgress(
      phase: BufferedSyncPhase.completed,
      startedAt: DateTime.now(),
      completedAt: DateTime.now(),
      recordsReceived: 0,
      attemptNumber: 0,
      note: note,
    );
  }

  void _publishTerminatedWithNote(String note) {
    final prev = _syncProgressNotifier.value;
    _syncProgressNotifier.value = BufferedSyncProgress(
      phase: BufferedSyncPhase.completed,
      startedAt: prev?.startedAt ?? _syncSessionStartedAt ?? DateTime.now(),
      completedAt: DateTime.now(),
      recordsReceived: _recordsReceivedThisSync,
      attemptNumber: _syncAttemptNumber,
      expectedTotal: _syncExpectedTotal,
      requestedStartSeq: prev?.requestedStartSeq,
      requestedEndSeq: prev?.requestedEndSeq,
      note: note,
    );
  }

  // ── Forget ─────────────────────────────────────────────────────────────

  @override
  Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _persistedIdentifier = null;
    _pairingComplete.value = false;

    await _teardownConnection();

    _batteryPercent = null;
    _bufferedCount = null;
    _lastSeenNotifier.value = null;
    _latestStatus = null;
    _latestReading = null;
    _shuttingDownReceived = false;
    // Leave _syncProgressNotifier alone — the harness may want to
    // inspect the last sync details even after forget.

    _transitionTo(DeviceConnectionState.idle);
  }

  // ── Teardown helpers ───────────────────────────────────────────────────

  Future<void> _teardownConnection() async {
    await _liveNotificationSubscription?.cancel();
    _liveNotificationSubscription = null;
    await _statusNotificationSubscription?.cancel();
    _statusNotificationSubscription = null;
    await _bufferedNotificationSubscription?.cancel();
    _bufferedNotificationSubscription = null;
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    _liveCharacteristic = null;
    _statusCharacteristic = null;
    _bufferedCharacteristic = null;

    _syncHeartbeatTimer?.cancel();
    _syncHeartbeatTimer = null;

    // Reset per-connection state so the next (re)connect starts
    // fresh. Nulling `_previousPressure` guarantees the first Live
    // sample after the next connect emits `pressureChangePaPerSec =
    // null` as the plan requires. `_liveArrivalAnchor` is nulled so
    // buffered back-fill cannot reference a stale anchor across
    // connection lifetimes. Sync flags and counters reset so a
    // reconnect re-evaluates whether sync is needed and starts from
    // attempt 1.
    _previousPressure = null;
    _liveArrivalAnchor = null;
    _firstLiveReceived = false;
    _firstStatusReceived = false;
    _syncEvaluated = false;
    _syncCompletedThisSession = false;
    _lastRequestedRange = null;
    _recordsReceivedThisSync = 0;
    _lastReceivedBufferedSeq = null;
    _syncAttemptNumber = 0;
    _syncSessionStartedAt = null;
    _syncExpectedTotal = null;

    final device = _connectedDevice;
    _connectedDevice = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (e) {
        debugPrint('[BLEManager] disconnect during teardown failed: $e');
      }
    }
  }

  @override
  void dispose() {
    unawaited(_adapterStateSubscription?.cancel());
    _adapterStateSubscription = null;
    unawaited(stopScan());
    unawaited(_teardownConnection());
    _stateController.close();
    _liveReadingsController.close();
    _bufferedReadingsController.close();
    _statusController.close();
    _scanResultsController.close();
    _adapterStateController.close();
    _pairingComplete.dispose();
    _lastSeenNotifier.dispose();
    _syncProgressNotifier.dispose();
  }

  // ── Internal ───────────────────────────────────────────────────────────

  void _transitionTo(DeviceConnectionState next) {
    if (_currentState == next) return;
    _currentState = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  /// Maps `flutter_blue_plus`'s [BluetoothAdapterState] onto our
  /// library-agnostic [BluetoothAvailability] enum. Collapses
  /// transient states (`turningOn`, `turningOff`), the hardware-
  /// absent `unavailable`, and the pre-report `unknown` all into
  /// [BluetoothAvailability.unknown] — UI treats that as "no useful
  /// information right now" and shows nothing.
  static BluetoothAvailability _mapAdapterState(BluetoothAdapterState s) {
    switch (s) {
      case BluetoothAdapterState.on:
        return BluetoothAvailability.on;
      case BluetoothAdapterState.off:
        return BluetoothAvailability.off;
      case BluetoothAdapterState.unauthorized:
        return BluetoothAvailability.unauthorised;
      case BluetoothAdapterState.unknown:
      case BluetoothAdapterState.unavailable:
      case BluetoothAdapterState.turningOn:
      case BluetoothAdapterState.turningOff:
        return BluetoothAvailability.unknown;
    }
  }
}
