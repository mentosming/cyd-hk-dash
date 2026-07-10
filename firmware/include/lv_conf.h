/**
 * LVGL 9 configuration for CYD-DASH.
 * Partial override file — anything not defined here takes the LVGL default
 * (lv_conf_internal.h). Included via LV_CONF_PATH.
 */
#ifndef LV_CONF_H
#define LV_CONF_H

#define LV_COLOR_DEPTH 16

/* No PSRAM on the WROOM-32: keep the LVGL heap modest */
#define LV_MEM_SIZE (56 * 1024U)

#define LV_DEF_REFR_PERIOD 33

/* Fonts: Montserrat for digits/Latin, custom CJK subset compiled in src/ui/fonts */
#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_MONTSERRAT_28 1
#define LV_FONT_MONTSERRAT_40 1
#define LV_FONT_DEFAULT &lv_font_montserrat_14

/* Trim widgets we do not use */
#define LV_USE_ANIMIMG 0
#define LV_USE_CALENDAR 0
#define LV_USE_CANVAS 0
#define LV_USE_CHART 0
#define LV_USE_CHECKBOX 0
#define LV_USE_DROPDOWN 0
#define LV_USE_IMAGEBUTTON 0
#define LV_USE_KEYBOARD 0
#define LV_USE_LED 0
#define LV_USE_LIST 0
#define LV_USE_MENU 0
#define LV_USE_MSGBOX 0
#define LV_USE_ROLLER 0
#define LV_USE_SLIDER 0
#define LV_USE_SPINBOX 0
#define LV_USE_TABLE 0
#define LV_USE_TEXTAREA 0
#define LV_USE_TILEVIEW 0
#define LV_USE_WIN 0

#define LV_USE_THEME_DEFAULT 1
#define LV_THEME_DEFAULT_DARK 1

#define LV_USE_LOG 0

#endif /* LV_CONF_H */
