import 'dart:async';

import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import '../data/datasources/air_quality_datasource.dart';
import '../data/models/air_quality_reading.dart';

/// Owns the [AppDatabase] and is the single point of persistence for
/// air quality readings.
///
/// Subscribes to both the live and buffered streams on the shared
/// [AirQualityDataSource] from app startup, so every reading — whether
/// it arrived in real time or was replayed from the device's flash
/// buffer during a catch-up sync — is durably persisted on arrival
/// with `stationId = null`. The `StationClassificationService`
/// (Phase 5) later calls [classifyReading] to attach a station to a
/// reading; the underlying write is an idempotent UPSERT keyed on
/// `(sequenceNumber, timestamp)`, so it doesn't matter whether
/// classification beats the raw write, whether the raw write came
/// from the live or buffered stream, or the other way round.
///
/// Lifecycle owned by `AppServices`.
class ReadingsRepository {
  ReadingsRepository(this._db, this._dataSource);

  final AppDatabase _db;
  final AirQualityDataSource _dataSource;
  StreamSubscription<AirQualityReading>? _liveSub;
  StreamSubscription<AirQualityReading>? _bufferedSub;

  /// Begin persisting incoming readings from both live and buffered
  /// streams. Idempotent — repeat calls are no-ops.
  void start() {
    _liveSub ??= _dataSource.subscribeToLiveReadings().listen(_persistRaw);
    _bufferedSub ??=
        _dataSource.subscribeToBufferedReadings().listen(_persistRaw);
  }

  /// Persist a reading as it arrives, with no classification.
  /// If a row with the same `(sequenceNumber, timestamp)` already
  /// exists — because classification beat us to it, or because a
  /// buffered record duplicates one we already have — leave it alone.
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

  /// Returns the number of readings whose `timestamp` falls within
  /// `[from, to]` (both bounds inclusive, matching the semantics of
  /// [getReadingsBetween]).
  ///
  /// Used by the CSV export screen to preview how many rows the
  /// "Today" button will include before the user commits to the
  /// export. Mirrors the shape of [countAll]: a single SELECT COUNT
  /// with no row materialisation, so it's cheap to call on every
  /// screen open.
  Future<int> countBetween(DateTime from, DateTime to) async {
    final countExp = _db.readings.id.count();
    final row =
        await (_db.selectOnly(_db.readings)
              ..addColumns([countExp])
              ..where(_db.readings.timestamp.isBetweenValues(from, to)))
            .getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Returns the largest `sequenceNumber` currently in the readings
  /// table, or `null` when the table is empty.
  ///
  /// Used by `BLEManager` on `connected` (after the first Live and
  /// first Status notifications have landed) to decide whether a
  /// buffered catch-up sync is needed. A `null` return means "empty
  /// DB, sync everything the device has"; otherwise the manager
  /// requests the range `[result + 1 .. 0xFFFFFFFF]`.
  ///
  /// Note: on firmware reset the device restarts its sequence counter,
  /// so a device `newest_buffered_seq` lower than this value doesn't
  /// necessarily mean the buffer is stale — the two "eras" of
  /// sequence numbers coexist in the DB, distinguished by their
  /// timestamps. Per Decision 4A of the Step 6 architecture review,
  /// `BLEManager` skips sync in that case rather than attempting a
  /// full-range refetch.
  Future<int?> getHighestSequenceNumber() async {
    final maxExp = _db.readings.sequenceNumber.max();
    final row = await (_db.selectOnly(
      _db.readings,
    )..addColumns([maxExp])).getSingle();
    return row.read(maxExp);
  }

  /// Release resources. Called by `AppServices.dispose()`.
  Future<void> dispose() async {
    await _liveSub?.cancel();
    await _bufferedSub?.cancel();
    _liveSub = null;
    _bufferedSub = null;
    await _db.close();
  }

  // ── Model ↔ row conversion ────────────────────────────────────────────

  ReadingsCompanion _toCompanion(AirQualityReading r) {
    return ReadingsCompanion(
      sequenceNumber:         Value(r.sequenceNumber),
      timestamp:              Value(r.timestamp),
      pm1:                    Value(r.pm1),
      pm25:                   Value(r.pm25),
      pm10:                   Value(r.pm10),
      co2:                    Value(r.co2),
      temperature:            Value(r.temperature),
      humidity:               Value(r.humidity),
      pressure:               Value(r.pressure),
      pressureChangePaPerSec: Value(r.pressureChangePaPerSec),
      nox:                    Value(r.nox),
      tvoc:                   Value(r.tvoc),
      vocRaw:                 Value(r.vocRaw),
      noxRaw:                 Value(r.noxRaw),
      sourceFlag:             Value(r.sourceFlag),
      stationId:              Value(r.stationId),
      lineId:                 Value(r.lineId),
      gpsLat:                 Value(r.gpsLat),
      gpsLng:                 Value(r.gpsLng),
    );
  }

  AirQualityReading _fromRow(Reading row) {
    return AirQualityReading(
      timestamp:              row.timestamp,
      pm1:                    row.pm1,
      pm25:                   row.pm25,
      pm10:                   row.pm10,
      co2:                    row.co2,
      temperature:            row.temperature,
      humidity:               row.humidity,
      pressure:               row.pressure,
      pressureChangePaPerSec: row.pressureChangePaPerSec,
      nox:                    row.nox,
      tvoc:                   row.tvoc,
      vocRaw:                 row.vocRaw,
      noxRaw:                 row.noxRaw,
      sourceFlag:             row.sourceFlag,
      sequenceNumber:         row.sequenceNumber,
      stationId:              row.stationId,
      lineId:                 row.lineId,
      gpsLat:                 row.gpsLat,
      gpsLng:                 row.gpsLng,
    );
  }
}