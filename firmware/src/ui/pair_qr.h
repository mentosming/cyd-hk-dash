#pragma once
#include "../model/app_state.h"

namespace ui {

// Pairing QR overlay: shown while a phone is connected but not yet authorised,
// or forced open by long-pressing the BT dot. Encodes the cyddash:// deep link.
void pairQRInit();
void pairQRUpdate(const AppState& s);

}  // namespace ui
