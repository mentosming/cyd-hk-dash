#pragma once
// NVS persistence of the last-known data so a cold boot in the car shows
// yesterday's numbers (greyed stale) instead of blanks.
#include "app_state.h"

namespace datacache {

void begin();                 // load cached journey/meters/fuel/slot names into appstate
void saveIfDue();             // rate-limited periodic save (call from loop)
void saveMetersNow();         // meters/fuel writes are rare — persist immediately
void saveFuelNow();
void saveSlotNames();

}  // namespace datacache
