#pragma once
// Mutex-guarded shared state between the BLE task and the LVGL/main task.
// BLE callbacks write; the UI tick copies a snapshot and renders.
#include <Arduino.h>

#include "../ble/protocol.h"

struct AppState {
  // Journey
  proto::Journey journey{};
  uint32_t journeyReceivedMs = 0;  // millis() when written; 0 = never
  // Previous capture's minutes per slot (0xFF unknown) — drives the ↑↓ arrows
  uint8_t prevMinutes[proto::kMaxSlots + 1] = {0};
  // Meters
  proto::Meters meters{};
  uint32_t metersReceivedMs = 0;
  bool metersPending = false;      // 掃一掃 sent, waiting for reply
  uint32_t metersRequestMs = 0;
  // Fuel prices
  proto::FuelPrices fuel{};
  uint32_t fuelReceivedMs = 0;
  // Route display names for slots 7-9 (from SlotNames payload / NVS)
  char slotNames[proto::kMaxSlots + 1][proto::kSlotNameMax + 1] = {};
  // Link
  bool connected = false;
  bool subscribed = false;
  // Non-zero while pairing: PIN the UI should display
  uint32_t showPasskey = 0;

  // Dirty flags set by BLE task, cleared by UI task
  volatile bool journeyDirty = false;
  volatile bool metersDirty = false;
  volatile bool fuelDirty = false;
  volatile bool slotNamesDirty = false;
  volatile bool linkDirty = false;
};

namespace appstate {

void begin();
// Run fn while holding the state lock. Keep fn short (no LVGL calls inside).
void with(void (*fn)(AppState&));
// Copy-out snapshot for the UI.
AppState snapshot();

}  // namespace appstate
