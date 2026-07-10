#pragma once
// HK local clock: epoch anchored to millis() by phone TimeSync, persisted to
// NVS so a reboot in the car still shows approximate time/tolls.
#include <Arduino.h>

namespace hkclock {

enum class Sync : uint8_t {
  NEVER = 0,   // no idea what time it is
  APPROX = 1,  // restored from NVS after boot (power-off gap unknown)
  SYNCED = 2,  // phone-synced this power cycle
};

struct Local {
  uint32_t secOfDay;  // 0..86399 HK local
  uint8_t dow;        // 0 = Sunday
  uint32_t days;      // local days since Unix epoch (date identity)
  uint8_t hour, min;
};

void begin();  // load NVS
void onTimeSync(uint32_t epochUtc, int16_t tzMin, uint8_t phFlags);
Sync syncState();
Local now();
// True if today should use the Sunday/PH toll schedule.
// Uses phone-provided PH flags when they match today's date, else falls back
// to "is it Sunday".
bool sundayOrPH();
void persistIfDue();  // call from loop; saves every CLOCK_NVS_SAVE_MS

}  // namespace hkclock
