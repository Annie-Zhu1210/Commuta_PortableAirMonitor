// ble.h - BLE GATT layer for Commuta
//
// Defines the on-the-wire packet formats and the public API exposed
// to the main sketch. Implementation lives in ble.cpp.
//
// REQUIRED LIBRARY: "NimBLE-Arduino" by h2zero (install via Library Manager).
// Tested against NimBLE-Arduino 2.x.

#ifndef COMMUTA_BLE_H
#define COMMUTA_BLE_H

#include <stdint.h>

// ---------- Packet layouts ----------
// All structs are __attribute__((packed)) so the in-memory layout matches
// the on-the-wire byte layout exactly. ESP32 is little-endian and modern
// phones are little-endian, so no byte-swapping is needed on either side.

// Record format version stamped into every CommutaSample.struct_version.
// v1 was the original, unversioned 40-byte layout (no boot_epoch; a
// firmware-computed battery_pct instead of raw vbat_mv). v2 was the 46-byte
// layout (struct_version + boot_epoch + raw vbat_mv). v3 is the 50-byte
// layout defined below. Bump this whenever the byte layout changes so a
// reader can tell records apart.
#define COMMUTA_STRUCT_VERSION 3

// 50-byte sample packet (Live characteristic, and Buffered records).
// v3 changes vs v2:
//   - dps368_temp_c added: DPS368 ambient temperature. The SCD40 self-heats
//     (NDIR heater) and its temperature drifts up as the enclosure warms,
//     so we now report the DPS368 temperature (no internal heater) as
//     ambient. SCD40 `temperature` is RETAINED: it still feeds SGP41 T/RH
//     compensation and is kept as methodology metadata.
// v2 changes vs v1:
//   - struct_version byte prepended (record self-describes its format)
//   - boot_epoch added: random per-install ID; app dedupes on (boot_epoch,
//     sequence) so sequence can safely reset after a flash-erase
//   - battery_pct (firmware-computed) replaced by raw vbat_mv; SOC is now
//     derived app-side from the raw voltage (see Phase 4 / OCV table)
typedef struct __attribute__((packed)) {
  uint8_t struct_version;  // == COMMUTA_STRUCT_VERSION for records this firmware writes
  uint32_t boot_epoch;     // random per-install ID; dedup key with sequence
  uint32_t sequence;       // monotonic sample counter, persists across reboots
  float pm1;               // ug/m3
  float pm25;              // ug/m3
  float pm10;              // ug/m3
  uint16_t co2;            // ppm
  float temperature;       // degC (from SCD40; feeds SGP41 comp + metadata, NOT reported ambient)
  float humidity;          // %RH (from SCD40)
  float pressure;          // hPa (from DPS368; also the SCD40 compensation reference)
  float dps368_temp_c;     // degC (from DPS368; reported ambient - no self-heating)
  uint16_t sraw_voc;       // SGP41 raw ticks
  uint16_t sraw_nox;       // SGP41 raw ticks (0 during conditioning)
  int16_t voc_index;       // 1..500
  int16_t nox_index;       // 1..500 (0 during conditioning)
  uint16_t vbat_mv;        // raw battery millivolts (ADC-derived); SOC computed app-side
  uint8_t flags;           // see COMMUTA_FLAG_* below
} CommutaSample;

// 24-byte status packet (Status characteristic).
// Expanded from 12 bytes to expose buffer range so the phone can decide
// what to sync without polling individual records.
typedef struct __attribute__((packed)) {
  uint32_t uptime_seconds;
  uint32_t total_samples;
  uint32_t oldest_buffered_seq;
  uint32_t newest_buffered_seq;
  uint32_t buffered_count;
  uint8_t battery_pct;
  uint8_t flags;
  uint8_t reserved[2];  // padding to 24 bytes; reserved for future use
} CommutaStatus;

// Flag bits used in both sample.flags and status.flags.
#define COMMUTA_FLAG_CONDITIONING  (1 << 0)  // SGP41 NOx pixel warming up
// Status-only flag. Sent in the very last Status notification before the
// device enters deep sleep. The phone treats the range fields in this
// Status as final and shows the unsynced count to the user.
#define COMMUTA_FLAG_SHUTTING_DOWN (1 << 1)

// ---------- Sync protocol ----------
// Wire format for the Buffered characteristic:
//
// Phone -> Device (write, 9 bytes):
//   byte 0:    command (0x01 = sync request)
//   bytes 1-4: start_seq (uint32 LE, inclusive)
//   bytes 5-8: end_seq   (uint32 LE, inclusive; 0xFFFFFFFF = "to newest")
//
// Device -> Phone (notify):
//   Data frame (1 + N*50 bytes, N <= 4):
//     byte 0:        type (0x01 = data)
//     bytes 1..:     N consecutive CommutaSample records
//
//   End-of-stream frame (13 bytes):
//     byte 0:        type (0x02 = end-of-stream)
//     bytes 1-4:     first_seq_sent (uint32 LE; 0 if none sent)
//     bytes 5-8:     last_seq_sent  (uint32 LE; 0 if none sent)
//     bytes 9-12:    sent_count     (uint32 LE)
//
// Zero or more data frames are sent, followed by exactly one EOS frame.
// If sent_count is 0, no data was available; first/last are also 0.
// The device clamps the requested range to what is actually on disk,
// so the phone reconciles by comparing first/last_sent against what it
// asked for.

#define COMMUTA_SYNC_CMD_REQUEST 0x01      // phone -> device
#define COMMUTA_SYNC_FRAME_DATA  0x01      // device -> phone
#define COMMUTA_SYNC_FRAME_EOS   0x02      // device -> phone

#define COMMUTA_SYNC_REQUEST_LEN 9
#define COMMUTA_SYNC_END_SEQ_NEWEST 0xFFFFFFFFu

// Max records per data frame. With MTU 247, a notification's ATT payload is
// 244 bytes (ATT_MTU - 3). The frame is 1 type byte + N records. At 50
// bytes/record (v3), 4 records = 201-byte frame fits; 5 records (251 bytes)
// would overflow the 244-byte payload and the notify would be rejected,
// stalling the sync. This MUST track sizeof(CommutaSample): it dropped from
// 5 to 4 when the struct grew 46 -> 50 bytes at v3.
#define COMMUTA_SYNC_RECORDS_PER_FRAME 4

// ---------- Public API ----------

// Call once in setup() after Serial is initialised.
void commutaBleSetup();

// Update the Live characteristic with a fresh sample and notify subscribers.
void commutaBleNotifyLive(const CommutaSample &sample);

// Update the Status characteristic and notify subscribers.
void commutaBleUpdateStatus(const CommutaStatus &status);

// True if at least one central is currently connected.
bool commutaBleIsConnected();

// True if a buffered-sync stream is mid-flight (used by the shutdown
// sequence to decide whether to send one more frame before sleeping).
bool commutaBleIsSyncActive();

// Drive the buffered-sync state machine. Call from the main loop on every
// iteration. Cheap when no sync is pending; sends at most one notification
// per call so the main loop stays responsive.
void commutaBleServiceSync();

#endif  // COMMUTA_BLE_H