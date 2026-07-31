import 'dart:typed_data';

import '../../services/device_connection.dart';

/// Immutable value type mirroring the on-the-wire `CommutaSample`
/// struct defined in the device firmware's `ble.h`.
///
/// Kept deliberately separate from `AirQualityReading` — this class
/// is a faithful representation of the packet bytes with no domain
/// interpretation. `BLEManager` combines it with the previous-pressure
/// history and a wall-clock timestamp to build the domain-layer
/// reading. Step 6's buffered sync parses identical 50-byte payloads
/// inside data frames and goes through the same intermediate.
///
/// Wire-format history:
///   * v1 (40 bytes): original, unversioned; firmware-computed
///     `battery_pct` byte at the tail; no `struct_version`, no
///     `boot_epoch`, no `dps368_temp_c`.
///   * v2 (46 bytes): added `struct_version` and `boot_epoch`;
///     `battery_pct` replaced by raw `vbat_mv`.
///   * v3 (50 bytes, CURRENT): added `dps368_temp_c`. SCD40
///     `temperature` retained — it still feeds SGP41 T/RH
///     compensation and is used as the ambient reading in the app;
///     `dps368_temp_c` is captured for export only (see
///     `AirQualityReading.dps368TempC`).
class LivePacket {
  const LivePacket({
    required this.structVersion,
    required this.bootEpoch,
    required this.sequence,
    required this.pm1,
    required this.pm25,
    required this.pm10,
    required this.co2,
    required this.temperature,
    required this.humidity,
    required this.pressure,
    required this.dps368TempC,
    required this.srawVoc,
    required this.srawNox,
    required this.vocIndex,
    required this.noxIndex,
    required this.vbatMv,
    required this.flags,
  });

  /// Format version stamped by the firmware, `== 3` for records this
  /// build understands. Preserved here so a future migration to v4+
  /// can validate at parse time; currently only diagnostic.
  final int structVersion;

  /// Per-install random ID generated once by the firmware on first
  /// boot and persisted to NVS. Regenerated only on a full flash
  /// erase (which wipes NVS). Combined with [sequence] this is the
  /// stable identity of a sample across reboots and re-syncs.
  final int bootEpoch;

  final int sequence;
  final double pm1;
  final double pm25;
  final double pm10;
  final int co2;

  /// SCD40 temperature in °C. The SCD40's NDIR heater causes it to
  /// self-heat and read a degree or two above ambient once the
  /// enclosure warms up. Kept as the ambient reading in the app
  /// (Annie's decision, dissertation-time), while
  /// [dps368TempC] — from the DPS368, which has no internal heater
  /// — is captured for export as a methodology reference.
  final double temperature;

  final double humidity;
  final double pressure;

  /// DPS368 ambient temperature in °C. No self-heating, so this is
  /// the closer-to-true ambient reading. Not surfaced in the UI in
  /// v3; persisted so the exported CSV (`DPS_tem` column) allows an
  /// SCD40-vs-DPS368 comparison in the methodology chapter.
  final double dps368TempC;

  final int srawVoc;
  final int srawNox;
  final int vocIndex;
  final int noxIndex;

  /// Raw battery cell voltage in millivolts, sampled via the ESP32's
  /// ADC + resistor divider. Used for app-side state-of-charge
  /// computation (Phase 4b). Note this is loaded voltage — the value
  /// under normal operation includes the sensor+radio draw sag, so
  /// a fully-charged 4.2 V cell typically reads ~3.9 V here.
  final int vbatMv;

  final int flags;

  /// True when the SGP41 NOx pixel is still warming up. During this
  /// window `vocIndex` and `noxIndex` are not meaningful and are
  /// nulled at the domain layer; the raw ticks remain populated.
  bool get conditioning => (flags & BlePacketParser.flagConditioning) != 0;
}

/// Base type for the two frame formats the device notifies on the
/// Buffered characteristic during a catch-up sync. Sealed so
/// `BLEManager`'s switch is exhaustive.
sealed class BufferedFrame {
  const BufferedFrame();
}

/// A data frame `[0x01, N × CommutaSample]` carrying up to
/// [BlePacketParser.maxBufferedRecordsPerFrame] records back-to-back.
/// Each record has the same 50-byte layout as a Live packet.
class BufferedDataFrame extends BufferedFrame {
  const BufferedDataFrame(this.records);
  final List<LivePacket> records;
}

/// End-of-stream frame `[0x02, first_sent:u32LE, last_sent:u32LE,
/// sent_count:u32LE]` closing a sync. All three fields are zero when
/// the device had nothing to send for the requested range.
class BufferedEosFrame extends BufferedFrame {
  const BufferedEosFrame({
    required this.firstSentSeq,
    required this.lastSentSeq,
    required this.sentCount,
  });

  final int firstSentSeq;
  final int lastSentSeq;
  final int sentCount;
}

/// Byte-level parser for the three notification packet formats emitted
/// by the Commuta firmware: 50-byte Live samples (v3), 24-byte Status
/// snapshots, and Buffered characteristic frames (data or EOS).
///
/// All structs are `__attribute__((packed))` on the device side (no
/// alignment padding) and encoded little-endian. ESP32 and modern
/// phones are both little-endian, so no byte-swapping is needed at
/// either end. See `firmware/ble.h` for the authoritative wire format.
///
/// The parser is a pure static utility — no clock reads, no
/// side-effects — so every parse method is trivially unit-testable
/// against captured byte fixtures.
class BlePacketParser {
  BlePacketParser._();

  // ── Wire-format constants (v3) ─────────────────────────────────────────

  /// Format version this build understands. Matches
  /// `COMMUTA_STRUCT_VERSION` in the firmware's `ble.h`.
  static const int structVersionV3 = 3;

  static const int liveLength = 50;
  static const int statusLength = 24;

  static const int flagConditioning = 1 << 0; // COMMUTA_FLAG_CONDITIONING
  static const int flagShuttingDown = 1 << 1; // COMMUTA_FLAG_SHUTTING_DOWN

  // ── Buffered sync framing constants ────────────────────────────────────

  /// First byte of a Buffered data frame. Matches the sync-request
  /// preamble the phone writes to the same characteristic.
  static const int bufferedDataFrameType = 0x01;

  /// First byte of a Buffered end-of-stream frame.
  static const int bufferedEosFrameType = 0x02;

  /// Each record inside a data frame has the same layout as a Live
  /// packet — 50 bytes on v3. Aliased for clarity at buffered call
  /// sites.
  static const int bufferedRecordLength = liveLength;

  /// Firmware guarantees N ≤ 4 records per data frame on v3. At 50
  /// bytes each, a full frame is `1 + 4 × 50 = 201` bytes, which fits
  /// inside the 244-byte ATT payload at MTU 247. This dropped from 6
  /// (v1/v2 at 40/46 bytes) to 4 when the sample struct grew to 50
  /// bytes; MUST track sizeof(CommutaSample).
  static const int maxBufferedRecordsPerFrame = 4;

  /// EOS frame is exactly `1 + 4 + 4 + 4 = 13` bytes.
  static const int bufferedEosLength = 13;

  // ── Parse methods ──────────────────────────────────────────────────────

  /// Parses a 50-byte v3 `CommutaSample`. Returns `null` if the
  /// payload isn't exactly [liveLength] bytes — the caller logs and
  /// skips.
  static LivePacket? parseLivePacket(List<int> bytes) {
    if (bytes.length != liveLength) return null;
    final data = Uint8List.fromList(bytes);
    return _readLivePacket(data.buffer.asByteData(), 0);
  }

  /// Parses a 24-byte `CommutaStatus`, wrapping it as a
  /// [DeviceStatus] with the supplied [receivedAt] timestamp so this
  /// method stays deterministic (no clock read inside the parser).
  /// Returns `null` if the payload isn't exactly [statusLength] bytes.
  ///
  /// The Status packet layout is unchanged in v3 — it still carries
  /// a firmware-computed `battery_pct` at offset 20. The app-side
  /// SOC work in Phase 4b will replace how the UI consumes that
  /// (and start reading `vbat_mv` from Live samples instead); the
  /// wire-format field remains for backwards-compat and diagnostics.
  static DeviceStatus? parseStatusPacket(List<int> bytes, DateTime receivedAt) {
    if (bytes.length != statusLength) return null;
    final data = Uint8List.fromList(bytes);
    final bd = data.buffer.asByteData();
    final flags = bd.getUint8(21);
    return DeviceStatus(
      uptimeSeconds: bd.getUint32(0, Endian.little),
      totalSamples: bd.getUint32(4, Endian.little),
      oldestBufferedSeq: bd.getUint32(8, Endian.little),
      newestBufferedSeq: bd.getUint32(12, Endian.little),
      bufferedCount: bd.getUint32(16, Endian.little),
      batteryPercent: bd.getUint8(20),
      conditioning: (flags & flagConditioning) != 0,
      shuttingDown: (flags & flagShuttingDown) != 0,
      receivedAt: receivedAt,
    );
  }

  /// Classifies a Buffered-characteristic notification into a
  /// [BufferedDataFrame] or [BufferedEosFrame]. Returns `null` when
  /// the payload is malformed — wrong first byte, wrong overall
  /// length, or a data-frame payload that isn't a whole multiple of
  /// [bufferedRecordLength]. The caller logs and drops the frame.
  static BufferedFrame? classifyBufferedFrame(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final frameType = bytes[0];

    if (frameType == bufferedDataFrameType) {
      final payloadLen = bytes.length - 1;
      if (payloadLen == 0) return null;
      if (payloadLen % bufferedRecordLength != 0) return null;
      final n = payloadLen ~/ bufferedRecordLength;
      if (n > maxBufferedRecordsPerFrame) return null;

      final data = Uint8List.fromList(bytes);
      final bd = data.buffer.asByteData();
      final records = List<LivePacket>.generate(
        n,
        (i) => _readLivePacket(bd, 1 + i * bufferedRecordLength),
        growable: false,
      );
      return BufferedDataFrame(records);
    }

    if (frameType == bufferedEosFrameType) {
      if (bytes.length != bufferedEosLength) return null;
      final data = Uint8List.fromList(bytes);
      final bd = data.buffer.asByteData();
      return BufferedEosFrame(
        firstSentSeq: bd.getUint32(1, Endian.little),
        lastSentSeq: bd.getUint32(5, Endian.little),
        sentCount: bd.getUint32(9, Endian.little),
      );
    }

    return null;
  }

  /// Builds the 9-byte sync-request payload the phone writes to the
  /// Buffered characteristic to open a catch-up stream. Format is
  /// `[0x01, start_seq:u32LE, end_seq:u32LE]`. Pass `0xFFFFFFFF` for
  /// [endSeq] to mean "to newest available". Kept here so the wire
  /// format lives in one file.
  static Uint8List encodeSyncRequest(int startSeq, int endSeq) {
    final out = Uint8List(9);
    final bd = out.buffer.asByteData();
    bd.setUint8(0, bufferedDataFrameType);
    bd.setUint32(1, startSeq, Endian.little);
    bd.setUint32(5, endSeq, Endian.little);
    return out;
  }

  // ── Internal ───────────────────────────────────────────────────────────

  /// Reads a v3 [LivePacket] from a [ByteData] view at [offset].
  /// Shared between [parseLivePacket] and [classifyBufferedFrame] so
  /// the 50-byte layout is defined in exactly one place.
  ///
  /// Byte offsets (from `firmware/ble.h`, packed, little-endian):
  ///
  ///   `struct_version`  u8   @ 0
  ///   `boot_epoch`      u32  @ 1
  ///   `sequence`        u32  @ 5
  ///   `pm1`             f32  @ 9
  ///   `pm25`            f32  @ 13
  ///   `pm10`            f32  @ 17
  ///   `co2`             u16  @ 21
  ///   `temperature`     f32  @ 23   (SCD40)
  ///   `humidity`        f32  @ 27
  ///   `pressure`        f32  @ 31
  ///   `dps368_temp_c`   f32  @ 35   (DPS368; no self-heating)
  ///   `sraw_voc`        u16  @ 39
  ///   `sraw_nox`        u16  @ 41
  ///   `voc_index`       i16  @ 43
  ///   `nox_index`       i16  @ 45
  ///   `vbat_mv`         u16  @ 47
  ///   `flags`           u8   @ 49
  ///
  /// Total: 50 bytes.
  static LivePacket _readLivePacket(ByteData bd, int offset) {
    return LivePacket(
      structVersion: bd.getUint8(offset + 0),
      bootEpoch: bd.getUint32(offset + 1, Endian.little),
      sequence: bd.getUint32(offset + 5, Endian.little),
      pm1: bd.getFloat32(offset + 9, Endian.little),
      pm25: bd.getFloat32(offset + 13, Endian.little),
      pm10: bd.getFloat32(offset + 17, Endian.little),
      co2: bd.getUint16(offset + 21, Endian.little),
      temperature: bd.getFloat32(offset + 23, Endian.little),
      humidity: bd.getFloat32(offset + 27, Endian.little),
      pressure: bd.getFloat32(offset + 31, Endian.little),
      dps368TempC: bd.getFloat32(offset + 35, Endian.little),
      srawVoc: bd.getUint16(offset + 39, Endian.little),
      srawNox: bd.getUint16(offset + 41, Endian.little),
      vocIndex: bd.getInt16(offset + 43, Endian.little),
      noxIndex: bd.getInt16(offset + 45, Endian.little),
      vbatMv: bd.getUint16(offset + 47, Endian.little),
      flags: bd.getUint8(offset + 49),
    );
  }
}
