import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../data/datasources/air_quality_datasource.dart';
import '../data/datasources/ble_manager.dart';
import 'device_connection.dart';
import 'device_persistence_service.dart';
import 'readings_repository.dart';
import 'station_classification_service.dart';
import 'tfl_map_data.dart';

/// Process-wide service holder.
///
/// Holds the shared [AirQualityDataSource], the sibling
/// [DeviceConnection], the [AppDatabase], the [ReadingsRepository],
/// the [StationClassificationService], and the
/// [DevicePersistenceService], so every screen reads from the same
/// instances and every reading lands in one durable store.
/// Initialised once in `main()` before `runApp`.
///
/// Pattern mirrors [TflMapData.instance].
class AppServices {
  AppServices._();
  static final AppServices instance = AppServices._();

  /// SharedPreferences key gating the one-shot clear of any mock
  /// readings left over from before the BLE cutover. Set to `true`
  /// once the clear has run so subsequent launches skip it entirely.
  ///
  /// The `_v1` suffix leaves room to bump the key if a future
  /// migration ever needs to re-run a similar one-shot wipe against
  /// a different `sourceFlag`.
  static const String _mockReadingsClearedKey = 'mock_readings_cleared_v1';

  bool _initialised = false;

  /// The shared air-quality data source. Same underlying [BLEManager]
  /// instance also implements [DeviceConnection] and is exposed via
  /// [deviceConnection].
  late final AirQualityDataSource dataSource;

  /// The shared device-connection surface. Same underlying instance
  /// as [dataSource] — split into two fields so consumers only depend
  /// on the half they need.
  late final DeviceConnection deviceConnection;

  /// Drift database. Used by [readingsRepository]; screens should
  /// not query it directly.
  late final AppDatabase database;

  /// Subscribes to [dataSource] from app startup and persists every
  /// reading to [database].
  late final ReadingsRepository readingsRepository;

  /// Watches location + readings and tags readings to the TfL station
  /// the user is currently at. Owns the current-station notifier that
  /// drives the TfL map halo. Persists for the whole session, so
  /// classification continues regardless of which tab is open.
  late final StationClassificationService classificationService;

  /// Cross-session persistence for the last-seen timestamp and the
  /// "samples not yet synced" flag. Seeded from prefs on init and
  /// kept in sync via listeners on the shared [deviceConnection].
  /// Read by the Device sub-page and by any other surface that
  /// needs those values to survive a force-quit.
  late final DevicePersistenceService devicePersistence;

  /// Idempotent app-startup bootstrap. Call once from `main()` after
  /// `WidgetsFlutterBinding.ensureInitialized()` and before `runApp`.
  ///
  /// Sequencing (Step 7 cutover, extended in 7b):
  ///   1. TfL map data loads first — no BLE dependencies, position
  ///      is unimportant.
  ///   2. Database is created before the mock-clear check so the DAO
  ///      call has somewhere to run.
  ///   3. The one-shot mock-clear runs before the repository is
  ///      wired, so the repository never subscribes against a table
  ///      still holding `sourceFlag = 'mock'` rows from the previous
  ///      MockManager era.
  ///   4. BLEManager is created as a concrete reference so
  ///      `eraSequenceNumbersProvider` can be wired — the field is
  ///      on the concrete class, not on either interface.
  ///   5. The repository is constructed *before* the provider is
  ///      wired (the provider is a reference to one of its methods)
  ///      and started *before* the BLE manager (so live and buffered
  ///      subscriptions exist before the first packet can arrive).
  ///   6. `bleManager.start()` is awaited. It returns as soon as
  ///      the persisted identifier has been read from
  ///      SharedPreferences. The auto-reconnect itself runs in the
  ///      background and does not block `init()`.
  ///   7. (7b) [DevicePersistenceService] is created and started
  ///      after the manager. It reuses the already-loaded `prefs`
  ///      instance and attaches listeners to the manager's
  ///      last-seen listenable and status stream.
  Future<void> init() async {
    if (_initialised) return;

    await TflMapData.instance.load();

    // ── Database ─────────────────────────────────────────────────
    database = AppDatabase();

    // ── One-shot clear of pre-cutover mock rows ──────────────────
    // First launch after the BLE cutover deletes every row whose
    // sourceFlag is 'mock', so buffered sync starts from a truly-
    // empty DB rather than resuming against the mock's sequence
    // numbers. Subsequent launches see the flag set and skip the
    // delete entirely. Zero-touch, idempotent, safe to leave in
    // the code indefinitely.
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_mockReadingsClearedKey) ?? false)) {
      final removed =
          await database.deleteReadingsWhereSourceFlag('mock');
      debugPrint(
        '[AppServices] Cutover mock-clear: removed $removed row(s) '
        "where sourceFlag = 'mock'.",
      );
      await prefs.setBool(_mockReadingsClearedKey, true);
    }

    // ── BLE cutover ──────────────────────────────────────────────
    // Concrete BLEManager reference — needed to wire
    // `eraSequenceNumbersProvider`, which lives on the concrete class
    // rather than on either interface. The two interface-typed late
    // finals below both point at the same instance.
    final manager = BLEManager();
    dataSource = manager;
    deviceConnection = manager;

    // ── Repository ───────────────────────────────────────────────
    // Constructed before the provider is wired, since the provider
    // is a reference to one of its methods.
    readingsRepository = ReadingsRepository(database, dataSource);

    // Break the constructor-time chicken-and-egg between repo and
    // manager: the manager needs to ask the repo which sequence
    // numbers are already persisted within the device's current
    // power session when it evaluates the gap-aware buffered sync,
    // but the repo needs the data source to construct.
    manager.eraSequenceNumbersProvider =
        readingsRepository.getSequenceNumbersSince;

    // Subscribe before starting the manager, so live and buffered
    // streams have listeners in place before the first packet.
    readingsRepository.start();

    // Kick off silent auto-reconnect. Returns after the persisted
    // identifier has been read from SharedPreferences; the actual
    // reconnect runs in the background.
    await manager.start();

    // ── Device persistence (7b) ──────────────────────────────────
    // Wired after the manager is available so the service can hook
    // onto the manager's `lastSeenListenable` and `statusStream`
    // straight away. Reuses the `prefs` instance opened above.
    devicePersistence =
        DevicePersistenceService(prefs, deviceConnection);
    devicePersistence.start();

    // ── Classification service ───────────────────────────────────
    classificationService =
        StationClassificationService(dataSource, readingsRepository);
    classificationService.start();
    // Note: startLocationTracking() is deliberately NOT called here.
    // Location permission must not be requested in main() before any
    // UI exists — the main scaffold calls it once it is on screen.

    _initialised = true;
  }

  /// Release resources. Mainly for tests; Flutter rarely calls this
  /// on a real device.
  Future<void> dispose() async {
    if (!_initialised) return;
    // Reverse order of creation: services that only listen come
    // first, then the repository (which closes the database), then
    // the data source itself.
    await classificationService.dispose();
    await devicePersistence.dispose();
    await readingsRepository.dispose(); // also closes the database
    dataSource.dispose();
    _initialised = false;
  }
}