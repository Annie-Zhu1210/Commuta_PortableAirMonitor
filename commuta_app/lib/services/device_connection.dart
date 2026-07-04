import 'dart:async';

/// Lifecycle states the physical device can be in from the app's point
/// of view.
///
/// A single [DeviceConnection.stateStream] carries transitions between
/// these values. The top status bar and the Settings device section
/// both subscribe to that stream.
enum DeviceConnectionState {
  /// Manager initialised, nothing happening. No persisted device, or
  /// [DeviceConnection.forget] was just called.
  idle,

  /// Actively scanning for the Commuta service UUID during first-run
  /// pairing.
  scanning,

  /// A peripheral has been selected; GATT discovery is in progress.
  connecting,

  /// GATT services bound, Live and Status notifications subscribed.
  /// This is the normal operating state.
  connected,

  /// Pulling missed buffered samples after a (re)connect. Sits between
  /// [connecting] and [connected] on the reconnect path; live samples
  /// may still arrive during this state.
  syncingBuffered,

  /// Was previously connected; the BLE link is now down. Auto-reconnect
  /// may or may not be attempting to recover — the state reflects link
  /// reality, not intent.
  disconnected,
}

/// Snapshot decoded from a single Status characteristic notification.
///
/// The 8-bit `flags` byte on the wire is decomposed here into two
/// booleans so UI code never has to know the bit layout.
class DeviceStatus {
  const DeviceStatus({
    required this.uptimeSeconds,
    required this.totalSamples,
    required this.oldestBufferedSeq,
    required this.newestBufferedSeq,
    required this.bufferedCount,
    required this.batteryPercent,
    required this.conditioning,
    required this.shuttingDown,
    required this.receivedAt,
  });

  /// Seconds since the device booted. Resets on firmware reboot.
  final int uptimeSeconds;

  /// Cumulative sample count since firmware boot. Also resets on reboot.
  final int totalSamples;

  /// Lowest sequence number currently held on the device's flash buffer.
  final int oldestBufferedSeq;

  /// Highest sequence number currently held on the device's flash buffer.
  final int newestBufferedSeq;

  /// Number of samples currently held on the device's flash buffer —
  /// what the phone hasn't drained yet from the device's perspective.
  /// The app persists everything it sees regardless, so this number
  /// only reflects device-side inventory.
  final int bufferedCount;

  /// Battery charge, 0–100.
  final int batteryPercent;

  /// SGP41 NOx pixel is still warming up. While true, `voc_index` and
  /// `nox_index` on the Live characteristic are unreliable and must be
  /// recorded as null on the resulting [AirQualityReading].
  final bool conditioning;

  /// This Status is the last one before the device deep-sleeps. If the
  /// buffered count on this Status is non-zero, the Settings device
  /// section should surface a "samples unsynced" indicator.
  final bool shuttingDown;

  /// Client-side timestamp of when this notification was received. The
  /// app is the source of truth for time (see the timestamp
  /// reconstruction rules in `BLE_Integration_Plan.md`).
  final DateTime receivedAt;
}

/// A device discovered during a BLE scan. Handed to
/// [DeviceConnection.pair] to initiate a connection.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// Opaque peripheral identifier. On iOS this is a per-app UUID that
  /// CoreBluetooth mints for the device — it is not the BLE MAC and
  /// not the same UUID as the service UUID in `secrets.h`. On Android
  /// it is a MAC-like identifier. Either way the app treats it as
  /// opaque: persist what the platform gives us, hand it back on
  /// reconnect.
  final String id;

  /// Advertised device name (e.g. `Commuta-A4F2`).
  final String name;

  /// Signal strength in dBm at the moment of discovery. Useful for
  /// showing nearest devices first in the scan UI, but not persisted.
  final int rssi;
}

/// Everything specific to the physical device: connection lifecycle,
/// battery, buffered count, pair/scan/forget actions.
///
/// Sibling interface to `AirQualityDataSource`. Both interfaces are
/// implemented by a single concrete class (`MockManager` for
/// development, `BLEManager` for the live device). `AppServices`
/// exposes one instance under two field names so subscribers can hold
/// exactly the surface they care about without leaking device concepts
/// into air-quality consumers or vice versa.
///
/// Reactive fields have both a stream (for change notifications) and a
/// getter (for the current snapshot). UI that only cares about the
/// current value can use the getter; UI that needs to update on change
/// combines the two, typically via `StreamBuilder(initialData:
/// manager.currentState, stream: manager.stateStream)`.
abstract class DeviceConnection {
  // ── Reactive streams (all broadcast) ────────────────────────────

  /// Emits on every state transition. Multiple listeners share the
  /// same sequence of events. New subscribers do NOT automatically
  /// receive the current state — combine with [currentState] for that.
  Stream<DeviceConnectionState> get stateStream;

  /// Emits every time a Status notification is decoded. Also emits
  /// synthesised values from `MockManager`. Subscribers include the
  /// top status bar (battery percentage) and the Settings device
  /// section (last-seen, buffered count, "samples unsynced").
  Stream<DeviceStatus> get statusStream;

  /// Emits each device found during an active scan. Only active while
  /// [currentState] is [DeviceConnectionState.scanning]; the stream
  /// stays open when scanning stops, it just goes quiet.
  Stream<DiscoveredDevice> get scanResults;

  // ── Current-value getters ───────────────────────────────────────

  /// Most recently transitioned-to state.
  DeviceConnectionState get currentState;

  /// Most recent Status snapshot, or null if no Status has been
  /// received yet in this session.
  DeviceStatus? get latestStatus;

  /// Convenience for `latestStatus?.batteryPercent`. Null before first
  /// Status.
  int? get batteryPercent;

  /// Convenience for `latestStatus?.bufferedCount`. Null before first
  /// Status.
  int? get bufferedCount;

  /// Client-side timestamp of the most recent notification of any kind
  /// (Live or Status). Distinct from `latestStatus?.receivedAt`
  /// because Live notifications refresh this too.
  DateTime? get lastSeen;

  /// True once a peripheral identifier has ever been persisted — i.e.
  /// a successful pair has happened at some point. False on first-ever
  /// launch, and false again after [forget]. This is what
  /// distinguishes "No device" from "Disconnected" in the UI.
  bool get isPaired;

  /// True if the most recent Status had the `SHUTTING_DOWN` flag set.
  /// Combined with a non-zero [bufferedCount], drives the "samples
  /// unsynced" indicator in Settings.
  bool get shuttingDownReceived;

  // ── Actions ─────────────────────────────────────────────────────

  /// Begin scanning for the Commuta service. Results appear on
  /// [scanResults]. Transitions [currentState] to
  /// [DeviceConnectionState.scanning].
  Future<void> startScan();

  /// Stop scanning. Transitions [currentState] back to whatever came
  /// before scanning (typically [DeviceConnectionState.idle]).
  Future<void> stopScan();

  /// Connect to the given discovered device, persist its identifier so
  /// subsequent launches auto-reconnect, and transition through
  /// [DeviceConnectionState.connecting] →
  /// [DeviceConnectionState.connected].
  Future<void> pair(DiscoveredDevice device);

  /// Clear the persisted peripheral identifier, disconnect if
  /// connected, and transition to [DeviceConnectionState.idle].
  /// [isPaired] becomes false.
  Future<void> forget();

  /// Manually attempt to reconnect using the persisted identifier.
  /// No-op if [isPaired] is false. Fails silently if the device is
  /// out of range — that is the normal "device is off" case, not an
  /// error.
  Future<void> reconnect();

  /// Release stream controllers and any BLE resources. Called from
  /// `AppServices.dispose()`.
  void dispose();
}