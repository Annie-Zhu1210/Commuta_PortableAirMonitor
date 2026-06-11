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
/// * `nox` and `tvoc` are nullable today (SGP41 not yet wired). When
///   the sensor lands, bump the schemaVersion and add a migration
///   that backfills any default if needed.
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
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // No migrations yet. When SGP41 lands or new tables arrive,
      // add cases here, e.g.:
      //   if (from < 2) {
      //     await m.addColumn(readings, readings.someNewColumn);
      //   }
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