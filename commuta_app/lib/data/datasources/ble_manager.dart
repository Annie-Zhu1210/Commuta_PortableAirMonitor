import 'dart:async';

import '../../services/device_connection.dart';
import '../models/air_quality_reading.dart';
import 'air_quality_datasource.dart';

/// Live-device implementation of both [AirQualityDataSource] and
/// [DeviceConnection].
///
/// Step 3 status: STUB. The class compiles, all interface methods
/// exist, the stream controllers are wired up, and the state machine
/// transitions on stub events — but no actual BLE work is performed
/// anywhere. Scan does not scan; pair does not connect; the live
/// readings stream is created but never receives readings.
///
/// Real behaviour is filled in over Steps 4–6:
///   • Step 4 — [startScan], [pair], [forget], [reconnect] talk to
///     `flutter_blue_plus` and persist to `SharedPreferences`.
///   • Step 5 — Live and Status characteristic notifications are
///     decoded and emitted on the streams.
///   • Step 6 — Buffered characteristic sync protocol.
///
/// The Step 7 cutover swaps this class in for `MockManager` by
/// changing one line in `AppServices.init()`.
class BLEManager implements AirQualityDataSource, DeviceConnection {
  BLEManager();

  // ── Reading stream ──────────────────────────────────────────────

  StreamController<AirQualityReading>? _readingController;

  @override
  Stream<AirQualityReading> subscribeToLiveReadings() {
    // Broadcast so Home and ReadingsRepository can both subscribe
    // without collision. Created lazily on first listen; will not
    // emit until Step 5 wires up notification parsing.
    _readingController ??= StreamController<AirQualityReading>.broadcast();
    return _readingController!.stream;
  }

  @override
  Future<AirQualityReading?> getLatestReading() async {
    // Real behaviour arrives in Step 5, where the most recent reading
    // is cached on each Live notification.
    return null;
  }

  @override
  Future<List<AirQualityReading>> getHistoricalReadings({
    required DateTime from,
    required DateTime to,
  }) async {
    // Historical queries are served from the Drift database via the
    // History screen, not from the BLE device directly. This method
    // exists to satisfy the interface but is not the intended query
    // path.
    return const [];
  }

  // ── Connection-state stream ─────────────────────────────────────

  StreamController<DeviceConnectionState>? _stateController;
  DeviceConnectionState _currentState = DeviceConnectionState.idle;

  void _transitionTo(DeviceConnectionState next) {
    if (_currentState == next) return;
    _currentState = next;
    _stateController?.add(next);
  }

  @override
  Stream<DeviceConnectionState> get stateStream {
    _stateController ??= StreamController<DeviceConnectionState>.broadcast();
    return _stateController!.stream;
  }

  @override
  DeviceConnectionState get currentState => _currentState;

  // ── Status stream ───────────────────────────────────────────────

  StreamController<DeviceStatus>? _statusController;
  DeviceStatus? _latestStatus;
  DateTime? _lastSeen;

  @override
  Stream<DeviceStatus> get statusStream {
    _statusController ??= StreamController<DeviceStatus>.broadcast();
    return _statusController!.stream;
  }

  @override
  DeviceStatus? get latestStatus => _latestStatus;

  @override
  int? get batteryPercent => _latestStatus?.batteryPercent;

  @override
  int? get bufferedCount => _latestStatus?.bufferedCount;

  @override
  DateTime? get lastSeen => _lastSeen;

  @override
  bool get shuttingDownReceived => _latestStatus?.shuttingDown ?? false;

  // ── Scan stream ─────────────────────────────────────────────────

  StreamController<DiscoveredDevice>? _scanController;

  @override
  Stream<DiscoveredDevice> get scanResults {
    _scanController ??= StreamController<DiscoveredDevice>.broadcast();
    return _scanController!.stream;
  }

  // ── Pairing state ───────────────────────────────────────────────

  bool _isPaired = false;

  @override
  bool get isPaired => _isPaired;

  // ── Actions (stubs — transitions only, no BLE calls) ────────────

  @override
  Future<void> startScan() async {
    // Step 4 will replace this with an actual flutter_blue_plus scan
    // filtered on BleUuids.service. For now, just transition state so
    // any UI wired to the state stream sees the change.
    _transitionTo(DeviceConnectionState.scanning);
  }

  @override
  Future<void> stopScan() async {
    // Step 4 will refine the return-state logic (e.g. back to
    // connected if the user cancels a re-scan). Idle is the sensible
    // default for the stub.
    _transitionTo(DeviceConnectionState.idle);
  }

  @override
  Future<void> pair(DiscoveredDevice device) async {
    // Step 4: open a GATT connection, discover services, subscribe to
    // Live and Status characteristics, request MTU 247, persist
    // `device.id` to SharedPreferences. Left in `connecting`
    // intentionally in the stub — a UI wired to this without Step 4
    // done should be visibly stuck, not silently claim success.
    _transitionTo(DeviceConnectionState.connecting);
  }

  @override
  Future<void> forget() async {
    // Step 4: cancel the live GATT connection, clear the persisted
    // identifier from SharedPreferences.
    _isPaired = false;
    _latestStatus = null;
    _lastSeen = null;
    _transitionTo(DeviceConnectionState.idle);
  }

  @override
  Future<void> reconnect() async {
    // Step 4: read the persisted identifier from SharedPreferences,
    // attempt to reconnect via CoreBluetooth identifier-based
    // retrieval (iOS) or MAC-based reconnect (Android). Fails silently
    // if the device is out of range.
    if (!_isPaired) return;
    _transitionTo(DeviceConnectionState.connecting);
  }

  // ── Lifecycle ───────────────────────────────────────────────────

  @override
  void dispose() {
    _readingController?.close();
    _readingController = null;
    _stateController?.close();
    _stateController = null;
    _statusController?.close();
    _statusController = null;
    _scanController?.close();
    _scanController = null;
  }
}