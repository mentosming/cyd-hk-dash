#include "app_state.h"

namespace appstate {
namespace {
AppState g_state;
SemaphoreHandle_t g_mutex;
}  // namespace

void begin() { g_mutex = xSemaphoreCreateMutex(); }

void with(void (*fn)(AppState&)) {
  xSemaphoreTake(g_mutex, portMAX_DELAY);
  fn(g_state);
  xSemaphoreGive(g_mutex);
}

AppState snapshot() {
  xSemaphoreTake(g_mutex, portMAX_DELAY);
  AppState copy = g_state;
  // Reading a snapshot consumes the dirty flags.
  g_state.journeyDirty = false;
  g_state.metersDirty = false;
  g_state.fuelDirty = false;
  g_state.slotNamesDirty = false;
  g_state.linkDirty = false;
  xSemaphoreGive(g_mutex);
  return copy;
}

}  // namespace appstate
