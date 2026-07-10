#pragma once
// Shared UI plumbing for the three pages. Dark automotive theme.
#include <lvgl.h>

#include "../model/app_state.h"

LV_FONT_DECLARE(font_cjk_16);
LV_FONT_DECLARE(font_cjk_20);

namespace ui {

// Palette
constexpr uint32_t COL_BG = 0x0B0F14;
constexpr uint32_t COL_CARD = 0x161D26;
constexpr uint32_t COL_CARD_BORDER = 0x232C38;
constexpr uint32_t COL_TEXT = 0xF2F5F8;
constexpr uint32_t COL_TEXT_DIM = 0x8A97A5;
constexpr uint32_t COL_GREEN = 0x34C759;
constexpr uint32_t COL_AMBER = 0xFFB020;
constexpr uint32_t COL_RED = 0xFF4D4F;
constexpr uint32_t COL_BLUE = 0x1788AD;   // HKeToll secondary blue
constexpr uint32_t COL_ETOLL = 0x18AD8E;  // 易通行 brand teal (from hketoll.gov.hk)
constexpr uint32_t COL_ETOLL_LT = 0x60C3B1;

// Layout
constexpr int SCR_W = 320, SCR_H = 240;
constexpr int HDR_H = 30, FTR_H = 34;  // footer is a big tappable tab bar
constexpr int PAGE_Y = HDR_H, PAGE_H = SCR_H - HDR_H - FTR_H;
constexpr int PAGE_COUNT = 4;

inline lv_color_t C(uint32_t c) { return lv_color_hex(c); }

// LVGL colour for TD COLOUR_ID (1 red, 2 amber, 3 green)
inline lv_color_t tdColour(uint8_t id) {
  switch (id) {
    case 1: return C(COL_RED);
    case 2: return C(COL_AMBER);
    case 3: return C(COL_GREEN);
    default: return C(COL_TEXT);
  }
}

// Plain container: no border/padding/scroll, transparent by default
lv_obj_t* makeBox(lv_obj_t* parent);
// Rounded card
lv_obj_t* makeCard(lv_obj_t* parent, int x, int y, int w, int h);
lv_obj_t* makeLabel(lv_obj_t* parent, const lv_font_t* font, uint32_t colour, const char* text);

// Renders a journey minutes value + colour into a big-number label
// (handles the 0xFF/0xFE/0xFD sentinels), dimming when stale.
void setMinutesLabel(lv_obj_t* label, uint8_t minutes, uint8_t colour, bool dim,
                     const lv_font_t* bigFont = &lv_font_montserrat_28);

// Trend arrow vs the previous capture: sets "↑" (red) / "↓" (green) or hides.
void setTrendArrow(lv_obj_t* label, uint8_t nowMin, uint8_t prevMin);

// Pages: each creates its container (hidden) and exposes an update fn.
lv_obj_t* pageHarbourCreate(lv_obj_t* parent);
void pageHarbourUpdate(const AppState& s, bool dim);
lv_obj_t* pageRoutesCreate(lv_obj_t* parent);
void pageRoutesUpdate(const AppState& s, bool dim);
lv_obj_t* pageMetersCreate(lv_obj_t* parent);
void pageMetersUpdate(const AppState& s);
lv_obj_t* pageFuelCreate(lv_obj_t* parent);
void pageFuelUpdate(const AppState& s);

}  // namespace ui
