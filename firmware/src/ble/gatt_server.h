#pragma once
#include <cstdint>

namespace ble {

void begin();
// Notify opcodes on the Command characteristic (no-op when not subscribed)
void notifyCommand(uint8_t opcode);
// Called from the main loop to drive the 120 s journey tick + watchdog
void tick();
bool isConnected();
// Forget all bonded devices (long-press the clock) — forces re-pairing
void clearBonds();

}  // namespace ble
