// Page 1: 過海隧道 — three cards (紅隧/東隧/西隧), both directions +
// current toll in a HKeToll (易通行) teal pill with next-change countdown.
#include "../../include/app_config.h"
#include "../model/hk_clock.h"
#include "../model/toll_engine.h"
#include "ui_internal.h"

namespace ui {
namespace {

struct TunnelCard {
  lv_obj_t* minutesHK2K;  // 港→九
  lv_obj_t* minutesK2HK;  // 九→港
  lv_obj_t* tollPill;
  lv_obj_t* tollLabel;
  lv_obj_t* tollNext;
};

TunnelCard g_cards[3];
// Card order on screen: 紅隧, 東隧, 西隧
const char* kNames[3] = {"紅隧", "東隧", "西隧"};
const toll::Crossing kCrossing[3] = {toll::Crossing::CHT, toll::Crossing::EHC,
                                     toll::Crossing::WHC};
// Slot registry: 1-3 = H2→CH/EH/WH (港→九), 4-6 = K03→CH/EH/WH (九→港)
const uint8_t kSlotHK2K[3] = {1, 2, 3};
const uint8_t kSlotK2HK[3] = {4, 5, 6};

}  // namespace

lv_obj_t* pageHarbourCreate(lv_obj_t* parent) {
  lv_obj_t* page = makeBox(parent);
  lv_obj_set_pos(page, 0, PAGE_Y);
  lv_obj_set_size(page, SCR_W, PAGE_H);

  for (int i = 0; i < 3; i++) {
    lv_obj_t* card = makeCard(page, 6, 2 + i * 62, SCR_W - 12, 58);
    TunnelCard& c = g_cards[i];

    lv_obj_t* name = makeLabel(card, &font_cjk_20, COL_TEXT, kNames[i]);
    lv_obj_align(name, LV_ALIGN_LEFT_MID, 10, 0);

    // 港→九 group
    lv_obj_t* lbl1 = makeLabel(card, &font_cjk_16, COL_TEXT_DIM, "港→九");
    lv_obj_set_pos(lbl1, 62, 5);
    c.minutesHK2K = makeLabel(card, &lv_font_montserrat_28, COL_TEXT_DIM, "--");
    lv_obj_set_pos(c.minutesHK2K, 62, 24);

    // 九→港 group
    lv_obj_t* lbl2 = makeLabel(card, &font_cjk_16, COL_TEXT_DIM, "九→港");
    lv_obj_set_pos(lbl2, 142, 5);
    c.minutesK2HK = makeLabel(card, &lv_font_montserrat_28, COL_TEXT_DIM, "--");
    lv_obj_set_pos(c.minutesK2HK, 142, 24);

    // HKeToll-style toll pill
    c.tollPill = lv_obj_create(card);
    lv_obj_set_size(c.tollPill, 78, 26);
    lv_obj_align(c.tollPill, LV_ALIGN_TOP_RIGHT, -8, 5);
    lv_obj_set_style_bg_color(c.tollPill, C(COL_ETOLL), 0);
    lv_obj_set_style_bg_opa(c.tollPill, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(c.tollPill, 0, 0);
    lv_obj_set_style_radius(c.tollPill, 13, 0);
    lv_obj_set_style_pad_all(c.tollPill, 0, 0);
    lv_obj_remove_flag(c.tollPill, LV_OBJ_FLAG_SCROLLABLE);

    c.tollLabel = makeLabel(c.tollPill, &lv_font_montserrat_20, 0xFFFFFF, "$--");
    lv_obj_center(c.tollLabel);

    c.tollNext = makeLabel(card, &font_cjk_16, COL_TEXT_DIM, "");
    lv_obj_align(c.tollNext, LV_ALIGN_BOTTOM_RIGHT, -8, -5);
  }
  return page;
}

void pageHarbourUpdate(const AppState& s, bool dim) {
  // Slot lookup table
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

  bool clockOk = hkclock::syncState() != hkclock::Sync::NEVER;
  hkclock::Local now = hkclock::now();
  bool sunPH = hkclock::sundayOrPH();

  for (int i = 0; i < 3; i++) {
    TunnelCard& c = g_cards[i];
    setMinutesLabel(c.minutesHK2K, mins[kSlotHK2K[i]], cols[kSlotHK2K[i]], dim);
    setMinutesLabel(c.minutesK2HK, mins[kSlotK2HK[i]], cols[kSlotK2HK[i]], dim);

    if (!clockOk) {
      lv_obj_set_style_bg_color(c.tollPill, C(COL_CARD_BORDER), 0);
      lv_label_set_text(c.tollLabel, "$--");
      lv_label_set_text(c.tollNext, "時鐘未同步");
      continue;
    }
    toll::Result r = toll::query(kCrossing[i], now.secOfDay, sunPH);
    lv_obj_set_style_bg_color(c.tollPill, C(COL_ETOLL), 0);
    lv_label_set_text_fmt(c.tollLabel, "$%d", r.dollars);
    if (r.next_change_sec >= 86400) {
      lv_label_set_text(c.tollNext, "");
    } else {
      uint32_t minsTo = (r.next_change_sec - now.secOfDay + 59) / 60;
      lv_label_set_text_fmt(c.tollNext, "%lu分後 $%d", (unsigned long)minsTo, r.next_dollars);
    }
  }
}

}  // namespace ui
