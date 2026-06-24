// ble.cpp - BLE GATT layer implementation for Commuta
//
// Uses NimBLE-Arduino (h2zero) 2.x. Install via Library Manager.

#include "ble.h"
#include "secrets.h"
#include "storage.h"  // CommutaSyncState and the sync iterator API

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <esp_mac.h>
#include <freertos/FreeRTOS.h>
#include <string.h>

static NimBLEServer* g_server = nullptr;
static NimBLECharacteristic* g_charLive = nullptr;
static NimBLECharacteristic* g_charBuf = nullptr;
static NimBLECharacteristic* g_charStatus = nullptr;
static bool g_connected = false;

// ---------- Sync state ----------
// The write callback runs on the NimBLE task; the streaming runs on the
// main loop task. ESP32 is dual-core with weak inter-core ordering, so we
// guard the pending-request fields with a FreeRTOS critical section.
static portMUX_TYPE g_syncMux = portMUX_INITIALIZER_UNLOCKED;
static bool g_syncRequested = false;      // protected by g_syncMux
static uint32_t g_pendingStartSeq = 0;    // protected by g_syncMux
static uint32_t g_pendingEndSeq = 0;      // protected by g_syncMux

// These are touched only by the main loop, so no synchronisation is needed.
static bool g_syncActive = false;
static CommutaSyncState g_syncState;

// ---------- Server connection callbacks ----------
class CommutaServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {
    g_connected = true;
    Serial.printf("BLE: central connected (handle %u)\n", info.getConnHandle());
  }
  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& info, int reason) override {
    // Don't touch sync state here — main loop sees !g_connected and cleans
    // up safely on its own task, avoiding a race with the file handle.
    g_connected = false;
    Serial.printf("BLE: central disconnected (reason 0x%02x)\n", reason);
  }
  void onMTUChange(uint16_t mtu, NimBLEConnInfo& info) override {
    Serial.printf("BLE: MTU negotiated to %u bytes\n", mtu);
  }
};

// ---------- Write handler for the Buffered characteristic ----------
class CommutaBufferedCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo& info) override {
    NimBLEAttValue val = chr->getValue();
    size_t len = val.length();
    const uint8_t* data = val.data();

    if (len != COMMUTA_SYNC_REQUEST_LEN) {
      Serial.printf("BLE: sync request wrong length (%u, expected %u)\n",
                    (unsigned)len, (unsigned)COMMUTA_SYNC_REQUEST_LEN);
      return;
    }
    uint8_t cmd = data[0];
    if (cmd != COMMUTA_SYNC_CMD_REQUEST) {
      Serial.printf("BLE: unknown sync command 0x%02x\n", cmd);
      return;
    }

    uint32_t startSeq, endSeq;
    memcpy(&startSeq, data + 1, 4);
    memcpy(&endSeq, data + 5, 4);

    Serial.printf("BLE: sync requested [%u..", (unsigned)startSeq);
    if (endSeq == COMMUTA_SYNC_END_SEQ_NEWEST) {
      Serial.println("newest]");
    } else {
      Serial.printf("%u]\n", (unsigned)endSeq);
    }

    // Hand off to the main loop. If a sync is already active, the main
    // loop will see this pending request after the current one completes.
    portENTER_CRITICAL(&g_syncMux);
    g_pendingStartSeq = startSeq;
    g_pendingEndSeq = endSeq;
    g_syncRequested = true;
    portEXIT_CRITICAL(&g_syncMux);
  }
};

// ---------- Setup ----------
void commutaBleSetup() {
  // Build a device name like "Commuta-A4F2" using the last 2 bytes of the BT MAC.
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_BT);
  char name[20];
  snprintf(name, sizeof(name), "%s%02X%02X",
           COMMUTA_BLE_NAME_PREFIX, mac[4], mac[5]);

  NimBLEDevice::init(name);
  NimBLEDevice::setPower(3);  // ~+3 dBm
  NimBLEDevice::setMTU(247);

  g_server = NimBLEDevice::createServer();
  g_server->setCallbacks(new CommutaServerCallbacks());
  g_server->advertiseOnDisconnect(true);

  NimBLEService* svc = g_server->createService(COMMUTA_SERVICE_UUID);

  // Live characteristic: phone subscribes; we notify every sample.
  g_charLive = svc->createCharacteristic(
    COMMUTA_CHAR_LIVE_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  // Buffered characteristic: phone writes a sync request; we notify chunks back.
  g_charBuf = svc->createCharacteristic(
    COMMUTA_CHAR_BUFFERED_UUID,
    NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY);
  g_charBuf->setCallbacks(new CommutaBufferedCallbacks());

  // Status characteristic: small, readable, notified on each sample.
  g_charStatus = svc->createCharacteristic(
    COMMUTA_CHAR_STATUS_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);

  svc->start();

  // Service UUID in adv packet, name in scan response.
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
  if (g_connected) g_charLive->notify();
}

void commutaBleUpdateStatus(const CommutaStatus& status) {
  if (!g_charStatus) return;
  g_charStatus->setValue((const uint8_t*)&status, sizeof(status));
  if (g_connected) g_charStatus->notify();
}

bool commutaBleIsConnected() { return g_connected; }

// ---------- Sync streaming ----------
// Data and EOS frames are sent as one-off notifications without touching
// the characteristic's stored value, since the Buffered characteristic is
// not READ-able and exists purely as a streaming channel.

static void sendDataFrame(const CommutaSample* records, size_t count) {
  if (!g_charBuf || !g_connected || count == 0) return;
  uint8_t buf[1 + COMMUTA_SYNC_RECORDS_PER_FRAME * sizeof(CommutaSample)];
  buf[0] = COMMUTA_SYNC_FRAME_DATA;
  memcpy(buf + 1, records, count * sizeof(CommutaSample));
  g_charBuf->notify(buf, 1 + count * sizeof(CommutaSample));
}

static void sendEndOfStream(uint32_t firstSeq, uint32_t lastSeq, uint32_t sentCount) {
  if (!g_charBuf || !g_connected) return;
  uint8_t buf[1 + 12];
  buf[0] = COMMUTA_SYNC_FRAME_EOS;
  memcpy(buf + 1, &firstSeq, 4);
  memcpy(buf + 5, &lastSeq, 4);
  memcpy(buf + 9, &sentCount, 4);
  g_charBuf->notify(buf, sizeof(buf));
  Serial.printf("BLE: sync EOS first=%u last=%u count=%u\n",
                (unsigned)firstSeq, (unsigned)lastSeq, (unsigned)sentCount);
}

void commutaBleServiceSync() {
  // Disconnect cleanup. Runs on the main loop so it's safe to touch the
  // file handle inside g_syncState here.
  if (!g_connected) {
    if (g_syncActive) {
      commutaSyncEnd(g_syncState);
      g_syncActive = false;
    }
    // Also clear any pending request that arrived just before the disconnect.
    portENTER_CRITICAL(&g_syncMux);
    g_syncRequested = false;
    portEXIT_CRITICAL(&g_syncMux);
    return;
  }

  // Snapshot pending-request state under the mutex. Only consume the
  // request if we're going to act on it now; otherwise leave it set so
  // we pick it up after the current sync finishes.
  bool requested = false;
  uint32_t startSeq = 0, endSeq = 0;
  portENTER_CRITICAL(&g_syncMux);
  if (g_syncRequested && !g_syncActive) {
    requested = true;
    startSeq = g_pendingStartSeq;
    endSeq = g_pendingEndSeq;
    g_syncRequested = false;
  }
  portEXIT_CRITICAL(&g_syncMux);

  // Start a new sync.
  if (requested) {
    bool ok = commutaSyncBegin(g_syncState, startSeq, endSeq);
    if (!ok) {
      // Nothing to send; immediately end with 0 records.
      sendEndOfStream(0, 0, 0);
      return;
    }
    g_syncActive = true;
    Serial.println("BLE: sync started");
    return;  // Next call will pull the first chunk
  }

  // Service an active stream.
  if (g_syncActive) {
    if (g_syncState.active) {
      // Pull and send one chunk.
      CommutaSample chunk[COMMUTA_SYNC_RECORDS_PER_FRAME];
      size_t n = commutaSyncReadChunk(g_syncState, chunk,
                                      COMMUTA_SYNC_RECORDS_PER_FRAME);
      if (n > 0) sendDataFrame(chunk, n);
      // If the iterator just finished, EOS goes on the next call.
    } else {
      // Iterator done — send EOS and tear down.
      sendEndOfStream(g_syncState.firstSentSeq,
                      g_syncState.lastSentSeq,
                      g_syncState.sentCount);
      commutaSyncEnd(g_syncState);
      g_syncActive = false;
    }
  }
}