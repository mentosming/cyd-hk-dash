#pragma once
#include "../model/app_state.h"

namespace ui {

void init();
// Call from the main loop every ~250-500 ms with a fresh snapshot.
void tick(const AppState& s);

}  // namespace ui
