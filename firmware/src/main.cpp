// CYD-DASH — HK tunnel journey times / tolls / parking meters car dashboard
// Board: ESP32-2432S028R ("Cheap Yellow Display")
#include <Arduino.h>
#include <esp32_smartdisplay.h>

#include "../include/app_config.h"
#include "ble/gatt_server.h"
#include "model/app_state.h"
#include "model/hk_clock.h"
#include "ui/ui.h"

static uint32_t g_lastUiTickMs = 0;
static float g_backlight = -1.0f;

static void clearMetersPending(AppState& s) {
  s.metersPending = false;
  s.metersDirty = true;
}

static void updateBacklight() {
  bool night = false;
  if (hkclock::syncState() != hkclock::Sync::NEVER) {
    hkclock::Local t = hkclock::now();
    uint32_t minOfDay = t.secOfDay / 60;
    night = minOfDay >= NIGHT_START_MIN || minOfDay < NIGHT_END_MIN;
  }
  // Any recent touch brings the panel back to full brightness for a while
  float target = (!night || lv_display_get_inactive_time(NULL) < TOUCH_WAKE_MS)
                     ? DAY_BACKLIGHT
                     : NIGHT_BACKLIGHT;
  if (target != g_backlight) {
    g_backlight = target;
    smartdisplay_lcd_set_backlight(target);
  }
}

void setup() {
  Serial.begin(115200);
  log_i("CYD-DASH fw %d.%d proto %d", FW_MAJOR, FW_MINOR, PROTOCOL_VERSION);

  appstate::begin();
  hkclock::begin();

  smartdisplay_init();
  // esp32_smartdisplay does NOT install an LVGL tick source, so without this
  // LVGL's timers never advance: the screen freezes on the first frame and
  // the touch indev is never read. Drive the LVGL tick from millis().
  lv_tick_set_cb([]() -> uint32_t { return millis(); });
  lv_display_set_rotation(lv_display_get_default(), LV_DISPLAY_ROTATION_270);
  smartdisplay_lcd_set_backlight(DAY_BACKLIGHT);

  ui::init();
  ble::begin();
  log_i("Setup complete, free heap %u", (unsigned)ESP.getFreeHeap());
}

void loop() {
  lv_timer_handler();
  ble::tick();

  uint32_t now = millis();
  if (now - g_lastUiTickMs >= 400) {
    g_lastUiTickMs = now;

    AppState s = appstate::snapshot();
    // 掃一掃 timed out without a Meters write — re-enable the button
    if (s.metersPending && now - s.metersRequestMs > METERS_TIMEOUT_MS) {
      appstate::with(clearMetersPending);
      s.metersPending = false;
    }
    ui::tick(s);

    updateBacklight();
    hkclock::persistIfDue();
  }
  delay(5);
}
