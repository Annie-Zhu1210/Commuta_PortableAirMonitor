import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// A single air quality reading row.
///
/// Mirrors [AirQualityReading] 1:1. Notes on the schema choices:
///
/// * Auto-incrementing primary key (`id`) — device sequence numbers
///   reset to 1 on firmware reboot, so they aren't unique across the
///   database's lifetime. Use `id` for row identity; `sequenceNumber`
///   stays an indexed column for diagnostics and the classification
///   UPSERT key.
/// * `(sequenceNumber, timestamp)` is the unique key used by the
///   UPSERT pattern. The pair is unique in practice even across
///   firmware reboots, because the timestamp will differ.
/// * `stationId` and `lineId` are nullable — populated only after
///   `StationClassificationService` runs (Phase 5+). Readings without
///   a station are still kept; classification doesn't gate
///   persistence.
/// * `nox` and `tvoc` are nullable because the SGP41 sensor warms up
///   in CONDITIONING mode after device boot; samples received in that
///   window have nulls for both. The raw counterparts `noxRaw` and
///   `vocRaw` are populated regardless of conditioning state and are
///   preserved primarily for the dissertation's JSON export.
class Readings extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get sequenceNumber => integer()();
  DateTimeColumn get timestamp => dateTime()();

  RealColumn get pm1 => real()();
  RealColumn get pm25 => real()();
  RealColumn get pm10 => real()();
  RealColumn get co2 => real()();
  RealColumn get temperature => real()();
  RealColumn get humidity => real()();
  RealColumn get pressure => real()();
  RealColumn get pressureChangePaPerSec => real().nullable()();
  RealColumn get nox => real().nullable()();
  RealColumn get tvoc => real().nullable()();

  /// SGP41 raw VOC ticks (uint16 on the wire). Always populated,
  /// even during CONDITIONING. Database-only; surfaced in JSON export.
  IntColumn get vocRaw => integer().nullable()();

  /// SGP41 raw NOx ticks (uint16 on the wire). Always populated,
  /// even during CONDITIONING. Database-only; surfaced in JSON export.
  IntColumn get noxRaw => integer().nullable()();

  TextColumn get sourceFlag => text()();

  TextColumn get stationId => text().nullable()();
  TextColumn get lineId => text().nullable()();

  RealColumn get gpsLat => real().nullable()();
  RealColumn get gpsLng => real().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sequenceNumber, timestamp},
  ];
}

@DriftDatabase(tables: [Readings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Bump this when the schema changes (new column, new table,
  /// nullability change). Drift uses it to drive migrations.
  ///
  /// v1 → v2 (BLE integration, Step 2): added `vocRaw` and `noxRaw`
  /// to preserve the SGP41 raw counts alongside the processed indices.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(readings, readings.vocRaw);
        await m.addColumn(readings, readings.noxRaw);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbFile = File('${dir.path}/commuta.sqlite');
    return NativeDatabase.createInBackground(dbFile);
  });
}