import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_connection.dart';

/// Session-independent persistence for two pieces of device state
/// that need to survive process death.
///
/// * `last_seen_iso` — the wall-clock time of the most recent Live
///   or Status notification. On a cold start the manager's own
///   [DeviceConnection.lastSeenListenable] is null until the first
///   packet arrives, so without this the Device screen would show
///   "—" for the entire reconnect window. Seeded from prefs on
///   [start], updated in memory on every packet, written to disk
///   at most once per [_lastSeenWriteInterval] to keep write churn
///   low.
///
/// * `pending_buffered_since_shutdown` — set to an ISO-8601
///   timestamp the moment a status packet arrives with the
///   `SHUTTING_DOWN` flag set, and cleared the moment a subsequent
///   status packet reports `bufferedCount == 0`. The manager's
///   in-memory [DeviceConnection.shuttingDownReceived] latch is
///   session-only, so persisting is what lets the "samples not yet
///   synced" indicator survive a force-quit between the shutdown
///   event and the next successful sync.
///
/// Neither notifier fans out through the manager itself — this
/// service is intentionally a peer, so the [DeviceConnection]
/// interface stays lean and no manager implementation has to know
/// about [SharedPreferences].
class DevicePersistenceService {
  DevicePersistenceService(this._prefs, this._connection);

  final SharedPreferences _prefs;
  final DeviceConnection _connection;

  static const String _lastSeenKey = 'last_seen_iso';
  static const String _shutdownPendingKey =
      'pending_buffered_since_shutdown';

  /// Throttle for `last_seen_iso` writes. `lastSeen` updates on
  /// every Live or Status packet — Live arrives every ~10 s, so
  /// unthrottled we would hit disk ~six times a minute. 30 s keeps
  /// writes rare while bounding the loss window to half a minute
  /// on a crash.
  static const Duration _lastSeenWriteInterval = Duration(seconds: 30);

  /// Live-tracking notifier for the last-seen timestamp. Seeded from
  /// prefs on [start], updated in memory on every packet. Consumers
  /// should read from this rather than hitting prefs directly.
  late final ValueNotifier<DateTime?> lastSeen;

  /// True when a `SHUTTING_DOWN` flag has been observed at any
  /// point (this session or a previous one) and buffered data has
  /// not yet finished syncing. Drives the Device screen's "samples
  /// not yet synced" row.
  late final ValueNotifier<bool> shutdownPending;

  DateTime? _lastPersistedLastSeen;
  StreamSubscription<DeviceStatus>? _statusSubscription;
  bool _started = false;

  /// Idempotent. Call once after the [DeviceConnection] is
  /// constructed. Seeds both notifiers from prefs and starts
  /// listening to the manager for updates.
  void start() {
    if (_started) return;
    _started = true;

    // ── Seed from prefs ─────────────────────────────────────────
    final lastSeenIso = _prefs.getString(_lastSeenKey);
    final seededLastSeen =
        lastSeenIso != null ? DateTime.tryParse(lastSeenIso) : null;
    lastSeen = ValueNotifier<DateTime?>(seededLastSeen);
    _lastPersistedLastSeen = seededLastSeen;

    // Presence of the key alone is enough — we don't need to parse
    // the timestamp back out. The value is only there for future
    // diagnostic use.
    final shutdownIso = _prefs.getString(_shutdownPendingKey);
    shutdownPending = ValueNotifier<bool>(shutdownIso != null);

    // ── Listen to manager for live updates ─────────────────────
    _connection.lastSeenListenable.addListener(_onLastSeenChanged);
    // Prime once in case the manager already has a non-null value
    // (e.g. hot reload during development).
    _onLastSeenChanged();

    _statusSubscription =
        _connection.statusStream.listen(_onStatus);
  }

  void _onLastSeenChanged() {
    final live = _connection.lastSeenListenable.value;
    if (live == null) return;

    // Update the in-memory notifier immediately so the UI shows
    // fresh "just now" values without waiting for the throttled
    // disk write.
    lastSeen.value = live;

    // Throttled write to disk.
    final lastPersisted = _lastPersistedLastSeen;
    if (lastPersisted == null ||
        live.difference(lastPersisted).abs() >=
            _lastSeenWriteInterval) {
      _prefs.setString(_lastSeenKey, live.toIso8601String());
      _lastPersistedLastSeen = live;
    }
  }

  void _onStatus(DeviceStatus status) {
    // ── Set pending on first sighting of the shutdown flag ─────
    if (status.shuttingDown && !shutdownPending.value) {
      shutdownPending.value = true;
      _prefs.setString(
        _shutdownPendingKey,
        DateTime.now().toIso8601String(),
      );
    }

    // ── Clear pending once buffered data has been drained ──────
    // Guard against the edge case where the device reports
    // `bufferedCount == 0` while `shuttingDown` is still true —
    // leave pending set until the shutdown flag also clears (which
    // it does on the next reboot, since the flag is session-scoped
    // on the firmware side).
    if (shutdownPending.value &&
        status.bufferedCount == 0 &&
        !status.shuttingDown) {
      shutdownPending.value = false;
      _prefs.remove(_shutdownPendingKey);
    }
  }

  Future<void> dispose() async {
    if (!_started) return;
    _started = false;
    _connection.lastSeenListenable.removeListener(_onLastSeenChanged);
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    lastSeen.dispose();
    shutdownPending.dispose();
  }
}