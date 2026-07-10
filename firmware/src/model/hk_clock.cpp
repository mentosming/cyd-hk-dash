#include "hk_clock.h"

#include <Preferences.h>

#include "../../include/app_config.h"

namespace hkclock {
namespace {

Preferences g_prefs;
Sync g_sync = Sync::NEVER;
uint32_t g_epochUtcAtAnchor = 0;
uint32_t g_anchorMs = 0;
int16_t g_tzMin = 480;
// PH flags with the local date (days since epoch) they were issued for
uint8_t g_phFlags = 0;
uint32_t g_phFlagsDay = 0;
uint32_t g_lastSaveMs = 0;

uint32_t epochUtcNow() {
  return g_epochUtcAtAnchor + (millis() - g_anchorMs) / 1000;
}

void save() {
  g_prefs.putUInt("epoch", epochUtcNow());
  g_prefs.putShort("tz", g_tzMin);
  g_prefs.putUChar("ph", g_phFlags);
  g_prefs.putUInt("phday", g_phFlagsDay);
  g_lastSaveMs = millis();
}

}  // namespace

void begin() {
  g_prefs.begin("hkclock", false);
  uint32_t saved = g_prefs.getUInt("epoch", 0);
  if (saved > 1700000000UL) {  // sanity: after Nov 2023
    g_epochUtcAtAnchor = saved;
    g_anchorMs = millis();
    g_tzMin = g_prefs.getShort("tz", 480);
    g_phFlags = g_prefs.getUChar("ph", 0);
    g_phFlagsDay = g_prefs.getUInt("phday", 0);
    g_sync = Sync::APPROX;
  }
}

void onTimeSync(uint32_t epochUtc, int16_t tzMin, uint8_t phFlags) {
  g_epochUtcAtAnchor = epochUtc;
  g_anchorMs = millis();
  g_tzMin = tzMin;
  g_phFlags = phFlags;
  g_phFlagsDay = (epochUtc + (int32_t)tzMin * 60) / 86400;
  g_sync = Sync::SYNCED;
  save();
}

Sync syncState() { return g_sync; }

uint32_t epochUtc() { return g_sync == Sync::NEVER ? 0 : epochUtcNow(); }

Local now() {
  Local l{};
  if (g_sync == Sync::NEVER) return l;
  uint32_t localEpoch = epochUtcNow() + (int32_t)g_tzMin * 60;
  l.days = localEpoch / 86400;
  l.secOfDay = localEpoch % 86400;
  l.dow = (l.days + 4) % 7;  // 1970-01-01 was a Thursday
  l.hour = l.secOfDay / 3600;
  l.min = (l.secOfDay % 3600) / 60;
  return l;
}

bool sundayOrPH() {
  Local l = now();
  if (g_sync == Sync::NEVER) return false;
  // phFlags covers 4 consecutive days starting at the sync date
  if (l.days >= g_phFlagsDay && l.days <= g_phFlagsDay + 3) {
    return g_phFlags & (1 << (l.days - g_phFlagsDay));
  }
  return l.dow == 0;
}

void persistIfDue() {
  if (g_sync == Sync::NEVER) return;
  if (millis() - g_lastSaveMs >= CLOCK_NVS_SAVE_MS) save();
}

}  // namespace hkclock
