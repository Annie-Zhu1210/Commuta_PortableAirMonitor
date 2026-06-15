// ble.cpp - BLE GATT layer implementation for Commuta
//
// Uses NimBLE-Arduino (h2zero) 2.x. Install via Library Manager.

#include "ble.h"
#include "secrets.h"

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <esp_mac.h>

static NimBLEServer* g_server = nullptr;
static NimBLECharacteristic* g_charLive = nullptr;
static NimBLECharacteristic* g_charBuf = nullptr;
static NimBLECharacteristic* g_charStatus = nullptr;
static bool g_connected = false;

// ---------- Server connection callbacks ----------
class CommutaServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {
    g_connected = true;
    Serial.printf("BLE: central connected (handle %u)\n", info.getConnHandle());
  }
  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& info, int reason) override {
    g_connected = false;
    Serial.printf("BLE: central disconnected (reason 0x%02x)\n", reason);
    // Advertising auto-restarts thanks to advertiseOnDisconnect(true) below.
  }
  void onMTUChange(uint16_t mtu, NimBLEConnInfo& info) override {
    Serial.printf("BLE: MTU negotiated to %u bytes\n", mtu);
  }
};

// ---------- Write handler for the Buffered characteristic ----------
// Placeholder: actual buffered-data streaming will be wired up once LittleFS is in.
class CommutaBufferedCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo& info) override {
    Serial.println("BLE: buffered request received (handler not yet implemented)");
    // TODO: parse the request payload and stream stored records back via notify().
  }
};

// ---------- Setup ----------
void commutaBleSetup() {
  // Build a device name like "Commuta-A4F2" using the last 2 bytes of the BT MAC.
  // This makes each unit individually identifiable in the phone's BLE scan list.
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_BT);
  char name[20];
  snprintf(name, sizeof(name), "%s%02X%02X",
           COMMUTA_BLE_NAME_PREFIX, mac[4], mac[5]);

  NimBLEDevice::init(name);
  NimBLEDevice::setPower(3);  // ~+3 dBm; raise to +9 if range proves insufficient
  NimBLEDevice::setMTU(247);  // request larger MTU so 40-byte samples fit one notify

  g_server = NimBLEDevice::createServer();
  g_server->setCallbacks(new CommutaServerCallbacks());
  g_server->advertiseOnDisconnect(true);  // auto-restart advertising after disconnect

  NimBLEService* svc = g_server->createService(COMMUTA_SERVICE_UUID);

  // Live characteristic: phone subscribes; we notify every sample.
  g_charLive = svc->createCharacteristic(
    COMMUTA_CHAR_LIVE_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  // Buffered characteristic: phone writes a request; we notify chunks back.
  g_charBuf = svc->createCharacteristic(
    COMMUTA_CHAR_BUFFERED_UUID,
    NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY);
  g_charBuf->setCallbacks(new CommutaBufferedCallbacks());

  // Status characteristic: small, readable, notified on each sample.
  g_charStatus = svc->createCharacteristic(
    COMMUTA_CHAR_STATUS_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  svc->start();

  // Explicit split: service UUID in adv packet, name in scan response.
  // This avoids the packet-size overflow that was hiding the device name.
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();

  NimBLEAdvertisementData advData;
  advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
  advData.setCompleteServices(NimBLEUUID(COMMUTA_SERVICE_UUID));
  adv->setAdvertisementData(advData);

  NimBLEAdvertisementData scanResp;
  scanResp.setName(name);
  adv->setScanResponseData(scanResp);

  NimBLEDevice::startAdvertising();

  Serial.printf("BLE: advertising as \"%s\"\n", name);
}

// ---------- Public API ----------
void commutaBleNotifyLive(const CommutaSample& sample) {
  if (!g_charLive) return;
  g_charLive->setValue((const uint8_t*)&sample, sizeof(sample));
  if (g_connected) {
    g_charLive->notify();
  }
}

void commutaBleUpdateStatus(const CommutaStatus& status) {
  if (!g_charStatus) return;
  g_charStatus->setValue((const uint8_t*)&status, sizeof(status));
  if (g_connected) {
    g_charStatus->notify();
  }
}

bool commutaBleIsConnected() {
  return g_connected;
}