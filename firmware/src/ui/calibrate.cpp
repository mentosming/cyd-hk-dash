#include "calibrate.h"

#include <Preferences.h>
#include <esp32_smartdisplay.h>

#include "ui_internal.h"

namespace calibrate {
namespace {

// Native portrait panel size (rotation 0)
constexpr int PANEL_W = 240;
constexpr int PANEL_H = 320;

const lv_point_t kScreenPts[3] = {{30, 30}, {PANEL_W - 30, PANEL_H / 2}, {PANEL_W / 2, PANEL_H - 40}};

lv_obj_t* g_overlay = nullptr;
lv_obj_t* g_cross = nullptr;
lv_obj_t* g_hint = nullptr;
lv_point_t g_touchPts[3];
int g_step = 0;
touch_calibration_data_t g_backup;

void saveToNVS(const touch_calibration_data_t& d) {
  Preferences p;
  p.begin("touchcal", false);
  p.putBytes("cal", &d, sizeof(d));
  p.end();
}

void showCross(int i) {
  lv_obj_set_pos(g_cross, kScreenPts[i].x - 12, kScreenPts[i].y - 16);
  lv_label_set_text_fmt(g_hint, "%d / 3", i + 1);
}

void finish(bool apply) {
  if (apply) {
    touch_calibration_data =
        smartdisplay_compute_touch_calibration(kScreenPts, g_touchPts);
    saveToNVS(touch_calibration_data);
    log_i("Touch calibration saved");
  } else {
    touch_calibration_data = g_backup;
  }
  lv_display_set_rotation(lv_display_get_default(), LV_DISPLAY_ROTATION_270);
  lv_obj_delete(g_overlay);
  g_overlay = nullptr;
}

void onOverlayPressed(lv_event_t* e) {
  lv_indev_t* indev = lv_indev_active();
  if (!indev) return;
  lv_point_t p;
  lv_indev_get_point(indev, &p);
  // rotation is 0 and calibration is disabled → p is a raw driver point
  g_touchPts[g_step] = p;
  log_i("cal point %d: raw (%d, %d)", g_step + 1, (int)p.x, (int)p.y);
  g_step++;
  if (g_step >= 3) {
    finish(true);
  } else {
    showCross(g_step);
  }
}

}  // namespace

void loadFromNVS() {
  Preferences p;
  p.begin("touchcal", false);  // RW: auto-creates the namespace on first boot
  touch_calibration_data_t d{};
  if (p.getBytesLength("cal") == sizeof(d)) {
    p.getBytes("cal", &d, sizeof(d));
    if (d.valid) {
      touch_calibration_data = d;
      log_i("Touch calibration restored");
    }
  }
  p.end();
}

bool isActive() { return g_overlay != nullptr; }

void start() {
  if (g_overlay) return;
  g_backup = touch_calibration_data;
  touch_calibration_data.valid = false;  // capture raw points
  g_step = 0;

  // Portrait: logical coords == driver coords, no un-rotation math needed
  lv_display_set_rotation(lv_display_get_default(), LV_DISPLAY_ROTATION_0);

  g_overlay = lv_obj_create(lv_layer_top());
  lv_obj_set_size(g_overlay, PANEL_W, PANEL_H);
  lv_obj_set_pos(g_overlay, 0, 0);
  lv_obj_set_style_bg_color(g_overlay, ui::C(ui::COL_BG), 0);
  lv_obj_set_style_bg_opa(g_overlay, LV_OPA_COVER, 0);
  lv_obj_set_style_border_width(g_overlay, 0, 0);
  lv_obj_set_style_radius(g_overlay, 0, 0);
  lv_obj_remove_flag(g_overlay, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_flag(g_overlay, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(g_overlay, onOverlayPressed, LV_EVENT_CLICKED, nullptr);

  g_hint = ui::makeLabel(g_overlay, &font_cjk_20, ui::COL_TEXT, "1 / 3");
  lv_obj_align(g_hint, LV_ALIGN_CENTER, 0, -20);
  lv_obj_t* tip = ui::makeLabel(g_overlay, &font_cjk_16, ui::COL_TEXT_DIM, "撳十字");
  lv_obj_align(tip, LV_ALIGN_CENTER, 0, 8);

  g_cross = ui::makeLabel(g_overlay, &lv_font_montserrat_28, ui::COL_ETOLL, "+");
  showCross(0);
}

}  // namespace calibrate
