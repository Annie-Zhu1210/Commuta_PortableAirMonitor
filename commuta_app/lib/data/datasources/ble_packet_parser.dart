import 'dart:typed_data';

import '../../services/device_connection.dart';

/// Immutable value type mirroring the on-the-wire `CommutaSample`
/// struct defined in the device firmware's `ble.h`.
///
/// Kept deliberately separate from `AirQualityReading` — this class
/// is a faithful representation of the packet bytes with no domain
/// interpretation. `BLEManager` combines it with the previous-pressure
/// history and a wall-clock timestamp to build the domain-layer
/// reading. Step 6's buffered sync parses identical 40-byte payloads
/// inside data frames and goes through the same intermediate.
class LivePacket {
  const LivePacket({
    required this.sequence,
    required this.pm1,
    required this.pm25,
    required this.pm10,
    required this.co2,
    required this.temperature,
    required this.humidity,
    required this.pressure,
    required this.srawVoc,
    required this.srawNox,
    required this.vocIndex,
    required this.noxIndex,
    required this.flags,
    required this.batteryPercent,
  });

  final int sequence;
  final double pm1;
  final double pm25;
  final double pm10;
  final int co2;
  final double temperature;
  final double humidity;
  final double pressure;
  final int srawVoc;
  final int srawNox;
  final int vocIndex;
  final int noxIndex;
  final int flags;
  final int batteryPercent;

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
/// Each record has the same 40-byte layout as a Live packet.
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
/// by the Commuta firmware: 40-byte Live samples, 24-byte Status
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

  static const int liveLength = 40;
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
  /// packet — 40 bytes. Aliased for clarity at buffered call sites.
  static const int bufferedRecordLength = liveLength;

  /// Firmware guarantees N ≤ 6 records per data frame, so a full
  /// frame is `1 + 6 × 40 = 241` bytes, comfortably under MTU 247.
  static const int maxBufferedRecordsPerFrame = 6;

  /// EOS frame is exactly `1 + 4 + 4 + 4 = 13` bytes.
  static const int bufferedEosLength = 13;

  // ── Parse methods ──────────────────────────────────────────────────────

  /// Parses a 40-byte `CommutaSample`. Returns `null` if the payload
  /// isn't exactly [liveLength] bytes — the caller logs and skips.
  static LivePacket? parseLivePacket(List<int> bytes) {
    if (bytes.length != liveLength) return null;
    final data = Uint8List.fromList(bytes);
    return _readLivePacket(data.buffer.asByteData(), 0);
  }

  /// Parses a 24-byte `CommutaStatus`, wrapping it as a
  /// [DeviceStatus] with the supplied [receivedAt] timestamp so this
  /// method stays deterministic (no clock read inside the parser).
  /// Returns `null` if the payload isn't exactly [statusLength] bytes.
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

  /// Reads a [LivePacket] from a [ByteData] view at [offset]. Shared
  /// between [parseLivePacket] and [classifyBufferedFrame] so the
  /// 40-byte layout is defined in exactly one place.
  static LivePacket _readLivePacket(ByteData bd, int offset) {
    return LivePacket(
      sequence: bd.getUint32(offset + 0, Endian.little),
      pm1: bd.getFloat32(offset + 4, Endian.little),
      pm25: bd.getFloat32(offset + 8, Endian.little),
      pm10: bd.getFloat32(offset + 12, Endian.little),
      co2: bd.getUint16(offset + 16, Endian.little),
      temperature: bd.getFloat32(offset + 18, Endian.little),
      humidity: bd.getFloat32(offset + 22, Endian.little),
      pressure: bd.getFloat32(offset + 26, Endian.little),
      srawVoc: bd.getUint16(offset + 30, Endian.little),
      srawNox: bd.getUint16(offset + 32, Endian.little),
      vocIndex: bd.getInt16(offset + 34, Endian.little),
      noxIndex: bd.getInt16(offset + 36, Endian.little),
      flags: bd.getUint8(offset + 38),
      batteryPercent: bd.getUint8(offset + 39),
    );
  }
}
