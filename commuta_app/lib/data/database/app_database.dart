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
///   reset to 1 on firmware reboot for pre-v3 firmware, so they
///   aren't unique across the database's lifetime. Use `id` for row
///   identity; `sequenceNumber` stays an indexed column for
///   diagnostics and the classification UPSERT key.
/// * `(sequenceNumber, timestamp)` is the unique key used by the
///   pre-v3 UPSERT pattern. The pair is unique in practice even
///   across firmware reboots, because the timestamp will differ.
/// * `(bootEpoch, sequenceNumber)` is a second unique key, added as
///   a UNIQUE INDEX in the schema-v3 migration (Session 1 Decision 1
///   — additive; the two coexist). Enforces v3's stable identity
///   even in edge cases where reconstructed buffered timestamps
///   jitter between duplicate deliveries of the same record. SQLite
///   treats NULL values as never-equal in unique indexes, so legacy
///   pre-v3 rows (`bootEpoch = null`) remain non-conflicting.
/// * `stationId` and `lineId` are nullable — populated only after
///   `StationClassificationService` runs (Phase 5+). Readings without
///   a station are still kept; classification doesn't gate
///   persistence.
/// * `nox` and `tvoc` are nullable because the SGP41 sensor warms up
///   in CONDITIONING mode after device boot; samples received in that
///   window have nulls for both. The raw counterparts `noxRaw` and
///   `vocRaw` are populated regardless of conditioning state and are
///   preserved primarily for the dissertation's JSON export.
/// * `bootEpoch`, `dps368TempC`, `vbatMv` are v3 additions and are
///   all nullable so pre-v3 rows and mock rows without these values
///   can coexist. See [AirQualityReading] for the semantics of each.
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

  /// v3: per-install random ID stamped by firmware, part of the new
  /// unique index `ux_readings_boot_seq` on `(bootEpoch,
  /// sequenceNumber)`. Nullable — legacy pre-v3 rows carry null.
  IntColumn get bootEpoch => integer().nullable()();

  /// v3: DPS368 ambient temperature (no self-heating). Not surfaced
  /// in the UI; exported as the `DPS_tem` column in the production
  /// CSV. Nullable — pre-v3 rows and mock rows leave it null.
  RealColumn get dps368TempC => real().nullable()();

  /// v3: raw battery voltage in mV (uint16 on the wire). Read by
  /// the one-off battery characterisation export; will drive the
  /// app-side SOC calculation in Session 3. Nullable — pre-v3 rows
  /// and mock rows leave it null.
  IntColumn get vbatMv => integer().nullable()();

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

  /// SQL fragment for the additive v3 unique index. Kept as a
  /// constant so `onCreate` (fresh install) and `onUpgrade`
  /// (v2 → v3 migration) use exactly the same DDL. `IF NOT EXISTS`
  /// guards against any re-run of the migration on a partially
  /// upgraded install.
  static const String _createBootSeqIndexSql =
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_readings_boot_seq '
      'ON readings (boot_epoch, sequence_number)';

  /// Bump this when the schema changes (new column, new table,
  /// nullability change, new index).
  ///
  /// v1 → v2 (BLE integration, Step 2): added `vocRaw` and `noxRaw`
  /// to preserve the SGP41 raw counts alongside the processed indices.
  ///
  /// v2 → v3 (Session 1, post-firmware v3): added `bootEpoch`,
  /// `dps368TempC`, `vbatMv` columns, plus a UNIQUE INDEX on
  /// `(bootEpoch, sequenceNumber)` — additive alongside the existing
  /// unique key. Pre-existing rows keep null values in the new
  /// columns; SQLite's NULL-never-equals-NULL rule means the new
  /// index does not conflict with them.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Fresh installs don't run onUpgrade, so the additive v3 index
      // is created here too. Kept identical to the v3 migration
      // statement below.
      await customStatement(_createBootSeqIndexSql);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(readings, readings.vocRaw);
        await m.addColumn(readings, readings.noxRaw);
      }
      if (from < 3) {
        // Three new columns, all nullable. Existing rows land with
        // null values for each, which is exactly the desired state:
        // they're pre-v3 records that never carried this data.
        await m.addColumn(readings, readings.bootEpoch);
        await m.addColumn(readings, readings.dps368TempC);
        await m.addColumn(readings, readings.vbatMv);
        // Additive unique index (Session 1 Decision 1). The pre-v3
        // `(sequenceNumber, timestamp)` unique key from the Table's
        // `uniqueKeys` remains in place. Both are now active; the
        // dedup / UPSERT code still targets the original pair so
        // this session doesn't touch classifyReading /
        // setGpsForReading semantics. The new index catches the one
        // edge case the old key misses: buffered records replayed
        // twice under different live anchors, where reconstructed
        // timestamps jitter but `(bootEpoch, sequenceNumber)` is
        // stable.
        await customStatement(_createBootSeqIndexSql);
      }
    },
  );

  /// Deletes every reading whose `sourceFlag` matches [flag]. Returns
  /// the number of rows removed.
  ///
  /// Used by `AppServices.init` on the one-shot cutover from
  /// [MockManager] to `BLEManager` (Step 7): the first launch after
  /// the cutover clears any lingering `sourceFlag = 'mock'` rows so
  /// the first real buffered sync starts from a truly-empty DB rather
  /// than resuming against the mock's sequence numbers. Gated by the
  /// `mock_readings_cleared_v1` SharedPreferences flag in `init`, so
  /// this DAO method runs at most once per install.
  Future<int> deleteReadingsWhereSourceFlag(String flag) {
    return (delete(readings)..where((t) => t.sourceFlag.equals(flag))).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbFile = File('${dir.path}/commuta.sqlite');
    return NativeDatabase.createInBackground(dbFile);
  });
}