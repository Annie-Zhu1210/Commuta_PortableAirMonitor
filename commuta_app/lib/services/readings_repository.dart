import 'dart:async';

import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import '../data/datasources/air_quality_datasource.dart';
import '../data/models/air_quality_reading.dart';

/// Owns the [AppDatabase] and is the single point of persistence for
/// air quality readings.
///
/// Subscribes to the shared [AirQualityDataSource] from app startup,
/// so every reading is durably persisted on arrival with
/// `stationId = null`. The `StationClassificationService` (Phase 5)
/// later calls [classifyReading] to attach a station to a reading;
/// the underlying write is an idempotent UPSERT keyed on
/// `(sequenceNumber, timestamp)`, so it doesn't matter whether
/// classification beats the raw write or the other way round.
///
/// Lifecycle owned by `AppServices`.
class ReadingsRepository {
  ReadingsRepository(this._db, this._dataSource);

  final AppDatabase _db;
  final AirQualityDataSource _dataSource;
  StreamSubscription<AirQualityReading>? _sub;

  /// Begin persisting incoming readings. Idempotent — repeat calls
  /// are no-ops.
  void start() {
    _sub ??= _dataSource.subscribeToLiveReadings().listen(_persistRaw);
  }

  /// Persist a reading as it arrives, with no classification.
  /// If a row with the same `(sequenceNumber, timestamp)` already
  /// exists — because classification beat us to it — leave it alone.
  Future<void> _persistRaw(AirQualityReading r) async {
    await _db.into(_db.readings).insert(
      _toCompanion(r),
      onConflict: DoNothing(),
    );
  }

  /// Called by the classification service. Idempotent UPSERT:
  /// if the raw reading hasn't been persisted yet, this writes the
  /// complete row including the classification. If it has, this
  /// updates only the classification fields.
  Future<void> classifyReading({
    required AirQualityReading reading,
    required String stationId,
    String? lineId,
  }) async {
    final companion = _toCompanion(
      reading,
    ).copyWith(stationId: Value(stationId), lineId: Value(lineId));
    await _db
        .into(_db.readings)
        .insert(
          companion,
          onConflict: DoUpdate(
            (_) => ReadingsCompanion(
              stationId: Value(stationId),
              lineId: Value(lineId),
            ),
            target: [_db.readings.sequenceNumber, _db.readings.timestamp],
          ),
        );
  }

  // ── Query API (for History / CSV export / station detail) ──────────────

  Future<List<AirQualityReading>> getAllReadings() async {
    final rows = await (_db.select(
      _db.readings,
    )..orderBy([(t) => OrderingTerm.asc(t.timestamp)])).get();
    return rows.map(_fromRow).toList();
  }

  Future<List<AirQualityReading>> getReadingsBetween(
    DateTime from,
    DateTime to,
  ) async {
    final rows =
        await (_db.select(_db.readings)
              ..where((t) => t.timestamp.isBetweenValues(from, to))
              ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
            .get();
    return rows.map(_fromRow).toList();
  }

  Future<List<AirQualityReading>> getReadingsForStation(
    String stationId,
  ) async {
    final rows =
        await (_db.select(_db.readings)
              ..where((t) => t.stationId.equals(stationId))
              ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
            .get();
    return rows.map(_fromRow).toList();
  }

  Future<int> countAll() async {
    final countExp = _db.readings.id.count();
    final row = await (_db.selectOnly(
      _db.readings,
    )..addColumns([countExp])).getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Release resources. Called by `AppServices.dispose()`.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _db.close();
  }

  // ── Model ↔ row conversion ────────────────────────────────────────────

  ReadingsCompanion _toCompanion(AirQualityReading r) {
    return ReadingsCompanion(
      sequenceNumber: Value(r.sequenceNumber),
      timestamp: Value(r.timestamp),
      pm1: Value(r.pm1),
      pm25: Value(r.pm25),
      pm10: Value(r.pm10),
      co2: Value(r.co2),
      temperature: Value(r.temperature),
      humidity: Value(r.humidity),
      pressure: Value(r.pressure),
      pressureChangePaPerSec: Value(r.pressureChangePaPerSec),
      nox: Value(r.nox),
      tvoc: Value(r.tvoc),
      sourceFlag: Value(r.sourceFlag),
      stationId: Value(r.stationId),
      lineId: Value(r.lineId),
      gpsLat: Value(r.gpsLat),
      gpsLng: Value(r.gpsLng),
    );
  }

  AirQualityReading _fromRow(Reading row) {
    return AirQualityReading(
      timestamp: row.timestamp,
      pm1: row.pm1,
      pm25: row.pm25,
      pm10: row.pm10,
      co2: row.co2,
      temperature: row.temperature,
      humidity: row.humidity,
      pressure: row.pressure,
      pressureChangePaPerSec: row.pressureChangePaPerSec,
      nox: row.nox,
      tvoc: row.tvoc,
      sourceFlag: row.sourceFlag,
      sequenceNumber: row.sequenceNumber,
      stationId: row.stationId,
      lineId: row.lineId,
      gpsLat: row.gpsLat,
      gpsLng: row.gpsLng,
    );
  }
}
