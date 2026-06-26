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

// 40-byte sample packet (Live characteristic, and Buffered records).
typedef struct __attribute__((packed)) {
  uint32_t sequence;    // monotonic sample counter, persists across reboots
  float pm1;            // ug/m3
  float pm25;           // ug/m3
  float pm10;           // ug/m3
  uint16_t co2;         // ppm
  float temperature;    // degC (from SCD40)
  float humidity;       // %RH (from SCD40)
  float pressure;       // hPa (from DPS368)
  uint16_t sraw_voc;    // SGP41 raw ticks
  uint16_t sraw_nox;    // SGP41 raw ticks (0 during conditioning)
  int16_t voc_index;    // 1..500
  int16_t nox_index;    // 1..500 (0 during conditioning)
  uint8_t flags;        // see COMMUTA_FLAG_* below
  uint8_t battery_pct;  // 0..100
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
//   Data frame (1 + N*40 bytes, N <= 6):
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

// Max records per data frame. With MTU 247, the ATT payload is 244 bytes;
// minus 1 byte type leaves 243 bytes -> 6 records (240 bytes) fits cleanly.
#define COMMUTA_SYNC_RECORDS_PER_FRAME 6

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