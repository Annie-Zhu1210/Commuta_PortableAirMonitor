import 'dart:async';
import 'package:flutter/foundation.dart';

/// Lifecycle of the connection to the physical Commuta device.
enum DeviceConnectionState {
  idle,
  scanning,
  connecting,
  connected,
  syncingBuffered,
  disconnected,
}

/// The phone's own Bluetooth radio state, decoupled from the state of
/// the connection to the Commuta device.
///
/// Pair-UI and Settings surfaces render a "Bluetooth is off" or
/// "Grant Bluetooth permission" affordance based on this, distinct
/// from the pair / scan / connected flow driven by
/// [DeviceConnectionState].
///
/// Deliberately wraps `flutter_blue_plus`'s `BluetoothAdapterState`
/// rather than passing it through — the [DeviceConnection] interface
/// stays library-agnostic (`MockManager` never has to import
/// `flutter_blue_plus`), and this enum collapses transient states
/// (turning on / off, unavailable on this hardware) into [unknown]
/// so UI code doesn't have to handle them individually.
enum BluetoothAvailability {
  /// Adapter is on and ready to scan / connect.
  on,

  /// Adapter is off; user needs to enable Bluetooth in system
  /// settings.
  off,

  /// App lacks Bluetooth permission; user needs to authorise it in
  /// system settings.
  unauthorised,

  /// State is indeterminate — either the adapter is transitioning
  /// (turningOn / turningOff), unavailable on this hardware, or has
  /// not yet reported after app start.
  unknown,
}

class DeviceStatus {
  DeviceStatus({
    required this.batteryPercent,
    required this.bufferedCount,
    required this.uptimeSeconds,
    required this.totalSamples,
    required this.oldestBufferedSeq,
    required this.newestBufferedSeq,
    required this.shuttingDown,
    required this.conditioning,
    required this.receivedAt,
  });

  final int batteryPercent;
  final int bufferedCount;
  final int uptimeSeconds;
  final int totalSamples;
  final int oldestBufferedSeq;
  final int newestBufferedSeq;
  final bool shuttingDown;
  final bool conditioning;
  final DateTime receivedAt;
}

class DiscoveredDevice {
  DiscoveredDevice({
    required this.identifier,
    required this.name,
    required this.rssi,
  });

  final String identifier;
  final String name;
  final int rssi;
}

/// Everything about the physical Commuta device that isn't an
/// [AirQualityReading].
abstract class DeviceConnection {
  Stream<DeviceConnectionState> get stateStream;
  DeviceConnectionState get currentState;

  Stream<DeviceStatus> get statusStream;
  DeviceStatus? get latestStatus;

  int? get batteryPercent;
  int? get bufferedCount;

  /// Wall-clock time the last Live or Status notification arrived, or
  /// null if nothing has arrived this session. Synchronous read;
  /// prefer [lastSeenListenable] in widgets that need to rebuild live.
  DateTime? get lastSeen;

  /// Reactive view of [lastSeen]. Rebuilds subscribing widgets each
  /// time a packet arrives. Value is null until the first packet.
  ValueListenable<DateTime?> get lastSeenListenable;

  ValueListenable<bool> get pairingCompleteListenable;
  bool get shuttingDownReceived;

  Stream<List<DiscoveredDevice>> get scanResults;

  /// Reactive view of the phone's Bluetooth adapter state. Emits on
  /// every change; prefer [adapterState] for a synchronous read.
  ///
  /// UI wiring: a top-level "Bluetooth off" or "unauthorised" banner
  /// listens here and takes precedence over pair-flow affordances,
  /// since neither pairing nor scanning can proceed unless the
  /// adapter is [BluetoothAvailability.on].
  Stream<BluetoothAvailability> get adapterStateStream;

  /// Synchronous read of the current Bluetooth adapter state. Use
  /// this to seed a `StreamBuilder`'s `initialData` when subscribing
  /// to [adapterStateStream].
  BluetoothAvailability get adapterState;

  Future<void> start();
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> pair(DiscoveredDevice device);
  Future<void> reconnect();
  Future<void> forget();
  void dispose();
}