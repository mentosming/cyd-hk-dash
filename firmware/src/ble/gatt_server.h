#pragma once
#include <cstdint>

namespace ble {

void begin();
// Notify opcodes on the Command characteristic (no-op when not subscribed)
void notifyCommand(uint8_t opcode);
// Called from the main loop to drive the 120 s journey tick
void tick();
bool isConnected();

}  // namespace ble
