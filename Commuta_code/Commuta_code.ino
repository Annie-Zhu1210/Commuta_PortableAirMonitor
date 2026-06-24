// Commuta - A Portable Air Quality Monitor

// Raw data for the 2nd version PCB

// Microcontroller Adafruit HUZZAH32 (ESP32)
// Sensors: SPS30 (PM), SCD40 (CO2/Tem/Hum), DPS368 (air pressure), SGP41 (VOC/NOx)
// Others: button, red & green bio-colour LED

// I2C: SDA = GPIO23, SCL = GPIO22

#include <Wire.h>
#include <Adafruit_DPS310.h>
#include <SensirionI2cScd4x.h>
#include <SensirionI2cSps30.h>
#include <SensirionI2CSgp41.h>
#include <VOCGasIndexAlgorithm.h>
#include <NOxGasIndexAlgorithm.h>

#include "ble.h"
#include "storage.h"

// ---------- pin map ----------
#define PIN_BUTTON 27
#define PIN_LED_RED 32
#define PIN_LED_GREEN 33
#define PIN_BATTERY_ADC 35  // internal, divider on board, reads Vbat/2

// ---------- sensor objects ----------
SensirionI2cSps30 sps30;
Adafruit_DPS310 dps;
SensirionI2cScd4x scd4x;
SensirionI2CSgp41 sgp41;
VOCGasIndexAlgorithm vocAlgo;
NOxGasIndexAlgorithm noxAlgo;

// ---------- SGP41 timing & state ----------
// Default compensation: 50 %RH, 25 degC, in SGP41 tick format
const uint16_t SGP41_DEFAULT_RH = 0x8000;             // 50  * 65535 / 100
const uint16_t SGP41_DEFAULT_T = 0x6666;              // (25 + 45) * 65535 / 175
const unsigned long SGP41_CONDITIONING_MS = 10000;    // 10 s NOx hotplate warm-up
const unsigned long SGP41_SAMPLE_INTERVAL_MS = 1000;  // 1 Hz cadence for gas index algorithm

unsigned long sgp41StartMs = 0;
unsigned long lastSgp41Ms = 0;
uint16_t srawVoc = 0;
uint16_t srawNox = 0;
int32_t vocIndex = 0;
int32_t noxIndex = 0;

// ---------- Latest sensor readings (used for both serial print and BLE) ----------
// These persist across loop iterations so that, if a single read fails, the
// BLE packet still carries the most recent valid value rather than zero.
float latestPm1 = 0.0f, latestPm25 = 0.0f, latestPm10 = 0.0f;
uint16_t latestCo2 = 0;
float latestT = 25.0f;
float latestRh = 50.0f;
float latestPressure = 0.0f;
bool haveScdReading = false;

// ---------- BLE sample state ----------
uint32_t sampleSequence = 0;  // increments every BLE sample; restored from storage on boot

// ---------- print / sample cadence ----------
unsigned long lastPrint = 0;
const unsigned long PRINT_INTERVAL_MS = 10000;  // also the BLE sample interval

// ---------- helpers ----------
uint16_t humidityToTicks(float rh) {
  if (rh < 0) rh = 0;
  if (rh > 100) rh = 100;
  return (uint16_t)((rh * 65535.0f) / 100.0f);
}
uint16_t temperatureToTicks(float t) {
  if (t < -45) t = -45;
  if (t > 130) t = 130;
  return (uint16_t)(((t + 45.0f) * 65535.0f) / 175.0f);
}

// Rough battery percentage from GPIO35 (internal Vbat/2 divider on the HUZZAH32).
// First-pass linear map only: ESP32 ADC is non-linear near the rails and the LiPo
// discharge curve isn't actually linear either. Improve once we have bench data.
uint8_t readBatteryPercent() {
  int raw = analogRead(PIN_BATTERY_ADC);
  float vbat = (raw / 4095.0f) * 3.3f * 2.0f;
  int pct = (int)((vbat - 3.3f) / (4.2f - 3.3f) * 100.0f);
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  return (uint8_t)pct;
}

void sampleSgp41() {
  bool conditioning = (millis() - sgp41StartMs) < SGP41_CONDITIONING_MS;
  uint16_t err;
  if (conditioning) {
    err = sgp41.executeConditioning(SGP41_DEFAULT_RH, SGP41_DEFAULT_T, srawVoc);
    srawNox = 0;
  } else {
    uint16_t rhT = haveScdReading ? humidityToTicks(latestRh) : SGP41_DEFAULT_RH;
    uint16_t tT = haveScdReading ? temperatureToTicks(latestT) : SGP41_DEFAULT_T;
    err = sgp41.measureRawSignals(rhT, tT, srawVoc, srawNox);
  }
  if (!err) {
    vocIndex = vocAlgo.process((int32_t)srawVoc);
    if (!conditioning) noxIndex = noxAlgo.process((int32_t)srawNox);
  }
}

void setup() {
  Serial.begin(115200);
  while (!Serial) delay(10);
  Serial.println("Commuta - Air Quality Monitor");

  // GPIO. LED stays as-is (continuously green) for now; button is wired but
  // unused — gesture detection (long-press power, double-press status) lands
  // in a future session.
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_LED_RED, OUTPUT);
  pinMode(PIN_LED_GREEN, OUTPUT);
  analogWrite(PIN_LED_RED, 16);
  analogWrite(PIN_LED_GREEN, 0);

  // I2C
  Wire.begin(23, 22);  // SDA=23, SCL=22

  // Storage: mount LittleFS, scan /buf/ for existing samples, and pick up
  // the sample sequence number from the highest-numbered segment on disk.
  if (!commutaStorageBegin()) {
    Serial.println("storage: WARN init failed; buffering disabled");
  } else {
    sampleSequence = commutaStorageNextSequence();
    Serial.printf("storage: resuming at sequence %u\n", (unsigned)sampleSequence);
  }

  // SPS30
  sps30.begin(Wire, 0x69);
  if (sps30.startMeasurement(SPS30_OUTPUT_FORMAT_OUTPUT_FORMAT_FLOAT)) {
    Serial.println("SPS30 not found!");
  } else {
    Serial.println("SPS30 OK");
  }

  // DPS368 - SDO floating on the second PCB -> default address 0x77
  if (!dps.begin_I2C()) {
    Serial.println("DPS368 not found!");
  } else {
    Serial.println("DPS368 OK");
    dps.configurePressure(DPS310_64HZ, DPS310_64SAMPLES);
    dps.configureTemperature(DPS310_64HZ, DPS310_64SAMPLES);
  }

  // SCD40
  scd4x.begin(Wire, 0x62);
  if (scd4x.startPeriodicMeasurement()) {
    Serial.println("SCD40 not found!");
  } else {
    Serial.println("SCD40 OK");
  }

  // SGP41
  sgp41.begin(Wire);
  uint16_t serial[3];
  if (sgp41.getSerialNumber(serial)) {
    Serial.println("SGP41 not found!");
  } else {
    Serial.println("SGP41 OK");
  }

  // BLE: start advertising before the warmup delay so the device is
  // discoverable from the phone right away.
  commutaBleSetup();

  Serial.println("Warming up sensors for 30 seconds...");
  delay(30000);

  // Mark SGP41 conditioning start AFTER the warmup delay.
  sgp41StartMs = millis();
  lastSgp41Ms = millis();

  Serial.println("Starting measurements...");
  analogWrite(PIN_LED_RED, 0);
  analogWrite(PIN_LED_GREEN, 16);
}

void loop() {
  // SGP41 must be sampled at ~1 Hz for the gas index algorithm to track properly.
  if (millis() - lastSgp41Ms >= SGP41_SAMPLE_INTERVAL_MS) {
    lastSgp41Ms = millis();
    sampleSgp41();
  }

  // Service buffered-sync streaming. Runs every loop iteration; cheap when
  // no sync is active. Sends at most one BLE notification per call so the
  // main loop stays responsive.
  commutaBleServiceSync();

  // Print sensors and notify BLE every PRINT_INTERVAL_MS.
  if (millis() - lastPrint < PRINT_INTERVAL_MS) return;
  lastPrint = millis();
  Serial.println("-----------------------------");

  // --- SPS30 ---
  float pm1, pm25, pm4, pm10;
  float nc05, nc1, nc25, nc4, nc10;
  float tps;
  if (sps30.readMeasurementValuesFloat(pm1, pm25, pm4, pm10,
                                       nc05, nc1, nc25, nc4, nc10, tps)) {
    Serial.println("SPS30: No reading");
  } else {
    latestPm1 = pm1;
    latestPm25 = pm25;
    latestPm10 = pm10;
    Serial.print("PM1.0: "); Serial.print(pm1); Serial.println(" ug/m3");
    Serial.print("PM2.5: "); Serial.print(pm25); Serial.println(" ug/m3");
    Serial.print("PM4.0: "); Serial.print(pm4); Serial.println(" ug/m3");
    Serial.print("PM10:  "); Serial.print(pm10); Serial.println(" ug/m3");
  }

  // --- SCD40 ---
  uint16_t co2 = 0;
  float t = 0.0f, rh = 0.0f;
  bool ready = false;
  scd4x.getDataReadyStatus(ready);
  if (ready) {
    scd4x.readMeasurement(co2, t, rh);
    latestCo2 = co2;
    latestT = t;
    latestRh = rh;
    haveScdReading = true;
    Serial.print("CO2:  "); Serial.print(co2); Serial.println(" ppm");
    Serial.print("Temp: "); Serial.print(t); Serial.println(" C");
    Serial.print("Hum:  "); Serial.print(rh); Serial.println(" %");
  } else {
    Serial.println("SCD40: No reading yet");
  }

  // --- DPS368 ---
  Adafruit_Sensor *dps_pressure = dps.getPressureSensor();
  sensors_event_t pe;
  if (dps.pressureAvailable()) {
    dps_pressure->getEvent(&pe);
    latestPressure = pe.pressure;
    Serial.print("Pressure: "); Serial.print(pe.pressure); Serial.println(" hPa");
  } else {
    Serial.println("DPS368: No reading yet");
  }

  // --- SGP41 ---
  bool conditioning = (millis() - sgp41StartMs) < SGP41_CONDITIONING_MS;
  Serial.print("SRAW VOC: "); Serial.println(srawVoc);
  Serial.print("VOC Idx:  "); Serial.println(vocIndex);
  if (conditioning) {
    Serial.println("SRAW NOx: (conditioning)");
    Serial.println("NOx Idx:  (conditioning)");
  } else {
    Serial.print("SRAW NOx: "); Serial.println(srawNox);
    Serial.print("NOx Idx:  "); Serial.println(noxIndex);
  }

  // --- Build the sample, persist it, and notify BLE ---
  uint8_t batteryPct = readBatteryPercent();

  CommutaSample sample = {};
  sample.sequence = sampleSequence++;
  sample.pm1 = latestPm1;
  sample.pm25 = latestPm25;
  sample.pm10 = latestPm10;
  sample.co2 = latestCo2;
  sample.temperature = latestT;
  sample.humidity = latestRh;
  sample.pressure = latestPressure;
  sample.sraw_voc = srawVoc;
  sample.sraw_nox = srawNox;
  sample.voc_index = (int16_t)vocIndex;
  sample.nox_index = (int16_t)noxIndex;
  sample.flags = conditioning ? COMMUTA_FLAG_CONDITIONING : 0;
  sample.battery_pct = batteryPct;

  // Persist to flash first, then notify the Live characteristic.
  commutaStorageAppend(sample);
  commutaBleNotifyLive(sample);

  // --- Update Status characteristic ---
  uint32_t oldestSeq, newestSeq, bufferedCount;
  commutaStorageGetRange(oldestSeq, newestSeq, bufferedCount);

  CommutaStatus status = {};
  status.uptime_seconds = millis() / 1000;
  status.total_samples = sampleSequence;
  status.oldest_buffered_seq = oldestSeq;
  status.newest_buffered_seq = newestSeq;
  status.buffered_count = bufferedCount;
  status.battery_pct = batteryPct;
  status.flags = sample.flags & COMMUTA_FLAG_CONDITIONING;
  commutaBleUpdateStatus(status);

  Serial.print("Bat:  "); Serial.print(batteryPct);
  Serial.print(" %  Buf: "); Serial.print(bufferedCount);
  Serial.print("  BLE: "); Serial.println(commutaBleIsConnected() ? "connected" : "advertising");
}