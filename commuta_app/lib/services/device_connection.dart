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

  Future<void> start();
  Future<void> startScan();
  Future<void> stopScan();
  Future<void> pair(DiscoveredDevice device);
  Future<void> reconnect();
  Future<void> forget();
  void dispose();
}