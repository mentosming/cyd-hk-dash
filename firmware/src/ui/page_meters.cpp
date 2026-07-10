// Page 3: 附近咪錶 — 掃一掃 button + list of the nearest streets that HAVE
// vacant meters (Chinese street names; the phone searches up to 4 km).
#include "../../include/app_config.h"
#include "../ble/gatt_server.h"
#include "ui_internal.h"

namespace ui {
namespace {

constexpr int NROWS = 4;

lv_obj_t* g_btn;
lv_obj_t* g_btnLabel;
lv_obj_t* g_status;
lv_obj_t* g_rows[NROWS];
lv_obj_t* g_rowName[NROWS];
lv_obj_t* g_rowDist[NROWS];
lv_obj_t* g_rowLPP[NROWS];
lv_obj_t* g_rowVacant[NROWS];
lv_obj_t* g_rowTotal[NROWS];

void markPending(AppState& s) {
  s.metersPending = true;
  s.metersRequestMs = millis();
  s.metersDirty = true;
}

void onScanTap(lv_event_t*) {
  appstate::with(markPending);
  ble::notifyCommand(CMD_METERS_REFRESH);
}

}  // namespace

lv_obj_t* pageMetersCreate(lv_obj_t* parent) {
  lv_obj_t* page = makeBox(parent);
  lv_obj_set_pos(page, 0, PAGE_Y);
  lv_obj_set_size(page, SCR_W, PAGE_H);
  lv_obj_add_flag(page, LV_OBJ_FLAG_HIDDEN);

  // 掃一掃 (left) + status text (right)
  g_btn = lv_button_create(page);
  lv_obj_set_pos(g_btn, 6, 2);
  lv_obj_set_size(g_btn, 132, 36);
  lv_obj_set_style_bg_color(g_btn, C(COL_ETOLL), 0);
  lv_obj_set_style_bg_color(g_btn, C(0x0F8A70), LV_STATE_PRESSED);
  lv_obj_set_style_radius(g_btn, 18, 0);
  lv_obj_set_style_shadow_width(g_btn, 0, 0);
  lv_obj_add_event_cb(g_btn, onScanTap, LV_EVENT_CLICKED, nullptr);

  g_btnLabel = makeLabel(g_btn, &font_cjk_20, 0xFFFFFF, "掃一掃");
  lv_obj_center(g_btnLabel);

  g_status = makeLabel(page, &font_cjk_16, COL_TEXT_DIM, "撳掣搜尋空位");
  lv_obj_align(g_status, LV_ALIGN_TOP_RIGHT, -8, 12);

  // Street rows
  for (int i = 0; i < NROWS; i++) {
    g_rows[i] = makeCard(page, 6, 44 + i * 33, SCR_W - 12, 31);
    lv_obj_add_flag(g_rows[i], LV_OBJ_FLAG_HIDDEN);

    g_rowName[i] = makeLabel(g_rows[i], &font_cjk_16, COL_TEXT, "");
    lv_obj_align(g_rowName[i], LV_ALIGN_LEFT_MID, 8, 0);
    lv_obj_set_width(g_rowName[i], 122);
    lv_label_set_long_mode(g_rowName[i], LV_LABEL_LONG_DOT);

    g_rowDist[i] = makeLabel(g_rows[i], &font_cjk_16, COL_TEXT_DIM, "");
    lv_obj_align(g_rowDist[i], LV_ALIGN_RIGHT_MID, -108, 0);

    g_rowLPP[i] = makeLabel(g_rows[i], &font_cjk_16, COL_TEXT_DIM, "");
    lv_obj_align(g_rowLPP[i], LV_ALIGN_RIGHT_MID, -58, 0);

    g_rowVacant[i] = makeLabel(g_rows[i], &lv_font_montserrat_20, COL_GREEN, "");
    lv_obj_align(g_rowVacant[i], LV_ALIGN_RIGHT_MID, -30, 0);

    g_rowTotal[i] = makeLabel(g_rows[i], &font_cjk_16, COL_TEXT_DIM, "");
    lv_obj_align(g_rowTotal[i], LV_ALIGN_RIGHT_MID, -6, 1);
  }
  return page;
}

void pageMetersUpdate(const AppState& s) {
  if (s.metersPending) {
    lv_label_set_text(g_btnLabel, "搜尋中");
    lv_obj_add_state(g_btn, LV_STATE_DISABLED);
  } else {
    lv_label_set_text(g_btnLabel, "掃一掃");
    lv_obj_remove_state(g_btn, LV_STATE_DISABLED);
  }

  if (s.metersReceivedMs == 0) {
    lv_label_set_text(g_status, s.metersPending ? "搜尋中..." : "撳掣搜尋空位");
    for (int i = 0; i < NROWS; i++) lv_obj_add_flag(g_rows[i], LV_OBJ_FLAG_HIDDEN);
    return;
  }

  const proto::Meters& m = s.meters;
  uint32_t ageMin = (millis() - s.metersReceivedMs) / 60000;
  bool showRows = (m.status == 0 || m.status == 4) && m.count > 0;
  switch (m.status) {
    case 0: lv_label_set_text_fmt(g_status, "更新 %lu分前", (unsigned long)ageMin); break;
    case 1: lv_label_set_text(g_status, "手機定位失敗"); break;
    case 2: lv_label_set_text(g_status, "讀取錯誤"); break;
    case 4: lv_label_set_text(g_status, "4000米內冇空位"); break;
    default: lv_label_set_text(g_status, "附近冇咪錶"); break;
  }

  for (int i = 0; i < NROWS; i++) {
    if (showRows && i < m.count) {
      const proto::MeterGroup& g = m.groups[i];
      lv_obj_remove_flag(g_rows[i], LV_OBJ_FLAG_HIDDEN);
      lv_label_set_text(g_rowName[i], g.name);
      lv_label_set_text_fmt(g_rowDist[i], "%u米", (unsigned)g.dist_m);
      if (g.lpp > 0)
        lv_label_set_text_fmt(g_rowLPP[i], "%u分", (unsigned)g.lpp);
      else
        lv_label_set_text(g_rowLPP[i], "");
      lv_label_set_text_fmt(g_rowVacant[i], "%u", (unsigned)g.vacant);
      lv_label_set_text_fmt(g_rowTotal[i], "/%u", (unsigned)g.total);
      lv_obj_set_style_text_color(g_rowVacant[i], C(g.vacant == 0 ? COL_RED : COL_GREEN), 0);
      lv_obj_align(g_rowVacant[i], LV_ALIGN_RIGHT_MID, -30, 0);
      lv_obj_align(g_rowDist[i], LV_ALIGN_RIGHT_MID, -108, 0);
      lv_obj_align(g_rowLPP[i], LV_ALIGN_RIGHT_MID, -58, 0);
    } else {
      lv_obj_add_flag(g_rows[i], LV_OBJ_FLAG_HIDDEN);
    }
  }
}

}  // namespace ui
