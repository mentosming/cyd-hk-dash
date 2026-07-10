#include "ui.h"

#include <esp32_smartdisplay.h>

#include "../../include/app_config.h"
#include "../ble/gatt_server.h"
#include "../model/hk_clock.h"
#include "calibrate.h"
#include "pair_qr.h"
#include "ui_internal.h"

namespace ui {
namespace {

lv_obj_t* g_pages[PAGE_COUNT];
lv_obj_t* g_tabs[PAGE_COUNT];
lv_obj_t* g_tabLabels[PAGE_COUNT];
lv_obj_t* g_lblTitle;
lv_obj_t* g_lblClock;
lv_obj_t* g_btDot;
lv_obj_t* g_lblUpdated;
int g_page = 0;

const char* kPageTitles[PAGE_COUNT] = {"過海隧道", "主要幹道", "附近咪錶", "油價"};
const char* kTabLabels[PAGE_COUNT] = {"過海", "幹道", "咪錶", "油價"};

void showPage(int idx) {
  g_page = (idx + PAGE_COUNT) % PAGE_COUNT;
  for (int i = 0; i < PAGE_COUNT; i++) {
    if (i == g_page)
      lv_obj_remove_flag(g_pages[i], LV_OBJ_FLAG_HIDDEN);
    else
      lv_obj_add_flag(g_pages[i], LV_OBJ_FLAG_HIDDEN);
    bool active = (i == g_page);
    lv_obj_set_style_bg_color(g_tabs[i], C(active ? COL_ETOLL : COL_CARD), 0);
    lv_obj_set_style_text_color(g_tabLabels[i], C(active ? 0xFFFFFF : COL_TEXT_DIM), 0);
  }
  lv_label_set_text(g_lblTitle, kPageTitles[g_page]);
}

void onGesture(lv_event_t* e) {
  lv_dir_t dir = lv_indev_get_gesture_dir(lv_indev_active());
  if (dir == LV_DIR_LEFT) showPage(g_page + 1);
  else if (dir == LV_DIR_RIGHT) showPage(g_page - 1);
}

void onTitleTap(lv_event_t*) { showPage(g_page + 1); }

void onTitleLongPress(lv_event_t*) { calibrate::start(); }

// Long-press the clock: forget all BLE bonds + regenerate token (full reset)
void onClockLongPress(lv_event_t*) {
  ble::clearBonds();
}

// Tap the BT dot toggles the pairing QR overlay (manual enrol / re-scan)
void onBtDotTap(lv_event_t*) {
  appstate::with([](AppState& s) {
    s.forceQR = !s.forceQR;
    s.linkDirty = true;
  });
}

// Pairing PIN modal, driven by AppState.showPasskey
lv_obj_t* g_pinOverlay = nullptr;

void updatePasskeyOverlay(uint32_t passkey) {
  if (passkey != 0 && g_pinOverlay == nullptr) {
    g_pinOverlay = lv_obj_create(lv_layer_top());
    lv_obj_set_size(g_pinOverlay, 240, 110);
    lv_obj_center(g_pinOverlay);
    lv_obj_set_style_bg_color(g_pinOverlay, C(COL_CARD), 0);
    lv_obj_set_style_border_color(g_pinOverlay, C(COL_ETOLL), 0);
    lv_obj_set_style_border_width(g_pinOverlay, 2, 0);
    lv_obj_set_style_radius(g_pinOverlay, 12, 0);
    lv_obj_remove_flag(g_pinOverlay, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t* title = makeLabel(g_pinOverlay, &font_cjk_16, COL_TEXT_DIM, "藍牙 PIN");
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 4);
    lv_obj_t* pin = makeLabel(g_pinOverlay, &lv_font_montserrat_40, COL_ETOLL, "");
    lv_label_set_text_fmt(pin, "%06lu", (unsigned long)passkey);
    lv_obj_align(pin, LV_ALIGN_BOTTOM_MID, 0, -10);
  } else if (passkey == 0 && g_pinOverlay != nullptr) {
    lv_obj_delete(g_pinOverlay);
    g_pinOverlay = nullptr;
  }
}

void onTabTap(lv_event_t* e) {
  intptr_t idx = (intptr_t)lv_event_get_user_data(e);
  showPage((int)idx);
}

}  // namespace

lv_obj_t* makeBox(lv_obj_t* parent) {
  lv_obj_t* o = lv_obj_create(parent);
  lv_obj_set_style_bg_opa(o, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(o, 0, 0);
  lv_obj_set_style_pad_all(o, 0, 0);
  lv_obj_set_style_radius(o, 0, 0);
  lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE);
  return o;
}

lv_obj_t* makeCard(lv_obj_t* parent, int x, int y, int w, int h) {
  lv_obj_t* o = lv_obj_create(parent);
  lv_obj_set_pos(o, x, y);
  lv_obj_set_size(o, w, h);
  lv_obj_set_style_bg_color(o, C(COL_CARD), 0);
  lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(o, C(COL_CARD_BORDER), 0);
  lv_obj_set_style_border_width(o, 1, 0);
  lv_obj_set_style_radius(o, 10, 0);
  lv_obj_set_style_pad_all(o, 0, 0);
  lv_obj_remove_flag(o, LV_OBJ_FLAG_SCROLLABLE);
  return o;
}

lv_obj_t* makeLabel(lv_obj_t* parent, const lv_font_t* font, uint32_t colour, const char* text) {
  lv_obj_t* l = lv_label_create(parent);
  lv_obj_set_style_text_font(l, font, 0);
  lv_obj_set_style_text_color(l, C(colour), 0);
  lv_label_set_text(l, text);
  return l;
}

void setTrendArrow(lv_obj_t* label, uint8_t nowMin, uint8_t prevMin) {
  // Only meaningful when both captures carry real minutes
  if (nowMin >= proto::kMinutesClosed || prevMin >= proto::kMinutesClosed || prevMin == 0) {
    lv_label_set_text(label, "");
    return;
  }
  int delta = (int)nowMin - (int)prevMin;
  if (delta >= 2) {
    lv_label_set_text(label, "↑");
    lv_obj_set_style_text_color(label, C(COL_RED), 0);
  } else if (delta <= -2) {
    lv_label_set_text(label, "↓");
    lv_obj_set_style_text_color(label, C(COL_GREEN), 0);
  } else {
    lv_label_set_text(label, "");
  }
}

void setMinutesLabel(lv_obj_t* label, uint8_t minutes, uint8_t colour, bool dim,
                     const lv_font_t* bigFont) {
  const lv_font_t* big = bigFont;
  switch (minutes) {
    case proto::kMinutesNA:
      lv_obj_set_style_text_font(label, big, 0);
      lv_label_set_text(label, "--");
      lv_obj_set_style_text_color(label, C(COL_TEXT_DIM), 0);
      return;
    case proto::kMinutesCongestion:
      lv_obj_set_style_text_font(label, &font_cjk_20, 0);
      lv_label_set_text(label, "擠塞");
      lv_obj_set_style_text_color(label, C(COL_RED), 0);
      return;
    case proto::kMinutesClosed:
      lv_obj_set_style_text_font(label, &font_cjk_20, 0);
      lv_label_set_text(label, "封閉");
      lv_obj_set_style_text_color(label, C(COL_RED), 0);
      return;
    default: {
      lv_obj_set_style_text_font(label, big, 0);
      lv_label_set_text_fmt(label, "%d", minutes);
      lv_obj_set_style_text_color(label, dim ? C(COL_TEXT_DIM) : tdColour(colour), 0);
    }
  }
}

void init() {
  lv_obj_t* scr = lv_screen_active();
  lv_obj_set_style_bg_color(scr, C(COL_BG), 0);
  lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);

  // ---- Header ----
  lv_obj_t* hdr = makeBox(scr);
  lv_obj_set_pos(hdr, 0, 0);
  lv_obj_set_size(hdr, SCR_W, HDR_H);

  // 易通行-style teal accent strip on the left of the title
  lv_obj_t* accent = lv_obj_create(hdr);
  lv_obj_set_pos(accent, 8, 7);
  lv_obj_set_size(accent, 4, 18);
  lv_obj_set_style_bg_color(accent, C(COL_ETOLL), 0);
  lv_obj_set_style_bg_opa(accent, LV_OPA_COVER, 0);
  lv_obj_set_style_border_width(accent, 0, 0);
  lv_obj_set_style_radius(accent, 2, 0);

  g_lblTitle = makeLabel(hdr, &font_cjk_20, COL_TEXT, kPageTitles[0]);
  lv_obj_align(g_lblTitle, LV_ALIGN_LEFT_MID, 20, 0);
  lv_obj_add_flag(g_lblTitle, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(g_lblTitle, onTitleTap, LV_EVENT_CLICKED, nullptr);
  lv_obj_add_event_cb(g_lblTitle, onTitleLongPress, LV_EVENT_LONG_PRESSED, nullptr);

  g_lblClock = makeLabel(hdr, &lv_font_montserrat_20, COL_TEXT, "--:--");
  lv_obj_align(g_lblClock, LV_ALIGN_RIGHT_MID, -26, 0);
  lv_obj_add_flag(g_lblClock, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(g_lblClock, onClockLongPress, LV_EVENT_LONG_PRESSED, nullptr);

  // updated-age text, centred in the header
  g_lblUpdated = makeLabel(hdr, &font_cjk_16, COL_TEXT_DIM, "等待數據");
  lv_obj_align(g_lblUpdated, LV_ALIGN_CENTER, 10, 0);

  g_btDot = lv_obj_create(hdr);
  lv_obj_set_size(g_btDot, 10, 10);
  lv_obj_align(g_btDot, LV_ALIGN_RIGHT_MID, -8, 0);
  lv_obj_set_style_radius(g_btDot, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_border_width(g_btDot, 0, 0);
  lv_obj_set_style_bg_color(g_btDot, C(COL_TEXT_DIM), 0);
  lv_obj_set_style_bg_opa(g_btDot, LV_OPA_COVER, 0);
  // Enlarge the tap target and let it toggle the pairing QR
  lv_obj_set_ext_click_area(g_btDot, 16);
  lv_obj_add_flag(g_btDot, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_add_event_cb(g_btDot, onBtDotTap, LV_EVENT_CLICKED, nullptr);

  // ---- Pages ----
  g_pages[0] = pageHarbourCreate(scr);
  g_pages[1] = pageRoutesCreate(scr);
  g_pages[2] = pageMetersCreate(scr);
  g_pages[3] = pageFuelCreate(scr);

  // ---- Footer: big tappable tab bar (reliable target for resistive touch) ----
  lv_obj_t* ftr = makeBox(scr);
  lv_obj_set_pos(ftr, 0, SCR_H - FTR_H);
  lv_obj_set_size(ftr, SCR_W, FTR_H);

  const int gap = 4;
  const int tabW = (SCR_W - gap * (PAGE_COUNT + 1)) / PAGE_COUNT;
  for (int i = 0; i < PAGE_COUNT; i++) {
    g_tabs[i] = lv_obj_create(ftr);
    lv_obj_set_size(g_tabs[i], tabW, FTR_H - 4);
    lv_obj_set_pos(g_tabs[i], gap + i * (tabW + gap), 2);
    lv_obj_set_style_bg_color(g_tabs[i], C(COL_CARD), 0);
    lv_obj_set_style_bg_opa(g_tabs[i], LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(g_tabs[i], 0, 0);
    lv_obj_set_style_radius(g_tabs[i], 8, 0);
    lv_obj_set_style_pad_all(g_tabs[i], 0, 0);
    lv_obj_remove_flag(g_tabs[i], LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(g_tabs[i], LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(g_tabs[i], onTabTap, LV_EVENT_CLICKED, (void*)(intptr_t)i);

    g_tabLabels[i] = makeLabel(g_tabs[i], &font_cjk_20, COL_TEXT_DIM, kTabLabels[i]);
    lv_obj_center(g_tabLabels[i]);
  }

  lv_obj_add_event_cb(scr, onGesture, LV_EVENT_GESTURE, nullptr);
  showPage(0);
}

void tick(const AppState& s) {
  // Clock
  if (hkclock::syncState() != hkclock::Sync::NEVER) {
    hkclock::Local t = hkclock::now();
    lv_label_set_text_fmt(g_lblClock, "%02d:%02d", t.hour, t.min);
  } else {
    lv_label_set_text(g_lblClock, "--:--");
  }

  // Link state — conveyed by the header BT dot colour
  // teal = authorised, amber = connected/pairing, grey = idle
  lv_obj_set_style_bg_color(
      g_btDot, C(s.authorized ? COL_ETOLL : (s.connected ? COL_AMBER : COL_TEXT_DIM)), 0);

  pairQRUpdate(s);

  // Journey staleness
  bool haveJourney = s.journeyReceivedMs != 0;
  uint32_t ageS = haveJourney ? (millis() - s.journeyReceivedMs) / 1000 : 0;
  bool dim = haveJourney && ageS > JOURNEY_DEAD_S;
  if (!haveJourney) {
    lv_label_set_text(g_lblUpdated, "等待數據");
    lv_obj_set_style_text_color(g_lblUpdated, C(COL_TEXT_DIM), 0);
  } else {
    lv_label_set_text_fmt(g_lblUpdated, "更新 %lu分前", (unsigned long)(ageS / 60));
    lv_obj_set_style_text_color(
        g_lblUpdated, C(ageS > JOURNEY_STALE_S ? (uint32_t)COL_AMBER : (uint32_t)COL_TEXT_DIM), 0);
  }

  updatePasskeyOverlay(s.showPasskey);

  pageHarbourUpdate(s, dim);
  pageRoutesUpdate(s, dim);
  pageMetersUpdate(s);
  pageFuelUpdate(s);
}

}  // namespace ui
