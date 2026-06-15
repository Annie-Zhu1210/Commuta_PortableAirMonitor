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
// Both structs are __attribute__((packed)) so the in-memory layout matches
// the on-the-wire byte layout exactly. ESP32 is little-endian and modern
// phones are little-endian, so no byte-swapping is needed on either side.

// 40-byte sample packet (Live characteristic, and future Buffered records).
typedef struct __attribute__((packed)) {
  uint32_t sequence;    // monotonic sample counter since boot
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

// 12-byte status packet (Status characteristic).
typedef struct __attribute__((packed)) {
  uint32_t uptime_seconds;
  uint32_t total_samples;
  uint16_t buffered_samples;  // 0 until LittleFS buffer is wired up
  uint8_t battery_pct;
  uint8_t flags;
} CommutaStatus;

// Flag bits used in both sample.flags and status.flags.
#define COMMUTA_FLAG_CONDITIONING (1 << 0)  // SGP41 NOx pixel warming up
#define COMMUTA_FLAG_BUTTON_EVENT (1 << 1)  // button pressed since previous sample

// ---------- Public API ----------

// Call once in setup() after Serial is initialised.
void commutaBleSetup();

// Update the Live characteristic with a fresh sample and notify subscribers.
// No-op (just updates the read value) if no central is connected.
void commutaBleNotifyLive(const CommutaSample &sample);

// Update the Status characteristic and notify subscribers.
void commutaBleUpdateStatus(const CommutaStatus &status);

// True if at least one central is currently connected.
bool commutaBleIsConnected();

#endif  // COMMUTA_BLE_H