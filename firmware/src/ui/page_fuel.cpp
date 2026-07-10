// Page 4: 油價 — Consumer Council list pump prices, 5 brands × 3 fuel types.
// Cheapest price per column highlighted in HKeToll teal.
#include "../model/hk_clock.h"
#include "ui_internal.h"

namespace ui {
namespace {

const char* kBrands[proto::kFuelBrands] = {"中石化", "中國石油", "加德士", "埃索", "蜆殼"};
const char* kTypes[proto::kFuelTypes] = {"無鉛", "特級", "柴油"};

lv_obj_t* g_price[proto::kFuelBrands][proto::kFuelTypes];
lv_obj_t* g_updated;

constexpr int NAME_W = 76;
constexpr int COL_W = (SCR_W - NAME_W - 12) / proto::kFuelTypes;  // ~77

}  // namespace

lv_obj_t* pageFuelCreate(lv_obj_t* parent) {
  lv_obj_t* page = makeBox(parent);
  lv_obj_set_pos(page, 0, PAGE_Y);
  lv_obj_set_size(page, SCR_W, PAGE_H);
  lv_obj_add_flag(page, LV_OBJ_FLAG_HIDDEN);

  // Column headers
  for (int t = 0; t < proto::kFuelTypes; t++) {
    lv_obj_t* hdr = makeLabel(page, &font_cjk_16, COL_TEXT_DIM, kTypes[t]);
    lv_obj_set_pos(hdr, NAME_W + 6 + t * COL_W + 14, 2);
  }
  g_updated = makeLabel(page, &font_cjk_16, COL_TEXT_DIM, "無數據");
  lv_obj_set_pos(g_updated, 8, 2);

  // Brand rows
  for (int b = 0; b < proto::kFuelBrands; b++) {
    lv_obj_t* row = makeCard(page, 6, 22 + b * 31, SCR_W - 12, 29);
    lv_obj_t* name = makeLabel(row, &font_cjk_16, COL_TEXT, kBrands[b]);
    lv_obj_align(name, LV_ALIGN_LEFT_MID, 6, 0);
    for (int t = 0; t < proto::kFuelTypes; t++) {
      g_price[b][t] = makeLabel(row, &lv_font_montserrat_14, COL_TEXT_DIM, "--");
      lv_obj_align(g_price[b][t], LV_ALIGN_LEFT_MID, NAME_W + t * COL_W + 8, 0);
    }
  }
  return page;
}

void pageFuelUpdate(const AppState& s) {
  if (s.fuelReceivedMs == 0) {
    lv_label_set_text(g_updated, "無數據");
    return;
  }

  // Data age from the fetch epoch (works across reboots once clock is synced)
  uint32_t nowEpoch = hkclock::epochUtc();
  if (nowEpoch > s.fuel.fetch_epoch && s.fuel.fetch_epoch > 0) {
    uint32_t ageH = (nowEpoch - s.fuel.fetch_epoch) / 3600;
    if (ageH == 0)
      lv_label_set_text(g_updated, "今日");
    else
      lv_label_set_text_fmt(g_updated, "%lu時前", (unsigned long)ageH);
  } else {
    lv_label_set_text(g_updated, "");
  }

  // Cheapest per fuel type
  uint16_t cheapest[proto::kFuelTypes];
  for (int t = 0; t < proto::kFuelTypes; t++) {
    cheapest[t] = proto::kFuelNA;
    for (int b = 0; b < proto::kFuelBrands; b++) {
      if (s.fuel.cents[b][t] < cheapest[t]) cheapest[t] = s.fuel.cents[b][t];
    }
  }

  for (int b = 0; b < proto::kFuelBrands; b++) {
    for (int t = 0; t < proto::kFuelTypes; t++) {
      uint16_t c = s.fuel.cents[b][t];
      if (c == proto::kFuelNA) {
        lv_label_set_text(g_price[b][t], "--");
        lv_obj_set_style_text_color(g_price[b][t], C(COL_TEXT_DIM), 0);
      } else {
        lv_label_set_text_fmt(g_price[b][t], "$%u.%02u", c / 100, c % 100);
        bool best = (c == cheapest[t]);
        lv_obj_set_style_text_color(g_price[b][t], C(best ? COL_ETOLL : COL_TEXT), 0);
      }
    }
  }
}

}  // namespace ui
