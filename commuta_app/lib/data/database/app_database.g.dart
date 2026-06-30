// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ReadingsTable extends Readings with TableInfo<$ReadingsTable, Reading> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sequenceNumberMeta = const VerificationMeta(
    'sequenceNumber',
  );
  @override
  late final GeneratedColumn<int> sequenceNumber = GeneratedColumn<int>(
    'sequence_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pm1Meta = const VerificationMeta('pm1');
  @override
  late final GeneratedColumn<double> pm1 = GeneratedColumn<double>(
    'pm1',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pm25Meta = const VerificationMeta('pm25');
  @override
  late final GeneratedColumn<double> pm25 = GeneratedColumn<double>(
    'pm25',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pm10Meta = const VerificationMeta('pm10');
  @override
  late final GeneratedColumn<double> pm10 = GeneratedColumn<double>(
    'pm10',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _co2Meta = const VerificationMeta('co2');
  @override
  late final GeneratedColumn<double> co2 = GeneratedColumn<double>(
    'co2',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _temperatureMeta = const VerificationMeta(
    'temperature',
  );
  @override
  late final GeneratedColumn<double> temperature = GeneratedColumn<double>(
    'temperature',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _humidityMeta = const VerificationMeta(
    'humidity',
  );
  @override
  late final GeneratedColumn<double> humidity = GeneratedColumn<double>(
    'humidity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pressureMeta = const VerificationMeta(
    'pressure',
  );
  @override
  late final GeneratedColumn<double> pressure = GeneratedColumn<double>(
    'pressure',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pressureChangePaPerSecMeta =
      const VerificationMeta('pressureChangePaPerSec');
  @override
  late final GeneratedColumn<double> pressureChangePaPerSec =
      GeneratedColumn<double>(
        'pressure_change_pa_per_sec',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _noxMeta = const VerificationMeta('nox');
  @override
  late final GeneratedColumn<double> nox = GeneratedColumn<double>(
    'nox',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tvocMeta = const VerificationMeta('tvoc');
  @override
  late final GeneratedColumn<double> tvoc = GeneratedColumn<double>(
    'tvoc',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vocRawMeta = const VerificationMeta('vocRaw');
  @override
  late final GeneratedColumn<int> vocRaw = GeneratedColumn<int>(
    'voc_raw',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noxRawMeta = const VerificationMeta('noxRaw');
  @override
  late final GeneratedColumn<int> noxRaw = GeneratedColumn<int>(
    'nox_raw',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceFlagMeta = const VerificationMeta(
    'sourceFlag',
  );
  @override
  late final GeneratedColumn<String> sourceFlag = GeneratedColumn<String>(
    'source_flag',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stationIdMeta = const VerificationMeta(
    'stationId',
  );
  @override
  late final GeneratedColumn<String> stationId = GeneratedColumn<String>(
    'station_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
    'line_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gpsLatMeta = const VerificationMeta('gpsLat');
  @override
  late final GeneratedColumn<double> gpsLat = GeneratedColumn<double>(
    'gps_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gpsLngMeta = const VerificationMeta('gpsLng');
  @override
  late final GeneratedColumn<double> gpsLng = GeneratedColumn<double>(
    'gps_lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sequenceNumber,
    timestamp,
    pm1,
    pm25,
    pm10,
    co2,
    temperature,
    humidity,
    pressure,
    pressureChangePaPerSec,
    nox,
    tvoc,
    vocRaw,
    noxRaw,
    sourceFlag,
    stationId,
    lineId,
    gpsLat,
    gpsLng,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'readings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Reading> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sequence_number')) {
      context.handle(
        _sequenceNumberMeta,
        sequenceNumber.isAcceptableOrUnknown(
          data['sequence_number']!,
          _sequenceNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sequenceNumberMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('pm1')) {
      context.handle(
        _pm1Meta,
        pm1.isAcceptableOrUnknown(data['pm1']!, _pm1Meta),
      );
    } else if (isInserting) {
      context.missing(_pm1Meta);
    }
    if (data.containsKey('pm25')) {
      context.handle(
        _pm25Meta,
        pm25.isAcceptableOrUnknown(data['pm25']!, _pm25Meta),
      );
    } else if (isInserting) {
      context.missing(_pm25Meta);
    }
    if (data.containsKey('pm10')) {
      context.handle(
        _pm10Meta,
        pm10.isAcceptableOrUnknown(data['pm10']!, _pm10Meta),
      );
    } else if (isInserting) {
      context.missing(_pm10Meta);
    }
    if (data.containsKey('co2')) {
      context.handle(
        _co2Meta,
        co2.isAcceptableOrUnknown(data['co2']!, _co2Meta),
      );
    } else if (isInserting) {
      context.missing(_co2Meta);
    }
    if (data.containsKey('temperature')) {
      context.handle(
        _temperatureMeta,
        temperature.isAcceptableOrUnknown(
          data['temperature']!,
          _temperatureMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_temperatureMeta);
    }
    if (data.containsKey('humidity')) {
      context.handle(
        _humidityMeta,
        humidity.isAcceptableOrUnknown(data['humidity']!, _humidityMeta),
      );
    } else if (isInserting) {
      context.missing(_humidityMeta);
    }
    if (data.containsKey('pressure')) {
      context.handle(
        _pressureMeta,
        pressure.isAcceptableOrUnknown(data['pressure']!, _pressureMeta),
      );
    } else if (isInserting) {
      context.missing(_pressureMeta);
    }
    if (data.containsKey('pressure_change_pa_per_sec')) {
      context.handle(
        _pressureChangePaPerSecMeta,
        pressureChangePaPerSec.isAcceptableOrUnknown(
          data['pressure_change_pa_per_sec']!,
          _pressureChangePaPerSecMeta,
        ),
      );
    }
    if (data.containsKey('nox')) {
      context.handle(
        _noxMeta,
        nox.isAcceptableOrUnknown(data['nox']!, _noxMeta),
      );
    }
    if (data.containsKey('tvoc')) {
      context.handle(
        _tvocMeta,
        tvoc.isAcceptableOrUnknown(data['tvoc']!, _tvocMeta),
      );
    }
    if (data.containsKey('voc_raw')) {
      context.handle(
        _vocRawMeta,
        vocRaw.isAcceptableOrUnknown(data['voc_raw']!, _vocRawMeta),
      );
    }
    if (data.containsKey('nox_raw')) {
      context.handle(
        _noxRawMeta,
        noxRaw.isAcceptableOrUnknown(data['nox_raw']!, _noxRawMeta),
      );
    }
    if (data.containsKey('source_flag')) {
      context.handle(
        _sourceFlagMeta,
        sourceFlag.isAcceptableOrUnknown(data['source_flag']!, _sourceFlagMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceFlagMeta);
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    }
    if (data.containsKey('line_id')) {
      context.handle(
        _lineIdMeta,
        lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta),
      );
    }
    if (data.containsKey('gps_lat')) {
      context.handle(
        _gpsLatMeta,
        gpsLat.isAcceptableOrUnknown(data['gps_lat']!, _gpsLatMeta),
      );
    }
    if (data.containsKey('gps_lng')) {
      context.handle(
        _gpsLngMeta,
        gpsLng.isAcceptableOrUnknown(data['gps_lng']!, _gpsLngMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sequenceNumber, timestamp},
  ];
  @override
  Reading map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Reading(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sequenceNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence_number'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      pm1: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pm1'],
      )!,
      pm25: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pm25'],
      )!,
      pm10: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pm10'],
      )!,
      co2: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}co2'],
      )!,
      temperature: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}temperature'],
      )!,
      humidity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}humidity'],
      )!,
      pressure: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pressure'],
      )!,
      pressureChangePaPerSec: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pressure_change_pa_per_sec'],
      ),
      nox: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}nox'],
      ),
      tvoc: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}tvoc'],
      ),
      vocRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}voc_raw'],
      ),
      noxRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}nox_raw'],
      ),
      sourceFlag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_flag'],
      )!,
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}station_id'],
      ),
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      ),
      gpsLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gps_lat'],
      ),
      gpsLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}gps_lng'],
      ),
    );
  }

  @override
  $ReadingsTable createAlias(String alias) {
    return $ReadingsTable(attachedDatabase, alias);
  }
}

class Reading extends DataClass implements Insertable<Reading> {
  final int id;
  final int sequenceNumber;
  final DateTime timestamp;
  final double pm1;
  final double pm25;
  final double pm10;
  final double co2;
  final double temperature;
  final double humidity;
  final double pressure;
  final double? pressureChangePaPerSec;
  final double? nox;
  final double? tvoc;

  /// SGP41 raw VOC ticks (uint16 on the wire). Always populated,
  /// even during CONDITIONING. Database-only; surfaced in JSON export.
  final int? vocRaw;

  /// SGP41 raw NOx ticks (uint16 on the wire). Always populated,
  /// even during CONDITIONING. Database-only; surfaced in JSON export.
  final int? noxRaw;
  final String sourceFlag;
  final String? stationId;
  final String? lineId;
  final double? gpsLat;
  final double? gpsLng;
  const Reading({
    required this.id,
    required this.sequenceNumber,
    required this.timestamp,
    required this.pm1,
    required this.pm25,
    required this.pm10,
    required this.co2,
    required this.temperature,
    required this.humidity,
    required this.pressure,
    this.pressureChangePaPerSec,
    this.nox,
    this.tvoc,
    this.vocRaw,
    this.noxRaw,
    required this.sourceFlag,
    this.stationId,
    this.lineId,
    this.gpsLat,
    this.gpsLng,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sequence_number'] = Variable<int>(sequenceNumber);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['pm1'] = Variable<double>(pm1);
    map['pm25'] = Variable<double>(pm25);
    map['pm10'] = Variable<double>(pm10);
    map['co2'] = Variable<double>(co2);
    map['temperature'] = Variable<double>(temperature);
    map['humidity'] = Variable<double>(humidity);
    map['pressure'] = Variable<double>(pressure);
    if (!nullToAbsent || pressureChangePaPerSec != null) {
      map['pressure_change_pa_per_sec'] = Variable<double>(
        pressureChangePaPerSec,
      );
    }
    if (!nullToAbsent || nox != null) {
      map['nox'] = Variable<double>(nox);
    }
    if (!nullToAbsent || tvoc != null) {
      map['tvoc'] = Variable<double>(tvoc);
    }
    if (!nullToAbsent || vocRaw != null) {
      map['voc_raw'] = Variable<int>(vocRaw);
    }
    if (!nullToAbsent || noxRaw != null) {
      map['nox_raw'] = Variable<int>(noxRaw);
    }
    map['source_flag'] = Variable<String>(sourceFlag);
    if (!nullToAbsent || stationId != null) {
      map['station_id'] = Variable<String>(stationId);
    }
    if (!nullToAbsent || lineId != null) {
      map['line_id'] = Variable<String>(lineId);
    }
    if (!nullToAbsent || gpsLat != null) {
      map['gps_lat'] = Variable<double>(gpsLat);
    }
    if (!nullToAbsent || gpsLng != null) {
      map['gps_lng'] = Variable<double>(gpsLng);
    }
    return map;
  }

  ReadingsCompanion toCompanion(bool nullToAbsent) {
    return ReadingsCompanion(
      id: Value(id),
      sequenceNumber: Value(sequenceNumber),
      timestamp: Value(timestamp),
      pm1: Value(pm1),
      pm25: Value(pm25),
      pm10: Value(pm10),
      co2: Value(co2),
      temperature: Value(temperature),
      humidity: Value(humidity),
      pressure: Value(pressure),
      pressureChangePaPerSec: pressureChangePaPerSec == null && nullToAbsent
          ? const Value.absent()
          : Value(pressureChangePaPerSec),
      nox: nox == null && nullToAbsent ? const Value.absent() : Value(nox),
      tvoc: tvoc == null && nullToAbsent ? const Value.absent() : Value(tvoc),
      vocRaw: vocRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(vocRaw),
      noxRaw: noxRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(noxRaw),
      sourceFlag: Value(sourceFlag),
      stationId: stationId == null && nullToAbsent
          ? const Value.absent()
          : Value(stationId),
      lineId: lineId == null && nullToAbsent
          ? const Value.absent()
          : Value(lineId),
      gpsLat: gpsLat == null && nullToAbsent
          ? const Value.absent()
          : Value(gpsLat),
      gpsLng: gpsLng == null && nullToAbsent
          ? const Value.absent()
          : Value(gpsLng),
    );
  }

  factory Reading.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Reading(
      id: serializer.fromJson<int>(json['id']),
      sequenceNumber: serializer.fromJson<int>(json['sequenceNumber']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      pm1: serializer.fromJson<double>(json['pm1']),
      pm25: serializer.fromJson<double>(json['pm25']),
      pm10: serializer.fromJson<double>(json['pm10']),
      co2: serializer.fromJson<double>(json['co2']),
      temperature: serializer.fromJson<double>(json['temperature']),
      humidity: serializer.fromJson<double>(json['humidity']),
      pressure: serializer.fromJson<double>(json['pressure']),
      pressureChangePaPerSec: serializer.fromJson<double?>(
        json['pressureChangePaPerSec'],
      ),
      nox: serializer.fromJson<double?>(json['nox']),
      tvoc: serializer.fromJson<double?>(json['tvoc']),
      vocRaw: serializer.fromJson<int?>(json['vocRaw']),
      noxRaw: serializer.fromJson<int?>(json['noxRaw']),
      sourceFlag: serializer.fromJson<String>(json['sourceFlag']),
      stationId: serializer.fromJson<String?>(json['stationId']),
      lineId: serializer.fromJson<String?>(json['lineId']),
      gpsLat: serializer.fromJson<double?>(json['gpsLat']),
      gpsLng: serializer.fromJson<double?>(json['gpsLng']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sequenceNumber': serializer.toJson<int>(sequenceNumber),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'pm1': serializer.toJson<double>(pm1),
      'pm25': serializer.toJson<double>(pm25),
      'pm10': serializer.toJson<double>(pm10),
      'co2': serializer.toJson<double>(co2),
      'temperature': serializer.toJson<double>(temperature),
      'humidity': serializer.toJson<double>(humidity),
      'pressure': serializer.toJson<double>(pressure),
      'pressureChangePaPerSec': serializer.toJson<double?>(
        pressureChangePaPerSec,
      ),
      'nox': serializer.toJson<double?>(nox),
      'tvoc': serializer.toJson<double?>(tvoc),
      'vocRaw': serializer.toJson<int?>(vocRaw),
      'noxRaw': serializer.toJson<int?>(noxRaw),
      'sourceFlag': serializer.toJson<String>(sourceFlag),
      'stationId': serializer.toJson<String?>(stationId),
      'lineId': serializer.toJson<String?>(lineId),
      'gpsLat': serializer.toJson<double?>(gpsLat),
      'gpsLng': serializer.toJson<double?>(gpsLng),
    };
  }

  Reading copyWith({
    int? id,
    int? sequenceNumber,
    DateTime? timestamp,
    double? pm1,
    double? pm25,
    double? pm10,
    double? co2,
    double? temperature,
    double? humidity,
    double? pressure,
    Value<double?> pressureChangePaPerSec = const Value.absent(),
    Value<double?> nox = const Value.absent(),
    Value<double?> tvoc = const Value.absent(),
    Value<int?> vocRaw = const Value.absent(),
    Value<int?> noxRaw = const Value.absent(),
    String? sourceFlag,
    Value<String?> stationId = const Value.absent(),
    Value<String?> lineId = const Value.absent(),
    Value<double?> gpsLat = const Value.absent(),
    Value<double?> gpsLng = const Value.absent(),
  }) => Reading(
    id: id ?? this.id,
    sequenceNumber: sequenceNumber ?? this.sequenceNumber,
    timestamp: timestamp ?? this.timestamp,
    pm1: pm1 ?? this.pm1,
    pm25: pm25 ?? this.pm25,
    pm10: pm10 ?? this.pm10,
    co2: co2 ?? this.co2,
    temperature: temperature ?? this.temperature,
    humidity: humidity ?? this.humidity,
    pressure: pressure ?? this.pressure,
    pressureChangePaPerSec: pressureChangePaPerSec.present
        ? pressureChangePaPerSec.value
        : this.pressureChangePaPerSec,
    nox: nox.present ? nox.value : this.nox,
    tvoc: tvoc.present ? tvoc.value : this.tvoc,
    vocRaw: vocRaw.present ? vocRaw.value : this.vocRaw,
    noxRaw: noxRaw.present ? noxRaw.value : this.noxRaw,
    sourceFlag: sourceFlag ?? this.sourceFlag,
    stationId: stationId.present ? stationId.value : this.stationId,
    lineId: lineId.present ? lineId.value : this.lineId,
    gpsLat: gpsLat.present ? gpsLat.value : this.gpsLat,
    gpsLng: gpsLng.present ? gpsLng.value : this.gpsLng,
  );
  Reading copyWithCompanion(ReadingsCompanion data) {
    return Reading(
      id: data.id.present ? data.id.value : this.id,
      sequenceNumber: data.sequenceNumber.present
          ? data.sequenceNumber.value
          : this.sequenceNumber,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      pm1: data.pm1.present ? data.pm1.value : this.pm1,
      pm25: data.pm25.present ? data.pm25.value : this.pm25,
      pm10: data.pm10.present ? data.pm10.value : this.pm10,
      co2: data.co2.present ? data.co2.value : this.co2,
      temperature: data.temperature.present
          ? data.temperature.value
          : this.temperature,
      humidity: data.humidity.present ? data.humidity.value : this.humidity,
      pressure: data.pressure.present ? data.pressure.value : this.pressure,
      pressureChangePaPerSec: data.pressureChangePaPerSec.present
          ? data.pressureChangePaPerSec.value
          : this.pressureChangePaPerSec,
      nox: data.nox.present ? data.nox.value : this.nox,
      tvoc: data.tvoc.present ? data.tvoc.value : this.tvoc,
      vocRaw: data.vocRaw.present ? data.vocRaw.value : this.vocRaw,
      noxRaw: data.noxRaw.present ? data.noxRaw.value : this.noxRaw,
      sourceFlag: data.sourceFlag.present
          ? data.sourceFlag.value
          : this.sourceFlag,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      gpsLat: data.gpsLat.present ? data.gpsLat.value : this.gpsLat,
      gpsLng: data.gpsLng.present ? data.gpsLng.value : this.gpsLng,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Reading(')
          ..write('id: $id, ')
          ..write('sequenceNumber: $sequenceNumber, ')
          ..write('timestamp: $timestamp, ')
          ..write('pm1: $pm1, ')
          ..write('pm25: $pm25, ')
          ..write('pm10: $pm10, ')
          ..write('co2: $co2, ')
          ..write('temperature: $temperature, ')
          ..write('humidity: $humidity, ')
          ..write('pressure: $pressure, ')
          ..write('pressureChangePaPerSec: $pressureChangePaPerSec, ')
          ..write('nox: $nox, ')
          ..write('tvoc: $tvoc, ')
          ..write('vocRaw: $vocRaw, ')
          ..write('noxRaw: $noxRaw, ')
          ..write('sourceFlag: $sourceFlag, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('gpsLat: $gpsLat, ')
          ..write('gpsLng: $gpsLng')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sequenceNumber,
    timestamp,
    pm1,
    pm25,
    pm10,
    co2,
    temperature,
    humidity,
    pressure,
    pressureChangePaPerSec,
    nox,
    tvoc,
    vocRaw,
    noxRaw,
    sourceFlag,
    stationId,
    lineId,
    gpsLat,
    gpsLng,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Reading &&
          other.id == this.id &&
          other.sequenceNumber == this.sequenceNumber &&
          other.timestamp == this.timestamp &&
          other.pm1 == this.pm1 &&
          other.pm25 == this.pm25 &&
          other.pm10 == this.pm10 &&
          other.co2 == this.co2 &&
          other.temperature == this.temperature &&
          other.humidity == this.humidity &&
          other.pressure == this.pressure &&
          other.pressureChangePaPerSec == this.pressureChangePaPerSec &&
          other.nox == this.nox &&
          other.tvoc == this.tvoc &&
          other.vocRaw == this.vocRaw &&
          other.noxRaw == this.noxRaw &&
          other.sourceFlag == this.sourceFlag &&
          other.stationId == this.stationId &&
          other.lineId == this.lineId &&
          other.gpsLat == this.gpsLat &&
          other.gpsLng == this.gpsLng);
}

class ReadingsCompanion extends UpdateCompanion<Reading> {
  final Value<int> id;
  final Value<int> sequenceNumber;
  final Value<DateTime> timestamp;
  final Value<double> pm1;
  final Value<double> pm25;
  final Value<double> pm10;
  final Value<double> co2;
  final Value<double> temperature;
  final Value<double> humidity;
  final Value<double> pressure;
  final Value<double?> pressureChangePaPerSec;
  final Value<double?> nox;
  final Value<double?> tvoc;
  final Value<int?> vocRaw;
  final Value<int?> noxRaw;
  final Value<String> sourceFlag;
  final Value<String?> stationId;
  final Value<String?> lineId;
  final Value<double?> gpsLat;
  final Value<double?> gpsLng;
  const ReadingsCompanion({
    this.id = const Value.absent(),
    this.sequenceNumber = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.pm1 = const Value.absent(),
    this.pm25 = const Value.absent(),
    this.pm10 = const Value.absent(),
    this.co2 = const Value.absent(),
    this.temperature = const Value.absent(),
    this.humidity = const Value.absent(),
    this.pressure = const Value.absent(),
    this.pressureChangePaPerSec = const Value.absent(),
    this.nox = const Value.absent(),
    this.tvoc = const Value.absent(),
    this.vocRaw = const Value.absent(),
    this.noxRaw = const Value.absent(),
    this.sourceFlag = const Value.absent(),
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.gpsLat = const Value.absent(),
    this.gpsLng = const Value.absent(),
  });
  ReadingsCompanion.insert({
    this.id = const Value.absent(),
    required int sequenceNumber,
    required DateTime timestamp,
    required double pm1,
    required double pm25,
    required double pm10,
    required double co2,
    required double temperature,
    required double humidity,
    required double pressure,
    this.pressureChangePaPerSec = const Value.absent(),
    this.nox = const Value.absent(),
    this.tvoc = const Value.absent(),
    this.vocRaw = const Value.absent(),
    this.noxRaw = const Value.absent(),
    required String sourceFlag,
    this.stationId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.gpsLat = const Value.absent(),
    this.gpsLng = const Value.absent(),
  }) : sequenceNumber = Value(sequenceNumber),
       timestamp = Value(timestamp),
       pm1 = Value(pm1),
       pm25 = Value(pm25),
       pm10 = Value(pm10),
       co2 = Value(co2),
       temperature = Value(temperature),
       humidity = Value(humidity),
       pressure = Value(pressure),
       sourceFlag = Value(sourceFlag);
  static Insertable<Reading> custom({
    Expression<int>? id,
    Expression<int>? sequenceNumber,
    Expression<DateTime>? timestamp,
    Expression<double>? pm1,
    Expression<double>? pm25,
    Expression<double>? pm10,
    Expression<double>? co2,
    Expression<double>? temperature,
    Expression<double>? humidity,
    Expression<double>? pressure,
    Expression<double>? pressureChangePaPerSec,
    Expression<double>? nox,
    Expression<double>? tvoc,
    Expression<int>? vocRaw,
    Expression<int>? noxRaw,
    Expression<String>? sourceFlag,
    Expression<String>? stationId,
    Expression<String>? lineId,
    Expression<double>? gpsLat,
    Expression<double>? gpsLng,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sequenceNumber != null) 'sequence_number': sequenceNumber,
      if (timestamp != null) 'timestamp': timestamp,
      if (pm1 != null) 'pm1': pm1,
      if (pm25 != null) 'pm25': pm25,
      if (pm10 != null) 'pm10': pm10,
      if (co2 != null) 'co2': co2,
      if (temperature != null) 'temperature': temperature,
      if (humidity != null) 'humidity': humidity,
      if (pressure != null) 'pressure': pressure,
      if (pressureChangePaPerSec != null)
        'pressure_change_pa_per_sec': pressureChangePaPerSec,
      if (nox != null) 'nox': nox,
      if (tvoc != null) 'tvoc': tvoc,
      if (vocRaw != null) 'voc_raw': vocRaw,
      if (noxRaw != null) 'nox_raw': noxRaw,
      if (sourceFlag != null) 'source_flag': sourceFlag,
      if (stationId != null) 'station_id': stationId,
      if (lineId != null) 'line_id': lineId,
      if (gpsLat != null) 'gps_lat': gpsLat,
      if (gpsLng != null) 'gps_lng': gpsLng,
    });
  }

  ReadingsCompanion copyWith({
    Value<int>? id,
    Value<int>? sequenceNumber,
    Value<DateTime>? timestamp,
    Value<double>? pm1,
    Value<double>? pm25,
    Value<double>? pm10,
    Value<double>? co2,
    Value<double>? temperature,
    Value<double>? humidity,
    Value<double>? pressure,
    Value<double?>? pressureChangePaPerSec,
    Value<double?>? nox,
    Value<double?>? tvoc,
    Value<int?>? vocRaw,
    Value<int?>? noxRaw,
    Value<String>? sourceFlag,
    Value<String?>? stationId,
    Value<String?>? lineId,
    Value<double?>? gpsLat,
    Value<double?>? gpsLng,
  }) {
    return ReadingsCompanion(
      id: id ?? this.id,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      timestamp: timestamp ?? this.timestamp,
      pm1: pm1 ?? this.pm1,
      pm25: pm25 ?? this.pm25,
      pm10: pm10 ?? this.pm10,
      co2: co2 ?? this.co2,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      pressure: pressure ?? this.pressure,
      pressureChangePaPerSec:
          pressureChangePaPerSec ?? this.pressureChangePaPerSec,
      nox: nox ?? this.nox,
      tvoc: tvoc ?? this.tvoc,
      vocRaw: vocRaw ?? this.vocRaw,
      noxRaw: noxRaw ?? this.noxRaw,
      sourceFlag: sourceFlag ?? this.sourceFlag,
      stationId: stationId ?? this.stationId,
      lineId: lineId ?? this.lineId,
      gpsLat: gpsLat ?? this.gpsLat,
      gpsLng: gpsLng ?? this.gpsLng,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sequenceNumber.present) {
      map['sequence_number'] = Variable<int>(sequenceNumber.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (pm1.present) {
      map['pm1'] = Variable<double>(pm1.value);
    }
    if (pm25.present) {
      map['pm25'] = Variable<double>(pm25.value);
    }
    if (pm10.present) {
      map['pm10'] = Variable<double>(pm10.value);
    }
    if (co2.present) {
      map['co2'] = Variable<double>(co2.value);
    }
    if (temperature.present) {
      map['temperature'] = Variable<double>(temperature.value);
    }
    if (humidity.present) {
      map['humidity'] = Variable<double>(humidity.value);
    }
    if (pressure.present) {
      map['pressure'] = Variable<double>(pressure.value);
    }
    if (pressureChangePaPerSec.present) {
      map['pressure_change_pa_per_sec'] = Variable<double>(
        pressureChangePaPerSec.value,
      );
    }
    if (nox.present) {
      map['nox'] = Variable<double>(nox.value);
    }
    if (tvoc.present) {
      map['tvoc'] = Variable<double>(tvoc.value);
    }
    if (vocRaw.present) {
      map['voc_raw'] = Variable<int>(vocRaw.value);
    }
    if (noxRaw.present) {
      map['nox_raw'] = Variable<int>(noxRaw.value);
    }
    if (sourceFlag.present) {
      map['source_flag'] = Variable<String>(sourceFlag.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<String>(stationId.value);
    }
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (gpsLat.present) {
      map['gps_lat'] = Variable<double>(gpsLat.value);
    }
    if (gpsLng.present) {
      map['gps_lng'] = Variable<double>(gpsLng.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingsCompanion(')
          ..write('id: $id, ')
          ..write('sequenceNumber: $sequenceNumber, ')
          ..write('timestamp: $timestamp, ')
          ..write('pm1: $pm1, ')
          ..write('pm25: $pm25, ')
          ..write('pm10: $pm10, ')
          ..write('co2: $co2, ')
          ..write('temperature: $temperature, ')
          ..write('humidity: $humidity, ')
          ..write('pressure: $pressure, ')
          ..write('pressureChangePaPerSec: $pressureChangePaPerSec, ')
          ..write('nox: $nox, ')
          ..write('tvoc: $tvoc, ')
          ..write('vocRaw: $vocRaw, ')
          ..write('noxRaw: $noxRaw, ')
          ..write('sourceFlag: $sourceFlag, ')
          ..write('stationId: $stationId, ')
          ..write('lineId: $lineId, ')
          ..write('gpsLat: $gpsLat, ')
          ..write('gpsLng: $gpsLng')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ReadingsTable readings = $ReadingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [readings];
}

typedef $$ReadingsTableCreateCompanionBuilder =
    ReadingsCompanion Function({
      Value<int> id,
      required int sequenceNumber,
      required DateTime timestamp,
      required double pm1,
      required double pm25,
      required double pm10,
      required double co2,
      required double temperature,
      required double humidity,
      required double pressure,
      Value<double?> pressureChangePaPerSec,
      Value<double?> nox,
      Value<double?> tvoc,
      Value<int?> vocRaw,
      Value<int?> noxRaw,
      required String sourceFlag,
      Value<String?> stationId,
      Value<String?> lineId,
      Value<double?> gpsLat,
      Value<double?> gpsLng,
    });
typedef $$ReadingsTableUpdateCompanionBuilder =
    ReadingsCompanion Function({
      Value<int> id,
      Value<int> sequenceNumber,
      Value<DateTime> timestamp,
      Value<double> pm1,
      Value<double> pm25,
      Value<double> pm10,
      Value<double> co2,
      Value<double> temperature,
      Value<double> humidity,
      Value<double> pressure,
      Value<double?> pressureChangePaPerSec,
      Value<double?> nox,
      Value<double?> tvoc,
      Value<int?> vocRaw,
      Value<int?> noxRaw,
      Value<String> sourceFlag,
      Value<String?> stationId,
      Value<String?> lineId,
      Value<double?> gpsLat,
      Value<double?> gpsLng,
    });

class $$ReadingsTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingsTable> {
  $$ReadingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequenceNumber => $composableBuilder(
    column: $table.sequenceNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pm1 => $composableBuilder(
    column: $table.pm1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pm25 => $composableBuilder(
    column: $table.pm25,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pm10 => $composableBuilder(
    column: $table.pm10,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get co2 => $composableBuilder(
    column: $table.co2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get humidity => $composableBuilder(
    column: $table.humidity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pressure => $composableBuilder(
    column: $table.pressure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pressureChangePaPerSec => $composableBuilder(
    column: $table.pressureChangePaPerSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get nox => $composableBuilder(
    column: $table.nox,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tvoc => $composableBuilder(
    column: $table.tvoc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get vocRaw => $composableBuilder(
    column: $table.vocRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get noxRaw => $composableBuilder(
    column: $table.noxRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceFlag => $composableBuilder(
    column: $table.sourceFlag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gpsLat => $composableBuilder(
    column: $table.gpsLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get gpsLng => $composableBuilder(
    column: $table.gpsLng,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadingsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingsTable> {
  $$ReadingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequenceNumber => $composableBuilder(
    column: $table.sequenceNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pm1 => $composableBuilder(
    column: $table.pm1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pm25 => $composableBuilder(
    column: $table.pm25,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pm10 => $composableBuilder(
    column: $table.pm10,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get co2 => $composableBuilder(
    column: $table.co2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get humidity => $composableBuilder(
    column: $table.humidity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pressure => $composableBuilder(
    column: $table.pressure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pressureChangePaPerSec => $composableBuilder(
    column: $table.pressureChangePaPerSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get nox => $composableBuilder(
    column: $table.nox,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tvoc => $composableBuilder(
    column: $table.tvoc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get vocRaw => $composableBuilder(
    column: $table.vocRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get noxRaw => $composableBuilder(
    column: $table.noxRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceFlag => $composableBuilder(
    column: $table.sourceFlag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gpsLat => $composableBuilder(
    column: $table.gpsLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get gpsLng => $composableBuilder(
    column: $table.gpsLng,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingsTable> {
  $$ReadingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sequenceNumber => $composableBuilder(
    column: $table.sequenceNumber,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<double> get pm1 =>
      $composableBuilder(column: $table.pm1, builder: (column) => column);

  GeneratedColumn<double> get pm25 =>
      $composableBuilder(column: $table.pm25, builder: (column) => column);

  GeneratedColumn<double> get pm10 =>
      $composableBuilder(column: $table.pm10, builder: (column) => column);

  GeneratedColumn<double> get co2 =>
      $composableBuilder(column: $table.co2, builder: (column) => column);

  GeneratedColumn<double> get temperature => $composableBuilder(
    column: $table.temperature,
    builder: (column) => column,
  );

  GeneratedColumn<double> get humidity =>
      $composableBuilder(column: $table.humidity, builder: (column) => column);

  GeneratedColumn<double> get pressure =>
      $composableBuilder(column: $table.pressure, builder: (column) => column);

  GeneratedColumn<double> get pressureChangePaPerSec => $composableBuilder(
    column: $table.pressureChangePaPerSec,
    builder: (column) => column,
  );

  GeneratedColumn<double> get nox =>
      $composableBuilder(column: $table.nox, builder: (column) => column);

  GeneratedColumn<double> get tvoc =>
      $composableBuilder(column: $table.tvoc, builder: (column) => column);

  GeneratedColumn<int> get vocRaw =>
      $composableBuilder(column: $table.vocRaw, builder: (column) => column);

  GeneratedColumn<int> get noxRaw =>
      $composableBuilder(column: $table.noxRaw, builder: (column) => column);

  GeneratedColumn<String> get sourceFlag => $composableBuilder(
    column: $table.sourceFlag,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<double> get gpsLat =>
      $composableBuilder(column: $table.gpsLat, builder: (column) => column);

  GeneratedColumn<double> get gpsLng =>
      $composableBuilder(column: $table.gpsLng, builder: (column) => column);
}

class $$ReadingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingsTable,
          Reading,
          $$ReadingsTableFilterComposer,
          $$ReadingsTableOrderingComposer,
          $$ReadingsTableAnnotationComposer,
          $$ReadingsTableCreateCompanionBuilder,
          $$ReadingsTableUpdateCompanionBuilder,
          (Reading, BaseReferences<_$AppDatabase, $ReadingsTable, Reading>),
          Reading,
          PrefetchHooks Function()
        > {
  $$ReadingsTableTableManager(_$AppDatabase db, $ReadingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sequenceNumber = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<double> pm1 = const Value.absent(),
                Value<double> pm25 = const Value.absent(),
                Value<double> pm10 = const Value.absent(),
                Value<double> co2 = const Value.absent(),
                Value<double> temperature = const Value.absent(),
                Value<double> humidity = const Value.absent(),
                Value<double> pressure = const Value.absent(),
                Value<double?> pressureChangePaPerSec = const Value.absent(),
                Value<double?> nox = const Value.absent(),
                Value<double?> tvoc = const Value.absent(),
                Value<int?> vocRaw = const Value.absent(),
                Value<int?> noxRaw = const Value.absent(),
                Value<String> sourceFlag = const Value.absent(),
                Value<String?> stationId = const Value.absent(),
                Value<String?> lineId = const Value.absent(),
                Value<double?> gpsLat = const Value.absent(),
                Value<double?> gpsLng = const Value.absent(),
              }) => ReadingsCompanion(
                id: id,
                sequenceNumber: sequenceNumber,
                timestamp: timestamp,
                pm1: pm1,
                pm25: pm25,
                pm10: pm10,
                co2: co2,
                temperature: temperature,
                humidity: humidity,
                pressure: pressure,
                pressureChangePaPerSec: pressureChangePaPerSec,
                nox: nox,
                tvoc: tvoc,
                vocRaw: vocRaw,
                noxRaw: noxRaw,
                sourceFlag: sourceFlag,
                stationId: stationId,
                lineId: lineId,
                gpsLat: gpsLat,
                gpsLng: gpsLng,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sequenceNumber,
                required DateTime timestamp,
                required double pm1,
                required double pm25,
                required double pm10,
                required double co2,
                required double temperature,
                required double humidity,
                required double pressure,
                Value<double?> pressureChangePaPerSec = const Value.absent(),
                Value<double?> nox = const Value.absent(),
                Value<double?> tvoc = const Value.absent(),
                Value<int?> vocRaw = const Value.absent(),
                Value<int?> noxRaw = const Value.absent(),
                required String sourceFlag,
                Value<String?> stationId = const Value.absent(),
                Value<String?> lineId = const Value.absent(),
                Value<double?> gpsLat = const Value.absent(),
                Value<double?> gpsLng = const Value.absent(),
              }) => ReadingsCompanion.insert(
                id: id,
                sequenceNumber: sequenceNumber,
                timestamp: timestamp,
                pm1: pm1,
                pm25: pm25,
                pm10: pm10,
                co2: co2,
                temperature: temperature,
                humidity: humidity,
                pressure: pressure,
                pressureChangePaPerSec: pressureChangePaPerSec,
                nox: nox,
                tvoc: tvoc,
                vocRaw: vocRaw,
                noxRaw: noxRaw,
                sourceFlag: sourceFlag,
                stationId: stationId,
                lineId: lineId,
                gpsLat: gpsLat,
                gpsLng: gpsLng,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingsTable,
      Reading,
      $$ReadingsTableFilterComposer,
      $$ReadingsTableOrderingComposer,
      $$ReadingsTableAnnotationComposer,
      $$ReadingsTableCreateCompanionBuilder,
      $$ReadingsTableUpdateCompanionBuilder,
      (Reading, BaseReferences<_$AppDatabase, $ReadingsTable, Reading>),
      Reading,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ReadingsTableTableManager get readings =>
      $$ReadingsTableTableManager(_db, _db.readings);
}
