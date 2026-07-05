import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../services/device_connection.dart';
import '../models/air_quality_reading.dart';
import 'air_quality_datasource.dart';


/// Development-time implementation of both [AirQualityDataSource] and
/// [DeviceConnection].
///
/// Produces synthetic air-quality readings on the same 10-second
/// cadence as the real device, and reports as always-connected with a
/// slowly draining synthetic battery. Useful for building against in
/// the simulator or during hot-reload sessions where a real device
/// isn't plugged in.
///
/// Renamed from the earlier `MockDataSource` when the
/// device-connection interface was introduced — the class is now more
/// than a data source.
class MockManager implements AirQualityDataSource, DeviceConnection {
  MockManager();

  // ═════════════════════════════════════════════════════════════════
  // Air-quality half. Behaviour is a straight lift of the previous
  // MockDataSource — same random walk, same broadcast stream, same
  // pressure-change algorithm, same 'mock' source flag.
  // ═════════════════════════════════════════════════════════════════

  final Random _random = Random();
  StreamController<AirQualityReading>? _readingController;
  Timer? _sampleTimer;
  int _sequence = 0;

  // Simulated "current" values that drift slightly each tick.
  double _pm1  = 8.2;
  double _pm25 = 14.5;
  double _pm10 = 22.1;
  double _co2  = 612.0;
  double _temp = 21.4;
  double _hum  = 48.0;
  double _pres = 1013.2;

  // Tracks the previous pressure so the next reading can compute the
  // rate of change in Pa/s (10 s interval, 1 hPa = 100 Pa).
  double? _prevPres;
  static const double _samplingIntervalSec = 10.0;

  AirQualityReading _buildReading() {
    // Small random walk so the UI doesn't look completely static.
    _pm1  = (_pm1  + (_random.nextDouble() - 0.5) *  1.0).clamp(2.0,  80.0);
    _pm25 = (_pm25 + (_random.nextDouble() - 0.5) *  1.5).clamp(3.0, 150.0);
    _pm10 = (_pm10 + (_random.nextDouble() - 0.5) *  2.0).clamp(5.0, 200.0);
    _co2  = (_co2  + (_random.nextDouble() - 0.5) * 20.0).clamp(400.0, 2000.0);
    // Clamps reflect the device's full measurement range:
    //   temperature: -10°C to 45°C, humidity: 0% to 100%.
    _temp = (_temp + (_random.nextDouble() - 0.5) *  0.3).clamp(-10.0, 45.0);
    _hum  = (_hum  + (_random.nextDouble() - 0.5) *  1.0).clamp( 0.0, 100.0);
    _pres = (_pres + (_random.nextDouble() - 0.5) *  0.5).clamp(950.0, 1050.0);

    // ── Pressure change ──────────────────────────────────────────
    // First reading has no prior pressure to compare to → leave null.
    // Otherwise compute |Δpressure| in Pa/s (hPa × 100 / interval).
    double? pressureChangePaPerSec;
    if (_prevPres != null) {
      final deltaHpa = (_pres - _prevPres!).abs();
      pressureChangePaPerSec = (deltaHpa * 100.0) / _samplingIntervalSec;
    }
    _prevPres = _pres;

    _sequence++;
    return AirQualityReading(
      timestamp:              DateTime.now(),
      pm1:                    double.parse(_pm1.toStringAsFixed(1)),
      pm25:                   double.parse(_pm25.toStringAsFixed(1)),
      pm10:                   double.parse(_pm10.toStringAsFixed(1)),
      co2:                    double.parse(_co2.toStringAsFixed(0)),
      temperature:            double.parse(_temp.toStringAsFixed(1)),
      humidity:               double.parse(_hum.toStringAsFixed(1)),
      pressure:               double.parse(_pres.toStringAsFixed(1)),
      pressureChangePaPerSec: pressureChangePaPerSec,
      // SGP41 modelled as unavailable in the mock — no processed
      // indices, no raw ticks. Everything nullable stays null.
      tvoc:                   null,
      nox:                    null,
      vocRaw:                 null,
      noxRaw:                 null,
      sourceFlag:             'mock',
      sequenceNumber:         _sequence,
    );
  }

  @override
  Stream<AirQualityReading> subscribeToBufferedReadings() =>
      const Stream<AirQualityReading>.empty();

      
  @override
  Stream<AirQualityReading> subscribeToLiveReadings() {
    _readingController ??= StreamController<AirQualityReading>.broadcast();
    _ensureSampleTimerRunning();
    return _readingController!.stream;
  }

  @override
  Future<AirQualityReading?> getLatestReading() async => _buildReading();

  @override
  Future<List<AirQualityReading>> getHistoricalReadings({
    required DateTime from,
    required DateTime to,
  }) async {
    // Generate a plausible history at 10-second intervals for anything
    // that queries the data source directly (the History screen will
    // read from the database instead, but this preserves parity with
    // the old MockDataSource).
    final readings = <AirQualityReading>[];
    DateTime cursor = from;
    while (cursor.isBefore(to)) {
      readings.add(_buildReading());
      cursor = cursor.add(const Duration(seconds: 10));
    }
    return readings;
  }

  // ═════════════════════════════════════════════════════════════════
  // Device-connection half. Always report connected; synthesise a
  // DeviceStatus in step with each sample tick, so the UI in Step 7
  // can be built against a mock that visibly updates.
  // ═════════════════════════════════════════════════════════════════

  StreamController<DeviceConnectionState>? _stateController;
  StreamController<DeviceStatus>? _statusController;
  StreamController<List<DiscoveredDevice>>? _scanController;

  final DeviceConnectionState _currentState = DeviceConnectionState.connected;
  DeviceStatus? _latestStatus;
  final ValueNotifier<DateTime?> _lastSeenNotifier =
      ValueNotifier<DateTime?>(null);

  /// Mock is always "already paired" — initialised to `true` and never
  /// flips. Exposed reactively so any Step 7 UI wired against
  /// `pairingCompleteListenable` compiles identically against mock and
  /// real managers.
  final ValueNotifier<bool> _pairingComplete = ValueNotifier<bool>(true);

  // Simple synthetic battery: drop 1% every 6 ticks (~1 min), floor at
  // 20%, wrap back to 100%. Purely to make the UI look alive.
  int _syntheticBattery = 100;
  int _tickCount = 0;

  /// Shared sample cadence for both the reading stream and the status
  /// stream. Whichever stream is listened to first starts the timer;
  /// subsequent listens are cheap.
  void _ensureSampleTimerRunning() {
    if (_sampleTimer != null) return;
    _emitTick(); // fire an immediate first tick on first subscribe
    _sampleTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _emitTick(),
    );
  }

  void _emitTick() {
    final reading = _buildReading();
    _lastSeenNotifier.value = DateTime.now();
    _readingController?.add(reading);
    _emitSyntheticStatus();
  }

  void _emitSyntheticStatus() {
    _tickCount++;
    if (_tickCount % 6 == 0) {
      _syntheticBattery =
          _syntheticBattery <= 20 ? 100 : _syntheticBattery - 1;
    }

    final status = DeviceStatus(
      uptimeSeconds:     _tickCount * 10,
      totalSamples:      _sequence,
      oldestBufferedSeq: 0,
      newestBufferedSeq: 0,
      bufferedCount:     0,
      batteryPercent:    _syntheticBattery,
      conditioning:      false,
      shuttingDown:      false,
      receivedAt:        DateTime.now(),
    );
    _latestStatus = status;
    _statusController?.add(status);
  }

  @override
  Stream<DeviceConnectionState> get stateStream {
    _stateController ??= StreamController<DeviceConnectionState>.broadcast();
    return _stateController!.stream;
  }

  @override
  Stream<DeviceStatus> get statusStream {
    _statusController ??= StreamController<DeviceStatus>.broadcast();
    _ensureSampleTimerRunning();
    return _statusController!.stream;
  }

  @override
  Stream<List<DiscoveredDevice>> get scanResults {
    _scanController ??=
        StreamController<List<DiscoveredDevice>>.broadcast();
    return _scanController!.stream;
  }

  @override
  DeviceConnectionState get currentState => _currentState;

  @override
  DeviceStatus? get latestStatus => _latestStatus;

  @override
  int? get batteryPercent => _latestStatus?.batteryPercent;

  @override
  int? get bufferedCount => _latestStatus?.bufferedCount;

  @override
  DateTime? get lastSeen => _lastSeenNotifier.value;

  @override
  ValueListenable<DateTime?> get lastSeenListenable => _lastSeenNotifier;

  @override
  ValueListenable<bool> get pairingCompleteListenable => _pairingComplete;

  @override
  bool get shuttingDownReceived => false;

  // Action methods: all no-ops. The mock is always connected; there is
  // nothing to start, scan for, pair with, forget, or reconnect to.
  // The state stream is intentionally silent so a UI wired up against
  // the mock sees only the always-connected initial state.

  @override
  Future<void> start() async {}

  @override
  Future<void> startScan() async {
    // The mock never advertises discoverable peripherals; emit an
    // empty snapshot so any subscribed scan UI shows "no devices"
    // cleanly rather than a bare loading spinner forever.
    _scanController ??=
        StreamController<List<DiscoveredDevice>>.broadcast();
    _scanController!.add(const <DiscoveredDevice>[]);
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> pair(DiscoveredDevice device) async {}

  @override
  Future<void> forget() async {}

  @override
  Future<void> reconnect() async {}

  // ═════════════════════════════════════════════════════════════════
  // Shared lifecycle.
  // ═════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _readingController?.close();
    _readingController = null;
    _stateController?.close();
    _stateController = null;
    _statusController?.close();
    _statusController = null;
    _scanController?.close();
    _scanController = null;
    _pairingComplete.dispose();
    _lastSeenNotifier.dispose();
  }
}