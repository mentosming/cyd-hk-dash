#include "pair_qr.h"

#include "../../include/app_config.h"
#include "../model/auth_token.h"
#include "ui_internal.h"

namespace ui {
namespace {

lv_obj_t* g_overlay = nullptr;

void build() {
  g_overlay = lv_obj_create(lv_layer_top());
  lv_obj_set_size(g_overlay, SCR_W, SCR_H);
  lv_obj_set_pos(g_overlay, 0, 0);
  lv_obj_set_style_bg_color(g_overlay, C(COL_BG), 0);
  lv_obj_set_style_bg_opa(g_overlay, LV_OPA_COVER, 0);
  lv_obj_set_style_border_width(g_overlay, 0, 0);
  lv_obj_set_style_radius(g_overlay, 0, 0);
  lv_obj_set_style_pad_all(g_overlay, 0, 0);
  lv_obj_remove_flag(g_overlay, LV_OBJ_FLAG_SCROLLABLE);

  lv_obj_t* title = makeLabel(g_overlay, &font_cjk_20, COL_TEXT, "手機掃描配對");
  lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 8);

  // White quiet zone behind the QR for reliable scanning
  lv_obj_t* frame = lv_obj_create(g_overlay);
  lv_obj_set_size(frame, 150, 150);
  lv_obj_align(frame, LV_ALIGN_CENTER, 0, 4);
  lv_obj_set_style_bg_color(frame, lv_color_white(), 0);
  lv_obj_set_style_border_width(frame, 0, 0);
  lv_obj_set_style_radius(frame, 6, 0);
  lv_obj_set_style_pad_all(frame, 6, 0);
  lv_obj_remove_flag(frame, LV_OBJ_FLAG_SCROLLABLE);

  lv_obj_t* qr = lv_qrcode_create(frame);
  lv_qrcode_set_size(qr, 138);
  lv_qrcode_set_dark_color(qr, lv_color_black());
  lv_qrcode_set_light_color(qr, lv_color_white());
  lv_obj_center(qr);
  String url = authtoken::pairUrl();
  lv_qrcode_update(qr, url.c_str(), url.length());

  lv_obj_t* hint = makeLabel(g_overlay, &font_cjk_16, COL_TEXT_DIM, "用相機App對住上面掃");
  lv_obj_align(hint, LV_ALIGN_BOTTOM_MID, 0, -6);
}

}  // namespace

void pairQRInit() {}

void pairQRUpdate(const AppState& s) {
  // Show the QR whenever not yet authorised so the user can always scan it to
  // pair; it hides automatically once the app presents a valid token.
  bool show = s.forceQR || (APP_TOKEN_REQUIRED && !s.authorized);
  if (show && g_overlay == nullptr) {
    build();
  } else if (!show && g_overlay != nullptr) {
    lv_obj_delete(g_overlay);
    g_overlay = nullptr;
  }
}

}  // namespace ui
