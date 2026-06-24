// storage.h - LittleFS-based sample buffering for Commuta
//
// Provides a circular ring of segment files on the on-board flash. Live
// samples are appended as 40-byte CommutaSample records; on reconnect the
// phone reads the available range from Status and pulls back missing data
// via the Buffered characteristic.
//
// Layout on flash:
//   /buf/00000000.bin   records 0..63
//   /buf/00000064.bin   records 64..127
//   /buf/00000128.bin   records 128..191
//   ...
//
// Each file holds at most RECORDS_PER_SEGMENT contiguous samples; oldest
// files are deleted when MAX_SEGMENTS would be exceeded. Sequence numbers
// are global and monotonic - they survive reboots because they are
// reconstructed from the highest-numbered filename plus its record count.

#ifndef COMMUTA_STORAGE_H
#define COMMUTA_STORAGE_H

#include <stdint.h>
#include <stddef.h>

#include "ble.h"  // CommutaSample

// ---------- Tunables ----------
// Smaller segments mean less data lost on a crash (only the in-progress
// segment is at risk) at the cost of more files on flash.
#define RECORDS_PER_SEGMENT 64

// 400 * 64 * 10s = ~71 hours = ~3 days of buffered data.
// Fits within the default ESP32 partition's filesystem area (~1.4 MB).
#define MAX_SEGMENTS 400

// ---------- Public API ----------

// Mount LittleFS (formatting it if mount fails), scan /buf/ for existing
// segments, and restore internal state. Returns false on unrecoverable
// filesystem error.
bool commutaStorageBegin();

// Returns the next sequence number to use (= newest persisted seq + 1, or 0
// if storage is empty). Call after commutaStorageBegin() to initialise the
// main sketch's sampleSequence counter.
uint32_t commutaStorageNextSequence();

// Persist one sample to flash. The sample.sequence field decides which
// segment file it belongs to; segments roll over and oldest segments are
// evicted automatically when MAX_SEGMENTS would be exceeded.
bool commutaStorageAppend(const CommutaSample& sample);

// Populate the three range fields exposed in the Status characteristic.
// If storage is empty, oldest == newest == 0 and count == 0.
void commutaStorageGetRange(uint32_t& oldestSeq, uint32_t& newestSeq, uint32_t& count);

// ---------- Sync iterator ----------
// Used by the BLE streaming layer to walk a sequence range. Open with
// commutaSyncBegin(), pull records in batches with commutaSyncReadChunk()
// until it returns 0, then call commutaSyncEnd() to release resources.

struct CommutaSyncState {
  bool active;
  uint32_t cursorSeq;     // next seq to read
  uint32_t endSeq;        // inclusive end of requested range
  uint32_t firstSentSeq;  // first seq actually sent (after clamping to oldest)
  uint32_t lastSentSeq;   // last seq actually sent
  uint32_t sentCount;     // running count of records sent
};

// Initialise an iterator for the inclusive range [startSeq, endSeq].
// Clamps to the actual available range. Returns false if there is nothing
// to send (e.g. requested range entirely older than what's still on disk).
bool commutaSyncBegin(CommutaSyncState& s, uint32_t startSeq, uint32_t endSeq);

// Read up to maxRecords records into out[]. Returns the number actually
// read. Zero means the iterator is exhausted.
size_t commutaSyncReadChunk(CommutaSyncState& s, CommutaSample* out, size_t maxRecords);

// Release any resources held by the iterator (open file handle etc).
void commutaSyncEnd(CommutaSyncState& s);

#endif  // COMMUTA_STORAGE_H