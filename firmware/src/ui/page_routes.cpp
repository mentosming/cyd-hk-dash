// Page 2: 主要幹道 — slots 7-9, big minutes. Route names are configurable
// from the phone (SlotNames payload, persisted in NVS).
#include "ui_internal.h"

namespace ui {
namespace {

lv_obj_t* g_names[3];
lv_obj_t* g_minutes[3];
lv_obj_t* g_arrows[3];
const char* kDefaultNames[3] = {"獅隧", "大老山", "青沙"};
const char* kSubtitle = "往九龍";
const uint8_t kSlots[3] = {7, 8, 9};

}  // namespace

lv_obj_t* pageRoutesCreate(lv_obj_t* parent) {
  lv_obj_t* page = makeBox(parent);
  lv_obj_set_pos(page, 0, PAGE_Y);
  lv_obj_set_size(page, SCR_W, PAGE_H);
  lv_obj_add_flag(page, LV_OBJ_FLAG_HIDDEN);

  for (int i = 0; i < 3; i++) {
    lv_obj_t* card = makeCard(page, 6, 2 + i * 58, SCR_W - 12, 54);

    g_names[i] = makeLabel(card, &font_cjk_20, COL_TEXT, kDefaultNames[i]);
    lv_obj_set_pos(g_names[i], 10, 6);
    lv_obj_set_width(g_names[i], 170);
    lv_label_set_long_mode(g_names[i], LV_LABEL_LONG_DOT);
    lv_obj_t* sub = makeLabel(card, &font_cjk_16, COL_TEXT_DIM, kSubtitle);
    lv_obj_set_pos(sub, 10, 32);

    lv_obj_t* suffix = makeLabel(card, &font_cjk_16, COL_TEXT_DIM, "分鐘");
    lv_obj_align(suffix, LV_ALIGN_RIGHT_MID, -10, 8);

    g_arrows[i] = makeLabel(card, &font_cjk_16, COL_TEXT_DIM, "");
    lv_obj_align(g_arrows[i], LV_ALIGN_RIGHT_MID, -10, -12);

    g_minutes[i] = makeLabel(card, &lv_font_montserrat_40, COL_TEXT_DIM, "--");
    lv_obj_align(g_minutes[i], LV_ALIGN_RIGHT_MID, -50, 0);
  }
  return page;
}

void pageRoutesUpdate(const AppState& s, bool dim) {
  uint8_t mins[proto::kMaxSlots + 1];
  uint8_t cols[proto::kMaxSlots + 1];
  memset(mins, proto::kMinutesNA, sizeof(mins));
  memset(cols, 0, sizeof(cols));
  if (s.journeyReceivedMs != 0) {
    for (uint8_t i = 0; i < s.journey.count; i++) {
      mins[s.journey.entries[i].slot] = s.journey.entries[i].minutes;
      cols[s.journey.entries[i].slot] = s.journey.entries[i].colour;
    }
  }
  for (int i = 0; i < 3; i++) {
    uint8_t slot = kSlots[i];
    if (s.slotNames[slot][0] != '\0') {
      lv_label_set_text(g_names[i], s.slotNames[slot]);
    }
    setMinutesLabel(g_minutes[i], mins[slot], cols[slot], dim, &lv_font_montserrat_40);
    setTrendArrow(g_arrows[i], mins[slot], s.prevMinutes[slot]);
    lv_obj_align(g_minutes[i], LV_ALIGN_RIGHT_MID, -50, 0);
  }
}

}  // namespace ui
