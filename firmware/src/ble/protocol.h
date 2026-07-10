#pragma once
// Binary payload layouts — normative spec: docs/ble-protocol.md
// All integers little-endian. PROTOCOL_VERSION (=2) in app_config.h.
#include <cstdint>
#include <cstring>

namespace proto {

constexpr uint8_t kProtoVer = 2;

constexpr uint8_t kMaxSlots = 12;
constexpr uint8_t kMaxMeterGroups = 4;
constexpr uint8_t kMeterNameMax = 36;   // Chinese street names: up to 12 CJK chars
constexpr uint8_t kSlotNameMax = 24;    // route display names: up to 8 CJK chars
constexpr uint8_t kFuelBrands = 5;      // 中石化, 中國石油, 加德士, 埃索, 蜆殼
constexpr uint8_t kFuelTypes = 3;       // 無鉛, 特級無鉛, 柴油
constexpr uint16_t kFuelNA = 0xFFFF;

// Journey minute sentinels
constexpr uint8_t kMinutesNA = 0xFF;
constexpr uint8_t kMinutesCongestion = 0xFE;
constexpr uint8_t kMinutesClosed = 0xFD;

struct TimeSync {
  uint32_t epoch_utc;
  int16_t tz_min;
  uint8_t flags;  // bit0..3: today / +1 / +2 / +3 days use the Sun/PH toll schedule
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
  uint8_t lpp;  // longest parking period of the vacant spaces (minutes: 30/60/120), 0 unknown
  char name[kMeterNameMax + 1];  // NUL-terminated Chinese street name
};

struct Meters {
  uint32_t fetch_epoch;
  uint8_t status;  // 0 ok, 1 no-GPS, 2 fetch error, 3 no meters <=4km, 4 no vacancy <=4km
  uint8_t count;
  MeterGroup groups[kMaxMeterGroups];
};

struct SlotName {
  uint8_t slot;
  char name[kSlotNameMax + 1];
};

struct SlotNames {
  uint8_t count;
  SlotName names[kMaxSlots];
};

struct FuelPrices {
  uint32_t fetch_epoch;
  // [brand][type], cents (price * 100); kFuelNA = unavailable
  uint16_t cents[kFuelBrands][kFuelTypes];
};

inline uint32_t rdU32(const uint8_t* p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
inline uint16_t rdU16(const uint8_t* p) { return (uint16_t)p[0] | ((uint16_t)p[1] << 8); }

// Each decoder returns false on malformed input (wrong version / truncated).

inline bool decodeTimeSync(const uint8_t* d, size_t len, TimeSync& out) {
  if (len < 8 || d[0] != kProtoVer) return false;
  out.epoch_utc = rdU32(d + 1);
  out.tz_min = (int16_t)rdU16(d + 5);
  out.flags = d[7];
  return true;
}

inline bool decodeJourney(const uint8_t* d, size_t len, Journey& out) {
  if (len < 6 || d[0] != kProtoVer) return false;
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
  if (len < 7 || d[0] != kProtoVer) return false;
  out.fetch_epoch = rdU32(d + 1);
  out.status = d[5];
  out.count = d[6];
  if (out.count > kMaxMeterGroups) return false;
  size_t off = 7;
  for (uint8_t i = 0; i < out.count; i++) {
    if (len < off + 6) return false;
    MeterGroup& g = out.groups[i];
    g.dist_m = rdU16(d + off);
    g.vacant = d[off + 2];
    g.total = d[off + 3];
    g.lpp = d[off + 4];
    uint8_t nl = d[off + 5];
    if (nl > kMeterNameMax || len < off + 6 + nl) return false;
    memcpy(g.name, d + off + 6, nl);
    g.name[nl] = '\0';
    off += 6 + nl;
  }
  return true;
}

inline bool decodeSlotNames(const uint8_t* d, size_t len, SlotNames& out) {
  if (len < 2 || d[0] != kProtoVer) return false;
  out.count = d[1];
  if (out.count > kMaxSlots) return false;
  size_t off = 2;
  for (uint8_t i = 0; i < out.count; i++) {
    if (len < off + 2) return false;
    SlotName& s = out.names[i];
    s.slot = d[off];
    uint8_t nl = d[off + 1];
    if (s.slot < 1 || s.slot > kMaxSlots || nl > kSlotNameMax || len < off + 2 + nl) return false;
    memcpy(s.name, d + off + 2, nl);
    s.name[nl] = '\0';
    off += 2 + nl;
  }
  return true;
}

inline bool decodeFuelPrices(const uint8_t* d, size_t len, FuelPrices& out) {
  if (len < 5 + 2 * kFuelBrands * kFuelTypes || d[0] != kProtoVer) return false;
  out.fetch_epoch = rdU32(d + 1);
  size_t off = 5;
  for (int b = 0; b < kFuelBrands; b++)
    for (int t = 0; t < kFuelTypes; t++, off += 2) out.cents[b][t] = rdU16(d + off);
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
