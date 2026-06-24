// storage.cpp - LittleFS sample buffering implementation

#include "storage.h"

#include <Arduino.h>
#include <LittleFS.h>
#include <string.h>

// ---------- Module state ----------
// All state is in-memory and re-derived on boot from the contents of /buf/.
// We deliberately do not maintain a separate index file: the directory IS
// the index. After a power-cut the next boot's scan recovers everything
// from filenames + file sizes alone.
static uint32_t g_oldestSegmentBase = 0;   // first seq in the oldest segment on disk
static uint32_t g_currentSegmentBase = 0;  // first seq in the segment we're currently writing
static uint32_t g_recordsInCurrent = 0;    // records already written to the current segment
static bool g_haveAnySegment = false;      // false on first boot, before any sample written

// Cached read-file handle. Opening per chunk is cheap but caching across
// chunks avoids reopening the same segment when consecutive reads fall in
// the same file - which is the common case.
static File g_readFile;
static uint32_t g_readFileBase = UINT32_MAX;

// ---------- Helpers ----------
static void segmentPath(uint32_t segmentBase, char* out, size_t len) {
  snprintf(out, len, "/buf/%08u.bin", (unsigned)segmentBase);
}

static void closeReadCache() {
  if (g_readFileBase != UINT32_MAX) {
    g_readFile.close();
    g_readFileBase = UINT32_MAX;
  }
}

static File& openReadCache(uint32_t segmentBase) {
  if (g_readFileBase == segmentBase && g_readFile) {
    return g_readFile;
  }
  closeReadCache();
  char path[32];
  segmentPath(segmentBase, path, sizeof(path));
  g_readFile = LittleFS.open(path, "r");
  if (g_readFile) g_readFileBase = segmentBase;
  return g_readFile;
}

// ---------- Boot scan ----------
// Walks /buf/ to find the lowest and highest segment-base filenames, plus
// the record count in the highest segment. Restores all module state.
//
// Note: we do NOT detect gaps between min and max - the iterator handles
// missing segments gracefully if they ever occur (e.g. after FS damage).
static bool bootScan() {
  if (!LittleFS.exists("/buf")) {
    if (!LittleFS.mkdir("/buf")) {
      Serial.println("storage: failed to create /buf/");
      return false;
    }
    Serial.println("storage: /buf/ created (no prior data)");
    return true;
  }

  File dir = LittleFS.open("/buf");
  if (!dir || !dir.isDirectory()) {
    Serial.println("storage: /buf/ exists but is not a directory");
    return false;
  }

  uint32_t lowest = UINT32_MAX;
  uint32_t highest = 0;
  size_t highestSize = 0;
  bool found = false;

  File entry = dir.openNextFile();
  while (entry) {
    if (!entry.isDirectory()) {
      // LittleFS may return either "00000064.bin" or "/buf/00000064.bin"
      // depending on version; strip any leading path.
      const char* name = entry.name();
      const char* slash = strrchr(name, '/');
      if (slash) name = slash + 1;

      // Expect exactly 8 digits + ".bin" = 12 chars
      if (strlen(name) == 12 && strcmp(name + 8, ".bin") == 0) {
        char digits[9];
        memcpy(digits, name, 8);
        digits[8] = 0;
        uint32_t base = (uint32_t)strtoul(digits, nullptr, 10);
        if (!found || base < lowest) lowest = base;
        if (!found || base > highest) {
          highest = base;
          highestSize = entry.size();
        }
        found = true;
      }
    }
    entry = dir.openNextFile();
  }

  if (!found) {
    Serial.println("storage: /buf/ empty, starting fresh");
    return true;
  }

  g_haveAnySegment = true;
  g_oldestSegmentBase = lowest;
  g_currentSegmentBase = highest;
  g_recordsInCurrent = highestSize / sizeof(CommutaSample);
  // Defensive cap - shouldn't happen but if a segment ended up oversized
  // somehow, treat it as full and the next append will roll to a new one.
  if (g_recordsInCurrent > RECORDS_PER_SEGMENT) {
    g_recordsInCurrent = RECORDS_PER_SEGMENT;
  }

  Serial.printf("storage: oldest=%u, current=%u, records in current=%u\n",
                (unsigned)g_oldestSegmentBase,
                (unsigned)g_currentSegmentBase,
                (unsigned)g_recordsInCurrent);
  return true;
}

// ---------- Eviction ----------
static void evictIfNeeded() {
  // Number of segments on disk = (current - oldest) / size + 1.
  // Evict while that count would exceed MAX_SEGMENTS.
  while (((g_currentSegmentBase - g_oldestSegmentBase) / RECORDS_PER_SEGMENT) + 1
         > MAX_SEGMENTS) {
    char path[32];
    segmentPath(g_oldestSegmentBase, path, sizeof(path));
    if (LittleFS.remove(path)) {
      Serial.printf("storage: evicted %s\n", path);
    } else {
      // If the file is unreadable for some reason, log and skip forward so
      // we don't loop forever on the same broken entry.
      Serial.printf("storage: WARN remove(%s) failed; skipping\n", path);
    }
    g_oldestSegmentBase += RECORDS_PER_SEGMENT;
  }
}

// ---------- Public API ----------
bool commutaStorageBegin() {
  // true = auto-format on mount failure. Acceptable for this device: if FS
  // ever gets damaged, we'd rather boot cleanly than refuse to start.
  if (!LittleFS.begin(true)) {
    Serial.println("storage: LittleFS mount failed (even after format)");
    return false;
  }
  Serial.printf("storage: LittleFS mounted (total=%u used=%u)\n",
                (unsigned)LittleFS.totalBytes(),
                (unsigned)LittleFS.usedBytes());
  return bootScan();
}

uint32_t commutaStorageNextSequence() {
  if (!g_haveAnySegment) return 0;
  return g_currentSegmentBase + g_recordsInCurrent;
}

bool commutaStorageAppend(const CommutaSample& sample) {
  uint32_t seq = sample.sequence;
  uint32_t segmentBase = (seq / RECORDS_PER_SEGMENT) * RECORDS_PER_SEGMENT;

  // First-ever sample - initialise both pointers.
  if (!g_haveAnySegment) {
    g_haveAnySegment = true;
    g_oldestSegmentBase = segmentBase;
    g_currentSegmentBase = segmentBase;
    g_recordsInCurrent = 0;
  }

  // Transitioning to a new segment.
  if (segmentBase != g_currentSegmentBase) {
    g_currentSegmentBase = segmentBase;
    g_recordsInCurrent = 0;
    evictIfNeeded();
  }

  // If the read cache happens to be holding the same file we're about to
  // append to, close it first to avoid concurrent open-for-read and
  // open-for-append on the same file.
  if (g_readFileBase == g_currentSegmentBase) closeReadCache();

  char path[32];
  segmentPath(g_currentSegmentBase, path, sizeof(path));
  File f = LittleFS.open(path, "a");
  if (!f) {
    Serial.printf("storage: open(%s) for append failed\n", path);
    return false;
  }
  size_t n = f.write((const uint8_t*)&sample, sizeof(sample));
  f.close();
  if (n != sizeof(sample)) {
    Serial.printf("storage: short write to %s (%u/%u)\n",
                  path, (unsigned)n, (unsigned)sizeof(sample));
    return false;
  }
  g_recordsInCurrent++;
  return true;
}

void commutaStorageGetRange(uint32_t& oldestSeq, uint32_t& newestSeq, uint32_t& count) {
  if (!g_haveAnySegment || g_recordsInCurrent == 0) {
    oldestSeq = 0;
    newestSeq = 0;
    count = 0;
    return;
  }
  oldestSeq = g_oldestSegmentBase;
  newestSeq = g_currentSegmentBase + g_recordsInCurrent - 1;
  count = newestSeq - oldestSeq + 1;
}

// ---------- Sync iterator ----------
bool commutaSyncBegin(CommutaSyncState& s, uint32_t startSeq, uint32_t endSeq) {
  s.active = false;
  s.firstSentSeq = 0;
  s.lastSentSeq = 0;
  s.sentCount = 0;

  uint32_t oldest, newest, count;
  commutaStorageGetRange(oldest, newest, count);
  if (count == 0) return false;

  // Clamp request to what we actually have.
  if (startSeq < oldest) startSeq = oldest;
  if (endSeq > newest) endSeq = newest;
  if (startSeq > endSeq) return false;

  s.cursorSeq = startSeq;
  s.endSeq = endSeq;
  s.active = true;
  return true;
}

size_t commutaSyncReadChunk(CommutaSyncState& s, CommutaSample* out, size_t maxRecords) {
  if (!s.active) return 0;
  size_t produced = 0;

  while (produced < maxRecords && s.cursorSeq <= s.endSeq) {
    uint32_t segmentBase = (s.cursorSeq / RECORDS_PER_SEGMENT) * RECORDS_PER_SEGMENT;
    File& f = openReadCache(segmentBase);
    if (!f) {
      // The file we expected isn't there - likely evicted between range
      // check and this read. Skip forward to the next segment that exists.
      Serial.printf("sync: missing segment %u, skipping\n", (unsigned)segmentBase);
      s.cursorSeq = segmentBase + RECORDS_PER_SEGMENT;
      continue;
    }

    uint32_t indexInSegment = s.cursorSeq - segmentBase;
    size_t offset = indexInSegment * sizeof(CommutaSample);
    if (!f.seek(offset)) {
      Serial.printf("sync: seek failed in segment %u\n", (unsigned)segmentBase);
      s.active = false;
      return produced;
    }

    // Read as many consecutive records as fit in (chunk AND segment AND range).
    uint32_t remainingInSegment = RECORDS_PER_SEGMENT - indexInSegment;
    uint32_t remainingInRange = s.endSeq - s.cursorSeq + 1;
    uint32_t remainingInChunk = maxRecords - produced;
    uint32_t toRead = remainingInSegment;
    if (toRead > remainingInRange) toRead = remainingInRange;
    if (toRead > remainingInChunk) toRead = remainingInChunk;

    size_t want = toRead * sizeof(CommutaSample);
    size_t n = f.read((uint8_t*)(out + produced), want);

    if (n != want) {
      // Likely a partial segment (current write segment hasn't been filled
      // up to where we tried to read). Account for whatever we did get and
      // stop the iterator cleanly.
      uint32_t got = n / sizeof(CommutaSample);
      if (got > 0) {
        if (s.sentCount == 0) s.firstSentSeq = s.cursorSeq;
        s.lastSentSeq = s.cursorSeq + got - 1;
        s.sentCount += got;
        produced += got;
      }
      s.active = false;
      return produced;
    }

    if (s.sentCount == 0) s.firstSentSeq = s.cursorSeq;
    s.lastSentSeq = s.cursorSeq + toRead - 1;
    s.sentCount += toRead;
    s.cursorSeq += toRead;
    produced += toRead;
  }

  if (s.cursorSeq > s.endSeq) s.active = false;
  return produced;
}

void commutaSyncEnd(CommutaSyncState& s) {
  s.active = false;
  closeReadCache();
}