import '../data/database/app_database.dart';
import '../data/datasources/air_quality_datasource.dart';
import '../data/datasources/mock_datasource.dart';
import 'readings_repository.dart';
import 'tfl_map_data.dart';

/// Process-wide service holder.
///
/// Holds the shared [AirQualityDataSource], the [AppDatabase], and the
/// [ReadingsRepository] so every screen reads from the same instances
/// and every reading lands in one durable store.
/// Initialised once in `main()` before `runApp`.
///
/// Pattern mirrors [TflMapData.instance].
class AppServices {
  AppServices._();
  static final AppServices instance = AppServices._();

  bool _initialised = false;

  /// The shared air quality data source. Swap [MockDataSource] for
  /// `BLEDataSource` in [init] when BLE is ready — this is the only
  /// line in the app that needs to change.
  late final AirQualityDataSource dataSource;

  /// Drift database. Used by [readingsRepository]; screens should
  /// not query it directly.
  late final AppDatabase database;

  /// Subscribes to [dataSource] from app startup and persists every
  /// reading to [database].
  late final ReadingsRepository readingsRepository;

  /// Idempotent app-startup bootstrap. Call once from `main()` after
  /// `WidgetsFlutterBinding.ensureInitialized()` and before `runApp`.
  Future<void> init() async {
    if (_initialised) return;

    await TflMapData.instance.load();

    dataSource = MockDataSource();
    database = AppDatabase();
    readingsRepository = ReadingsRepository(database, dataSource);
    readingsRepository.start();

    _initialised = true;
  }

  /// Release resources. Mainly for tests; Flutter rarely calls this
  /// on a real device.
  Future<void> dispose() async {
    if (!_initialised) return;
    await readingsRepository.dispose(); // also closes the database
    dataSource.dispose();
    _initialised = false;
  }
}