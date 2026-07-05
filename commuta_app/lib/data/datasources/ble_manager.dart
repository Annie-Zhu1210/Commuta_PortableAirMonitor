import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/ble_uuids.dart';
import '../../services/device_connection.dart';
import '../models/air_quality_reading.dart';
import 'air_quality_datasource.dart';

/// Real BLE implementation of [AirQualityDataSource] and [DeviceConnection].
///
/// See BLE_Integration_Plan.md for the full context. Step 4
/// responsibilities: scan, connect, characteristic discovery, notify
/// subscriptions, MTU 247 (Android), SharedPreferences persistence,
/// silent auto-reconnect, forget. Parsing lands in Step 5.
class BLEManager implements AirQualityDataSource, DeviceConnection {
  static const String _prefsKey = 'commuta_paired_peripheral_id';

  static const Duration _scanTimeout                = Duration(seconds: 10);
  static const Duration _connectTimeout             = Duration(seconds: 15);
  static const Duration _autoReconnectTimeout       = Duration(seconds: 10);
  static const Duration _autoReconnectScanTimeout   = Duration(seconds: 12);
  static const int _targetMtu = 247;

  bool _started = false;
  DeviceConnectionState _currentState = DeviceConnectionState.idle;
  final _stateController =
      StreamController<DeviceConnectionState>.broadcast();

  final ValueNotifier<bool> _pairingComplete = ValueNotifier<bool>(false);
  final ValueNotifier<DateTime?> _lastSeenNotifier =
      ValueNotifier<DateTime?>(null);
  bool _shuttingDownReceived = false;

  int? _batteryPercent;
  int? _bufferedCount;
  AirQualityReading? _latestReading;
  DeviceStatus? _latestStatus;

  String? _persistedIdentifier;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _liveCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;
  BluetoothCharacteristic? _bufferedCharacteristic;

  final _liveReadingsController =
      StreamController<AirQualityReading>.broadcast();
  final _statusController =
      StreamController<DeviceStatus>.broadcast();
  final _scanResultsController =
      StreamController<List<DiscoveredDevice>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _liveNotificationSubscription;
  StreamSubscription<List<int>>? _statusNotificationSubscription;

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

  // ── AirQualityDataSource surfaces ──────────────────────────────────────

  @override
  Stream<AirQualityReading> subscribeToLiveReadings() =>
      _liveReadingsController.stream;

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
    _connectionStateSubscription = device.connectionState.listen(
      (state) {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint('[BLEManager] Peer initiated disconnect.');
          unawaited(_teardownConnection());
          _transitionTo(DeviceConnectionState.disconnected);
        }
      },
    );

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
    _liveNotificationSubscription =
        _liveCharacteristic!.lastValueStream.listen(_onLivePacket);

    await _statusCharacteristic!.setNotifyValue(true);
    _statusNotificationSubscription =
        _statusCharacteristic!.lastValueStream.listen(_onStatusPacket);

    _transitionTo(DeviceConnectionState.connected);
  }

  void _onLivePacket(List<int> bytes) {
    // `lastValueStream` emits an empty list on first subscribe, before
    // any real notification. Ignore those — they're not real packets.
    if (bytes.isEmpty) return;
    _lastSeenNotifier.value = DateTime.now();
    debugPrint(
      '[BLEManager] Live packet: ${bytes.length} bytes '
      '(parsing lands in Step 5).',
    );
  }

  void _onStatusPacket(List<int> bytes) {
    if (bytes.isEmpty) return;
    _lastSeenNotifier.value = DateTime.now();
    debugPrint(
      '[BLEManager] Status packet: ${bytes.length} bytes '
      '(parsing lands in Step 5).',
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
    _shuttingDownReceived = false;

    _transitionTo(DeviceConnectionState.idle);
  }

  // ── Teardown helpers ───────────────────────────────────────────────────

  Future<void> _teardownConnection() async {
    await _liveNotificationSubscription?.cancel();
    _liveNotificationSubscription = null;
    await _statusNotificationSubscription?.cancel();
    _statusNotificationSubscription = null;
    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    _liveCharacteristic = null;
    _statusCharacteristic = null;
    _bufferedCharacteristic = null;

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
    unawaited(stopScan());
    unawaited(_teardownConnection());
    _stateController.close();
    _liveReadingsController.close();
    _statusController.close();
    _scanResultsController.close();
    _pairingComplete.dispose();
    _lastSeenNotifier.dispose();
  }

  // ── Internal ───────────────────────────────────────────────────────────

  void _transitionTo(DeviceConnectionState next) {
    if (_currentState == next) return;
    _currentState = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }
}