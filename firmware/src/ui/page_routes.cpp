// Page 2: 主要幹道 — 獅隧 / 大老山 / 青沙, big minutes.
#include "ui_internal.h"

namespace ui {
namespace {

lv_obj_t* g_minutes[3];
const char* kNames[3] = {"獅隧", "大老山", "青沙"};
const char* kSubtitle = "往九龍";
// Slot registry: 7 = SJ1→LRT, 8 = SJ2→TCT, 9 = SJ2→TSCA
const uint8_t kSlots[3] = {7, 8, 9};

}  // namespace

lv_obj_t* pageRoutesCreate(lv_obj_t* parent) {
  lv_obj_t* page = makeBox(parent);
  lv_obj_set_pos(page, 0, PAGE_Y);
  lv_obj_set_size(page, SCR_W, PAGE_H);

  for (int i = 0; i < 3; i++) {
    lv_obj_t* card = makeCard(page, 6, 2 + i * 62, SCR_W - 12, 58);

    lv_obj_t* name = makeLabel(card, &font_cjk_20, COL_TEXT, kNames[i]);
    lv_obj_set_pos(name, 10, 8);
    lv_obj_t* sub = makeLabel(card, &font_cjk_16, COL_TEXT_DIM, kSubtitle);
    lv_obj_set_pos(sub, 10, 34);

    lv_obj_t* suffix = makeLabel(card, &font_cjk_16, COL_TEXT_DIM, "分鐘");
    lv_obj_align(suffix, LV_ALIGN_RIGHT_MID, -10, 8);

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
    setMinutesLabel(g_minutes[i], mins[kSlots[i]], cols[kSlots[i]], dim, &lv_font_montserrat_40);
    // Keep the number right-anchored as its width changes
    lv_obj_align(g_minutes[i], LV_ALIGN_RIGHT_MID, -50, 0);
  }
}

}  // namespace ui
