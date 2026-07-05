import '../data/database/app_database.dart';
import '../data/datasources/air_quality_datasource.dart';
import '../data/datasources/mock_manager.dart';
import 'device_connection.dart';
import 'readings_repository.dart';
import 'station_classification_service.dart';
import 'tfl_map_data.dart';

/// Process-wide service holder.
///
/// Holds the shared [AirQualityDataSource], the sibling
/// [DeviceConnection], the [AppDatabase], the [ReadingsRepository], and
/// the [StationClassificationService], so every screen reads from the
/// same instances and every reading lands in one durable store.
/// Initialised once in `main()` before `runApp`.
///
/// Pattern mirrors [TflMapData.instance].
class AppServices {
  AppServices._();
  static final AppServices instance = AppServices._();

  bool _initialised = false;

  /// The shared air-quality data source. See `dataSource` note on the
  /// cutover line inside [init]: same instance also implements
  /// [DeviceConnection] and is exposed via [deviceConnection].
  late final AirQualityDataSource dataSource;

  /// The shared device-connection surface. Same underlying instance as
  /// [dataSource] — split into two fields so consumers only depend on
  /// the half they need.
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

  /// Idempotent app-startup bootstrap. Call once from `main()` after
  /// `WidgetsFlutterBinding.ensureInitialized()` and before `runApp`.
  Future<void> init() async {
    if (_initialised) return;

    await TflMapData.instance.load();

    // ── The BLE cutover lives on these three lines ─────────────────
    // Step 4 (current): MockManager backs both interfaces. BLEManager
    //   is exercised only via the dev harness on the home screen.
    // Step 7 (cutover): swap `MockManager()` for `BLEManager()` and add
    //   `await manager.start()` on the following line to fire the
    //   silent auto-reconnect. Nothing else in the app needs to change.
    final manager = MockManager();
    dataSource = manager;
    deviceConnection = manager;

    database = AppDatabase();

    // Repository first, so raw persistence is subscribed before the
    // classification service starts attaching stations to readings.
    readingsRepository = ReadingsRepository(database, dataSource);
    readingsRepository.start();

    classificationService =
        StationClassificationService(dataSource, readingsRepository);
    classificationService.start();
    // Note: startLocationTracking() is deliberately NOT called here.
    // Location permission must not be requested in main() before any UI
    // exists — the main scaffold calls it once it is on screen.

    _initialised = true;
  }

  /// Release resources. Mainly for tests; Flutter rarely calls this
  /// on a real device.
  Future<void> dispose() async {
    if (!_initialised) return;
    // Reverse order of creation: service first (it listens to the data
    // source), then the repository (which closes the database).
    await classificationService.dispose();
    await readingsRepository.dispose(); // also closes the database
    dataSource.dispose();
    _initialised = false;
  }
}