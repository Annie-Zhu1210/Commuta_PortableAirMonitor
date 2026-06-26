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

#include <esp_sleep.h>
#include <driver/rtc_io.h>

#include "ble.h"
#include "storage.h"
#include "button.h"

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

// ---------- Expected I2C devices ----------
// Used by the on-demand health probe (see probeAllSensorsHealthy). Order
// is informational only; the probe checks all of them on every call.
struct SensorInfo {
  uint8_t addr;
  const char* name;
};
static const SensorInfo kSensors[] = {
  { 0x59, "SGP41" },
  { 0x62, "SCD40" },
  { 0x69, "SPS30" },
  { 0x77, "DPS368" },
};
static const size_t kNumSensors = sizeof(kSensors) / sizeof(kSensors[0]);

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

// ---------- LED control via explicit LEDC channels ----------
// Each LED pin gets its OWN PWM channel via ledcAttach(). This avoids the
// auto-channel-assignment behaviour in analogWrite() that caused yellow to
// fail on the bench (only green visible when both pins were PWMed at once).
//
// API note: ledcAttach(pin, freq, res) is the ESP32 Arduino core 3.x form.
// If your installed core is 2.x, this won't compile and we'll swap to the
// older ledcSetup + ledcAttachPin pair.
#define LED_PWM_FREQ 5000
#define LED_PWM_RESOLUTION 8  // 0..255 duty
#define LED_DIM_DUTY 16       // ~6% brightness, dim enough for the Underground

static void ledSetup() {
  ledcAttach(PIN_LED_RED, LED_PWM_FREQ, LED_PWM_RESOLUTION);
  ledcAttach(PIN_LED_GREEN, LED_PWM_FREQ, LED_PWM_RESOLUTION);
  ledcWrite(PIN_LED_RED, 0);
  ledcWrite(PIN_LED_GREEN, 0);
}
static void ledOff() {
  ledcWrite(PIN_LED_RED, 0);
  ledcWrite(PIN_LED_GREEN, 0);
}
static void ledRed() {
  ledcWrite(PIN_LED_RED, LED_DIM_DUTY);
  ledcWrite(PIN_LED_GREEN, 0);
}
static void ledGreen() {
  ledcWrite(PIN_LED_RED, 0);
  ledcWrite(PIN_LED_GREEN, LED_DIM_DUTY);
}
static void ledYellow() {
  // Bi-colour LED has a much brighter green die than red at equal duty.
  // Bench sweep landed on (red=200, green=16) as the duty pair that the
  // eye perceives as yellow. If the LED part is ever swapped, re-run the
  // diagnostic sweep — the ratio is part-specific.
  ledcWrite(PIN_LED_RED, 200);
  ledcWrite(PIN_LED_GREEN, LED_DIM_DUTY);
}

// ---------- I2C bus probe ----------
// Direct address-ACK test. Returns true iff a device at `addr` acknowledged
// its address on the bus. This is more reliable than calling into the
// sensor-specific drivers, which may swallow NACK errors and return 0.
static bool i2cProbe(uint8_t addr) {
  Wire.beginTransmission(addr);
  // endTransmission returns:
  //   0 = success (slave ACKed address)
  //   1 = data too long for buffer
  //   2 = NACK on address transmit (device absent / unreachable)
  //   3 = NACK on data transmit
  //   4 = other error
  return Wire.endTransmission() == 0;
}

// Probes all four expected sensors RIGHT NOW. Returns true iff every one
// of them ACKs. Used both at boot (for accurate serial logging) and from
// the double-press handler (live health check for the LED colour).
static bool probeAllSensorsHealthy() {
  bool allOk = true;
  for (size_t i = 0; i < kNumSensors; i++) {
    bool ok = i2cProbe(kSensors[i].addr);
    if (!ok) {
      Serial.printf("Probe: %s @ 0x%02X NOT present\n",
                    kSensors[i].name, kSensors[i].addr);
      allOk = false;
    } else {
      Serial.printf("Probe: %s @ 0x%02X present\n",
                    kSensors[i].name, kSensors[i].addr);
    }
  }
  return allOk;
}

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

// ---------- Deep-sleep entry helpers ----------
// Configure GPIO27 for wake and enter deep sleep. Never returns.
static void enterDeepSleep() {
  Serial.flush();
  // GPIO27 pull-up needs to survive deep sleep; the regular IO_MUX pull-up
  // does not, so re-enable via the RTC GPIO API.
  rtc_gpio_pullup_en((gpio_num_t)PIN_BUTTON);
  rtc_gpio_pulldown_dis((gpio_num_t)PIN_BUTTON);
  esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_BUTTON, 0);  // wake when LOW
  esp_deep_sleep_start();
  // unreachable
}

// Called from setup() when the wakeup cause is EXT0. Polls GPIO27 until
// either the long-press threshold is reached (returns true and lights the
// red LED) or the user releases early (returns false).
static bool validateWakePress() {
  Serial.println("Wake: validating long-press from sleep");
  uint32_t startMs = millis();
  while (digitalRead(PIN_BUTTON) == LOW) {
    if (millis() - startMs >= COMMUTA_BTN_LONG_PRESS_MS) {
      Serial.println("Wake: long-press confirmed");
      ledRed();
      // Wait for the user to release before we move on, so the running-
      // mode button manager starts in a clean IDLE state.
      while (digitalRead(PIN_BUTTON) == LOW) delay(10);
      delay(COMMUTA_BTN_DEBOUNCE_MS);
      return true;
    }
    delay(5);
  }
  Serial.println("Wake: released before threshold; back to sleep");
  return false;
}

// ---------- Button callbacks ----------
// Threshold crossed: user has held long enough, light red as the "you can
// let go" cue. Runs immediately before the long-press handler.
static void onBtnLongPressThreshold() {
  ledRed();
}

// Double-press: probe all sensors RIGHT NOW and flash twice. Green if every
// expected I2C address ACKs; yellow if any sensor is unreachable. ~600 ms
// total LED time; the brief block in the main loop is well within SGP41's
// tolerance for a missed sample.
static void onBtnDoublePress() {
  bool healthy = probeAllSensorsHealthy();
  Serial.printf("Button: double-press (healthy=%d)\n", (int)healthy);
  for (int i = 0; i < 2; i++) {
    if (healthy) ledGreen();
    else ledYellow();
    delay(150);
    ledOff();
    if (i == 0) delay(150);
  }
}

// Long-press during normal operation: graceful shutdown into deep sleep.
// Never returns (deep sleep ends with esp_deep_sleep_start()).
static void onBtnLongPress() {
  Serial.println("Button: long-press -> shutdown");

  // Per design: finish one more sync frame if mid-stream, then proceed.
  // The phone uses the SHUTTING_DOWN flag (sent below) to finalise its
  // sync state regardless of whether we sent an explicit EOS.
  if (commutaBleIsSyncActive()) {
    Serial.println("Shutdown: sending one more sync frame");
    commutaBleServiceSync();
    delay(50);  // let the radio actually transmit
  }

  // Final Status notification: SHUTTING_DOWN flag + current buffer range
  // so the phone can compute and display the unsynced count.
  uint32_t oldestSeq, newestSeq, bufferedCount;
  commutaStorageGetRange(oldestSeq, newestSeq, bufferedCount);

  CommutaStatus status = {};
  status.uptime_seconds = millis() / 1000;
  status.total_samples = sampleSequence;
  status.oldest_buffered_seq = oldestSeq;
  status.newest_buffered_seq = newestSeq;
  status.buffered_count = bufferedCount;
  status.battery_pct = readBatteryPercent();
  status.flags = COMMUTA_FLAG_SHUTTING_DOWN;
  commutaBleUpdateStatus(status);
  Serial.printf("Shutdown: sent SHUTTING_DOWN status (buf=%u, newest=%u)\n",
                (unsigned)bufferedCount, (unsigned)newestSeq);
  delay(300);  // generous window for the notification to actually leave the radio

  // Clean sensor stop. SPS30 in particular benefits from stopMeasurement
  // (its fan spins down and the laser turns off cleanly).
  Serial.println("Shutdown: stopping sensors");
  sps30.stopMeasurement();
  scd4x.stopPeriodicMeasurement();

  // CRITICAL: wait for button release before sleeping. If we enter deep
  // sleep with GPIO27 still LOW, EXT0 wakes the chip back up immediately.
  Serial.println("Shutdown: waiting for button release");
  while (digitalRead(PIN_BUTTON) == LOW) delay(10);
  delay(COMMUTA_BTN_DEBOUNCE_MS);

  ledOff();
  Serial.println("Shutdown: entering deep sleep");
  enterDeepSleep();
  // unreachable
}

void setup() {
  // -- Earliest possible setup: button pin + LED PWM channels --
  // Done first so the wake-validation gate has working I/O before doing
  // anything else.
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  ledSetup();  // attaches PIN_LED_RED and PIN_LED_GREEN to dedicated LEDC channels

  Serial.begin(115200);
  // NOTE: do NOT add `while (!Serial)` here. On the HUZZAH32 (CP2104
  // hardware UART) `Serial` is always ready, and on any board that uses
  // native USB the loop would hang forever when running on battery
  // without a host attached.
  delay(50);  // tiny grace period for the host serial monitor
  Serial.println();
  Serial.println("Commuta - Air Quality Monitor");

  // -- Wake validation / cold-boot gate --
  // Device is off by default: cold boot (battery insert, USB plug-in,
  // unexpected reset) goes straight to deep sleep. Only an EXT0 wake
  // with a validated long-press proceeds to full boot.
  esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();
  if (cause == ESP_SLEEP_WAKEUP_EXT0) {
    if (!validateWakePress()) {
      enterDeepSleep();
    }
    // Long-press confirmed; red LED stays on through the rest of setup.
  } else {
    Serial.printf("Boot cause %d - device off by default; long-press to wake\n",
                  (int)cause);
    enterDeepSleep();
  }

  // -- Full boot (red LED has been on since validateWakePress) --

  // I2C
  Wire.begin(23, 22);  // SDA=23, SCL=22
  delay(10);           // brief settle before probing

  // Boot-time presence probe. Just for serial logging — the live probe in
  // the double-press handler is what actually drives the LED colour.
  Serial.println("--- Boot-time I2C presence probe ---");
  probeAllSensorsHealthy();
  Serial.println("--- end probe ---");

  // Storage: mount LittleFS, scan /buf/ for existing samples, and pick up
  // the sample sequence number from the highest-numbered segment on disk.
  if (!commutaStorageBegin()) {
    Serial.println("storage: WARN init failed; buffering disabled");
  } else {
    sampleSequence = commutaStorageNextSequence();
    Serial.printf("storage: resuming at sequence %u\n", (unsigned)sampleSequence);
  }

  // Sensor inits. These still happen unconditionally — calling them on an
  // absent sensor is harmless (the I2C NACK is silently ignored by the
  // library), and if the sensor reappears later we want it already in
  // measurement mode. Their return codes are NOT used for health tracking
  // any more; the double-press handler does a live probe instead.
  sps30.begin(Wire, 0x69);
  sps30.startMeasurement(SPS30_OUTPUT_FORMAT_OUTPUT_FORMAT_FLOAT);

  if (dps.begin_I2C()) {
    dps.configurePressure(DPS310_64HZ, DPS310_64SAMPLES);
    dps.configureTemperature(DPS310_64HZ, DPS310_64SAMPLES);
  }

  scd4x.begin(Wire, 0x62);
  scd4x.startPeriodicMeasurement();

  sgp41.begin(Wire);

  // BLE: start advertising before the warmup delay so the device is
  // discoverable from the phone right away.
  commutaBleSetup();

  Serial.println("Warming up sensors for 30 seconds...");
  delay(30000);

  // Mark SGP41 conditioning start AFTER the warmup delay.
  sgp41StartMs = millis();
  lastSgp41Ms = millis();

  // Boot sequence complete: switch from red (booting) to green (ready),
  // then off for discretion on the Underground.
  Serial.println("Starting measurements...");
  ledGreen();
  delay(3000);
  ledOff();

  // -- Button manager: register callbacks for running-mode gestures --
  commutaButtonBegin(PIN_BUTTON);
  commutaButtonOnLongPressThreshold(onBtnLongPressThreshold);
  commutaButtonOnLongPress(onBtnLongPress);
  commutaButtonOnDoublePress(onBtnDoublePress);
}

void loop() {
  // Service button gestures every iteration. Cheap (one digitalRead + a
  // bit of state-machine arithmetic).
  commutaButtonUpdate();

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
    Serial.print("PM1.0: ");
    Serial.print(pm1);
    Serial.println(" ug/m3");
    Serial.print("PM2.5: ");
    Serial.print(pm25);
    Serial.println(" ug/m3");
    Serial.print("PM4.0: ");
    Serial.print(pm4);
    Serial.println(" ug/m3");
    Serial.print("PM10:  ");
    Serial.print(pm10);
    Serial.println(" ug/m3");
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
    Serial.print("CO2:  ");
    Serial.print(co2);
    Serial.println(" ppm");
    Serial.print("Temp: ");
    Serial.print(t);
    Serial.println(" C");
    Serial.print("Hum:  ");
    Serial.print(rh);
    Serial.println(" %");
  } else {
    Serial.println("SCD40: No reading yet");
  }

  // --- DPS368 ---
  Adafruit_Sensor* dps_pressure = dps.getPressureSensor();
  sensors_event_t pe;
  if (dps.pressureAvailable()) {
    dps_pressure->getEvent(&pe);
    latestPressure = pe.pressure;
    Serial.print("Pressure: ");
    Serial.print(pe.pressure);
    Serial.println(" hPa");
  } else {
    Serial.println("DPS368: No reading yet");
  }

  // --- SGP41 ---
  bool conditioning = (millis() - sgp41StartMs) < SGP41_CONDITIONING_MS;
  Serial.print("SRAW VOC: ");
  Serial.println(srawVoc);
  Serial.print("VOC Idx:  ");
  Serial.println(vocIndex);
  if (conditioning) {
    Serial.println("SRAW NOx: (conditioning)");
    Serial.println("NOx Idx:  (conditioning)");
  } else {
    Serial.print("SRAW NOx: ");
    Serial.println(srawNox);
    Serial.print("NOx Idx:  ");
    Serial.println(noxIndex);
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

  Serial.print("Bat:  ");
  Serial.print(batteryPct);
  Serial.print(" %  Buf: ");
  Serial.print(bufferedCount);
  Serial.print("  BLE: ");
  Serial.println(commutaBleIsConnected() ? "connected" : "advertising");
}