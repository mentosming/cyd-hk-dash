#include "data_cache.h"

#include <Preferences.h>

#include "../../include/app_config.h"

namespace datacache {
namespace {

Preferences g_prefs;
uint32_t g_lastSaveMs = 0;

// Guard byte so stale blobs from an older struct layout are ignored.
constexpr uint8_t kBlobVer = PROTOCOL_VERSION;

void loadInto(AppState& s) {
  uint8_t ver = g_prefs.getUChar("ver", 0);
  if (ver != kBlobVer) return;

  if (g_prefs.getBytesLength("journey") == sizeof(s.journey)) {
    g_prefs.getBytes("journey", &s.journey, sizeof(s.journey));
    s.journeyReceivedMs = millis() | 1;  // non-zero: "have (old) data"
    s.journeyDirty = true;
  }
  if (g_prefs.getBytesLength("meters") == sizeof(s.meters)) {
    g_prefs.getBytes("meters", &s.meters, sizeof(s.meters));
    s.metersReceivedMs = millis() | 1;
    s.metersDirty = true;
  }
  if (g_prefs.getBytesLength("fuel") == sizeof(s.fuel)) {
    g_prefs.getBytes("fuel", &s.fuel, sizeof(s.fuel));
    s.fuelReceivedMs = millis() | 1;
    s.fuelDirty = true;
  }
  if (g_prefs.getBytesLength("slots") == sizeof(s.slotNames)) {
    g_prefs.getBytes("slots", &s.slotNames, sizeof(s.slotNames));
    s.slotNamesDirty = true;
  }
}

void persist(const char* key, const void* data, size_t len) {
  g_prefs.putUChar("ver", kBlobVer);
  g_prefs.putBytes(key, data, len);
}

void saveJourney(AppState& s) {
  if (s.journeyReceivedMs) persist("journey", &s.journey, sizeof(s.journey));
}
void saveMeters(AppState& s) {
  if (s.metersReceivedMs) persist("meters", &s.meters, sizeof(s.meters));
}
void saveFuel(AppState& s) {
  if (s.fuelReceivedMs) persist("fuel", &s.fuel, sizeof(s.fuel));
}
void saveSlots(AppState& s) { persist("slots", &s.slotNames, sizeof(s.slotNames)); }

}  // namespace

void begin() {
  g_prefs.begin("cache", false);
  appstate::with(loadInto);
}

void saveIfDue() {
  // Journey updates every 2 min; writing NVS each time would wear the flash.
  if (millis() - g_lastSaveMs < CLOCK_NVS_SAVE_MS) return;
  g_lastSaveMs = millis();
  appstate::with(saveJourney);
}

void saveMetersNow() { appstate::with(saveMeters); }
void saveFuelNow() { appstate::with(saveFuel); }
void saveSlotNames() { appstate::with(saveSlots); }

}  // namespace datacache
