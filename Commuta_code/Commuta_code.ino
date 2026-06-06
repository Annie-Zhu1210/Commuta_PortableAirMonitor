#include <Wire.h>
#include <Adafruit_DPS310.h>
#include <SensirionI2cScd4x.h>
#include <SensirionI2cSps30.h>

// SPS30
SensirionI2cSps30 sps30;

// DPS310
Adafruit_DPS310 dps;

// SCD40
SensirionI2cScd4x scd4x;

void setup() {
  Serial.begin(115200);
  while (!Serial) delay(10);
  Serial.println("Air Quality Monitor - Test");

  // Start I2C
  Wire.begin(23, 22);  // SDA, SCL

  // Init SPS30
  sps30.begin(Wire, 0x69);
  int16_t sps_error = sps30.startMeasurement(SPS30_OUTPUT_FORMAT_OUTPUT_FORMAT_FLOAT);
  if (sps_error) {
    Serial.println("SPS30 not found!");
  } else {
    Serial.println("SPS30 OK");
  }

  // Init DPS310
  if (!dps.begin_I2C(0x76)) {
    Serial.println("DPS368 not found!");
  } else {
    Serial.println("DPS368 OK");
    dps.configurePressure(DPS310_64HZ, DPS310_64SAMPLES);
    dps.configureTemperature(DPS310_64HZ, DPS310_64SAMPLES);
  }

  // Init SCD40
  scd4x.begin(Wire, 0x62);
  uint16_t scd_error = scd4x.startPeriodicMeasurement();
  if (scd_error) {
    Serial.println("SCD40 not found!");
  } else {
    Serial.println("SCD40 OK");
  }

  // Warm up period
  Serial.println("Warming up sensors for 30 seconds...");
  delay(30000);
  Serial.println("Starting measurements...");
}

unsigned long lastPrint = 0;

void loop() {
  if (millis() - lastPrint >= 5000) {
    lastPrint = millis();
    Serial.println("-----------------------------");

    // --- SPS30 ---
    float pm1p0, pm2p5, pm4p0, pm10p0;
    float nc0p5, nc1p0, nc2p5, nc4p0, nc10p0;
    float typicalParticleSize;
    int16_t sps_error = sps30.readMeasurementValuesFloat(
      pm1p0, pm2p5, pm4p0, pm10p0,
      nc0p5, nc1p0, nc2p5, nc4p0, nc10p0,
      typicalParticleSize);
    if (sps_error) {
      Serial.println("SPS30: No reading");
    } else {
      Serial.print("PM1.0: ");
      Serial.print(pm1p0);
      Serial.println(" ug/m3");
      Serial.print("PM2.5: ");
      Serial.print(pm2p5);
      Serial.println(" ug/m3");
      Serial.print("PM4.0: ");
      Serial.print(pm4p0);
      Serial.println(" ug/m3");
      Serial.print("PM10:  ");
      Serial.print(pm10p0);
      Serial.println(" ug/m3");
    }

    // --- SCD40 ---
    uint16_t co2 = 0;
    float temperature = 0.0f;
    float humidity = 0.0f;
    bool isDataReady = false;
    scd4x.getDataReadyStatus(isDataReady);
    if (isDataReady) {
      scd4x.readMeasurement(co2, temperature, humidity);
      Serial.print("CO2:  ");
      Serial.print(co2);
      Serial.println(" ppm");
      Serial.print("Temp: ");
      Serial.print(temperature);
      Serial.println(" C");
      Serial.print("Hum:  ");
      Serial.print(humidity);
      Serial.println(" %");
    } else {
      Serial.println("SCD40: No reading yet");
    }

    // --- DPS310 ---
    Adafruit_Sensor *dps_pressure = dps.getPressureSensor();
    sensors_event_t pressure_event;
    if (dps.pressureAvailable()) {
      dps_pressure->getEvent(&pressure_event);
      Serial.print("Pressure: ");
      Serial.print(pressure_event.pressure);
      Serial.println(" hPa");
    } else {
      Serial.println("DPS310: No reading yet");
    }
  }
}
