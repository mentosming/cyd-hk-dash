#pragma once
// Binary payload layouts — normative spec: docs/ble-protocol.md
// All integers little-endian. PROTOCOL_VERSION in app_config.h.
#include <cstdint>
#include <cstring>

namespace proto {

constexpr uint8_t kMaxSlots = 12;
constexpr uint8_t kMaxMeterGroups = 4;
constexpr uint8_t kMeterNameMax = 36;  // Chinese street names: up to 12 CJK chars
constexpr uint8_t kMaxMapPoints = 48;

// Journey minute sentinels
constexpr uint8_t kMinutesNA = 0xFF;
constexpr uint8_t kMinutesCongestion = 0xFE;
constexpr uint8_t kMinutesClosed = 0xFD;

struct TimeSync {
  uint32_t epoch_utc;
  int16_t tz_min;
  uint8_t flags;  // bit0 today Sun/PH, bit1 tomorrow Sun/PH
};

struct JourneyEntry {
  uint8_t slot;     // 1..12
  uint8_t minutes;  // or sentinel
  uint8_t colour;   // 1 red, 2 amber, 3 green, 0 none
};

struct Journey {
  uint32_t capture_epoch;
  uint8_t count;
  JourneyEntry entries[kMaxSlots];
};

struct MeterGroup {
  uint16_t dist_m;
  uint8_t vacant;
  uint8_t total;
  char name[kMeterNameMax + 1];  // NUL-terminated
};

struct Meters {
  uint32_t fetch_epoch;
  uint8_t status;  // 0 ok, 1 no-GPS, 2 fetch error, 3 none nearby
  uint8_t count;
  MeterGroup groups[kMaxMeterGroups];
};

struct MapPoint {
  int8_t dx;       // east offset as fraction of radius_m: metres = dx/127 * radius
  int8_t dy;       // north offset, same encoding
  uint8_t status;  // 0 vacant, 1 occupied, 2 suspended/unknown
};

struct MeterMap {
  uint32_t fetch_epoch;
  uint16_t radius_m;
  uint8_t count;
  MapPoint points[kMaxMapPoints];
};

inline uint32_t rdU32(const uint8_t* p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
inline uint16_t rdU16(const uint8_t* p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }

// Each decoder returns false on malformed input (wrong version / truncated).

inline bool decodeTimeSync(const uint8_t* d, size_t len, TimeSync& out) {
  if (len < 8 || d[0] != 1) return false;
  out.epoch_utc = rdU32(d + 1);
  out.tz_min = (int16_t)rdU16(d + 5);
  out.flags = d[7];
  return true;
}

inline bool decodeJourney(const uint8_t* d, size_t len, Journey& out) {
  if (len < 6 || d[0] != 1) return false;
  out.capture_epoch = rdU32(d + 1);
  out.count = d[5];
  if (out.count > kMaxSlots || len < 6 + (size_t)out.count * 3) return false;
  for (uint8_t i = 0; i < out.count; i++) {
    const uint8_t* e = d + 6 + i * 3;
    out.entries[i] = {e[0], e[1], e[2]};
    if (out.entries[i].slot < 1 || out.entries[i].slot > kMaxSlots) return false;
  }
  return true;
}

inline bool decodeMeters(const uint8_t* d, size_t len, Meters& out) {
  if (len < 7 || d[0] != 1) return false;
  out.fetch_epoch = rdU32(d + 1);
  out.status = d[5];
  out.count = d[6];
  if (out.count > kMaxMeterGroups) return false;
  size_t off = 7;
  for (uint8_t i = 0; i < out.count; i++) {
    if (len < off + 5) return false;
    MeterGroup& g = out.groups[i];
    g.dist_m = rdU16(d + off);
    g.vacant = d[off + 2];
    g.total = d[off + 3];
    uint8_t nl = d[off + 4];
    if (nl > kMeterNameMax || len < off + 5 + nl) return false;
    memcpy(g.name, d + off + 5, nl);
    g.name[nl] = '\0';
    off += 5 + nl;
  }
  return true;
}

inline bool decodeMeterMap(const uint8_t* d, size_t len, MeterMap& out) {
  if (len < 8 || d[0] != 1) return false;
  out.fetch_epoch = rdU32(d + 1);
  out.radius_m = rdU16(d + 5);
  out.count = d[7];
  if (out.count > kMaxMapPoints || len < 8 + (size_t)out.count * 3) return false;
  for (uint8_t i = 0; i < out.count; i++) {
    const uint8_t* p = d + 8 + i * 3;
    out.points[i] = {(int8_t)p[0], (int8_t)p[1], p[2]};
  }
  return true;
}

// Status payload (12 bytes) encoder
inline void encodeStatus(uint8_t* out, uint8_t protoVer, uint8_t fwMaj, uint8_t fwMin,
                         uint32_t uptime_s, uint16_t journeyAge_s, uint16_t metersAge_s) {
  out[0] = protoVer;
  out[1] = fwMaj;
  out[2] = fwMin;
  out[3] = 0;
  out[4] = uptime_s & 0xFF;
  out[5] = (uptime_s >> 8) & 0xFF;
  out[6] = (uptime_s >> 16) & 0xFF;
  out[7] = (uptime_s >> 24) & 0xFF;
  out[8] = journeyAge_s & 0xFF;
  out[9] = (journeyAge_s >> 8) & 0xFF;
  out[10] = metersAge_s & 0xFF;
  out[11] = (metersAge_s >> 8) & 0xFF;
}

}  // namespace proto
