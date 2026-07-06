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

// ---------- Pending-frame buffer (back-pressure) ----------
// A frame built by commutaBleServiceSync but not yet accepted by the host
// stack's outgoing-notification queue. This exists because NimBLE's
// notify() returns false when its ATT tx queue is full (which happens
// under the burst load of a buffered sync), and if we don't retry we
// silently drop that frame. Losing a data frame drops records; losing an
// EOS frame is worse — the phone never learns the stream ended, so it
// heartbeat-times-out at 30 s with sync half-done.
//
// The rule this file enforces: no state advances (no iterator read, no
// EOS teardown, no new request accepted) while g_pendingFrameLen > 0.
// The main loop just keeps retrying tryFlushPendingFrame() until notify
// is accepted, then moves on.
//
// Sized to the larger of a full data frame (1 + 6*40 = 241 bytes) and
// an EOS frame (13 bytes). Static storage — no allocation during sync.
static uint8_t g_pendingFrame[1 + COMMUTA_SYNC_RECORDS_PER_FRAME * sizeof(CommutaSample)];
static size_t g_pendingFrameLen = 0;
static bool g_pendingIsEos = false;

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

bool commutaBleIsSyncActive() { return g_syncActive; }

// ---------- Sync streaming ----------
// Data and EOS frames are sent as one-off notifications without touching
// the characteristic's stored value, since the Buffered characteristic is
// not READ-able and exists purely as a streaming channel.

// Try to push whatever's in the pending-frame slot into the host stack's
// outgoing queue. Returns true if there's nothing to send OR the notify
// was accepted (in which case the slot is cleared). Returns false only
// when notify() was refused — the frame stays in the slot for a retry on
// the next serviceSync call.
//
// notify() being refused is not an error: it's normal back-pressure that
// happens during buffered sync's high frame rate. NimBLE's ATT tx queue
// has a small fixed depth; when full, further notifies get rejected until
// the radio has actually transmitted enough queued packets to make room.
static bool tryFlushPendingFrame() {
  if (g_pendingFrameLen == 0) return true;
  if (!g_charBuf || !g_connected) {
    // Peer went away with a frame queued. Drop it silently; the sync
    // state machine's disconnect path will handle everything else.
    g_pendingFrameLen = 0;
    g_pendingIsEos = false;
    return true;
  }
  bool ok = g_charBuf->notify(g_pendingFrame, g_pendingFrameLen);
  if (ok) {
    g_pendingFrameLen = 0;
  }
  return ok;
}

// Copy a data frame into the pending slot. Precondition: g_pendingFrameLen
// must be 0 (caller flushes any prior frame first).
static void bufferDataFrame(const CommutaSample* records, size_t count) {
  g_pendingFrame[0] = COMMUTA_SYNC_FRAME_DATA;
  memcpy(g_pendingFrame + 1, records, count * sizeof(CommutaSample));
  g_pendingFrameLen = 1 + count * sizeof(CommutaSample);
  g_pendingIsEos = false;
}

// Copy an EOS frame into the pending slot. Precondition as above.
static void bufferEosFrame(uint32_t firstSeq, uint32_t lastSeq, uint32_t sentCount) {
  g_pendingFrame[0] = COMMUTA_SYNC_FRAME_EOS;
  memcpy(g_pendingFrame + 1, &firstSeq, 4);
  memcpy(g_pendingFrame + 5, &lastSeq, 4);
  memcpy(g_pendingFrame + 9, &sentCount, 4);
  g_pendingFrameLen = 13;
  g_pendingIsEos = true;
}

void commutaBleServiceSync() {
  // ── 1. Disconnect cleanup ─────────────────────────────────────────────
  // Runs on the main loop so it's safe to touch the file handle inside
  // g_syncState here.
  if (!g_connected) {
    if (g_syncActive) {
      commutaSyncEnd(g_syncState);
      g_syncActive = false;
    }
    // Drop any orphaned frame — we can't send it and the phone has moved on.
    g_pendingFrameLen = 0;
    g_pendingIsEos = false;
    // Also clear any pending request that arrived just before the disconnect.
    portENTER_CRITICAL(&g_syncMux);
    g_syncRequested = false;
    portEXIT_CRITICAL(&g_syncMux);
    return;
  }

  // ── 2. Flush any frame carried over from a previous call ──────────────
  // This is the heart of the back-pressure fix. If notify() was refused
  // last time, we retry here first, and do nothing else this iteration
  // unless the retry succeeds. The main loop cycles quickly enough that
  // the host stack's tx queue drains a slot within a handful of calls.
  if (g_pendingFrameLen > 0) {
    bool wasEos = g_pendingIsEos;
    if (!tryFlushPendingFrame()) {
      // Still refused. Try again next iteration.
      return;
    }
    // Flush succeeded. If the frame that just left was EOS, that means
    // the stream is genuinely done — tear the iterator down NOW so we
    // don't fall through to step 4 and buffer a duplicate EOS.
    if (wasEos) {
      if (g_syncActive) {
        commutaSyncEnd(g_syncState);
        g_syncActive = false;
      }
      g_pendingIsEos = false;
    }
    // Fall through — a new sync request may be waiting, and a data-
    // frame flush leaves the iterator ready for the next chunk.
  }

  // ── 3. Consume a pending sync request ─────────────────────────────────
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

  if (requested) {
    bool ok = commutaSyncBegin(g_syncState, startSeq, endSeq);
    if (!ok) {
      // Nothing to send. Emit an EOS with all-zeros so the phone still
      // gets the reconciliation it's waiting for. If notify is refused
      // right now, next iteration's step 2 will retry.
      bufferEosFrame(0, 0, 0);
      Serial.println("BLE: sync empty range; sending EOS(0,0,0)");
      tryFlushPendingFrame();
      return;
    }
    g_syncActive = true;
    Serial.println("BLE: sync started");
    return;  // Pull the first chunk next iteration.
  }

  // ── 4. Service an active stream ───────────────────────────────────────
  if (g_syncActive) {
    if (g_syncState.active) {
      // Pull one chunk into the pending slot, then attempt to flush.
      // We only get here when g_pendingFrameLen is 0 (step 2 either had
      // nothing pending or successfully flushed), so the iterator can
      // safely advance — the chunk we just read is guaranteed to be
      // buffered before we could ever pull the next one.
      CommutaSample chunk[COMMUTA_SYNC_RECORDS_PER_FRAME];
      size_t n = commutaSyncReadChunk(g_syncState, chunk,
                                      COMMUTA_SYNC_RECORDS_PER_FRAME);
      if (n > 0) {
        bufferDataFrame(chunk, n);
        tryFlushPendingFrame();  // If refused, next iteration retries.
      }
      // If n == 0 without s.active having flipped false, that's an
      // exhausted iterator we'll pick up on the next call (see below).
    } else {
      // Iterator done — buffer EOS. Tear-down only happens AFTER the EOS
      // has been accepted by the stack (handled in step 2's wasEos path
      // or immediately below if this call's flush succeeds).
      Serial.printf("BLE: sync EOS first=%u last=%u count=%u\n",
                    (unsigned)g_syncState.firstSentSeq,
                    (unsigned)g_syncState.lastSentSeq,
                    (unsigned)g_syncState.sentCount);
      bufferEosFrame(g_syncState.firstSentSeq,
                     g_syncState.lastSentSeq,
                     g_syncState.sentCount);
      if (tryFlushPendingFrame()) {
        // EOS accepted immediately. Safe to tear down now.
        commutaSyncEnd(g_syncState);
        g_syncActive = false;
        g_pendingIsEos = false;
      }
      // Else: EOS remains in the pending slot. Next iteration's step 2
      // will keep retrying and tear down once accepted.
    }
  }
}