#pragma once

#define FW_MAJOR 0
#define FW_MINOR 2
#define PROTOCOL_VERSION 2

// BLE
#define BLE_DEVICE_NAME      "CYD-DASH"
// Bonding: writes require encryption; pairing PIN is shown on screen.
// Set to 0 to revert to open access (no re-pairing needed after flashing).
#define BLE_REQUIRE_BONDING 1
#define BLE_PASSKEY 924031
#define UUID_SERVICE   "9A3F0001-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
#define UUID_JOURNEY   "9A3F0002-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
#define UUID_TIMESYNC  "9A3F0003-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
#define UUID_METERS    "9A3F0004-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
#define UUID_COMMAND    "9A3F0005-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
#define UUID_STATUS     "9A3F0006-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
#define UUID_SLOTNAMES  "9A3F0008-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
#define UUID_FUELPRICES "9A3F0009-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
#define UUID_AUTH       "9A3F000A-6D2C-4C8A-9B4E-1F2E3D4C5B6A"

// App-layer pairing token: scan the on-screen QR (deep link) to enrol the app.
// Set to 0 to accept data writes without a token (open access).
#define APP_TOKEN_REQUIRED 1
#define PAIR_URL_SCHEME "cyddash"   // QR: cyddash://pair?t=<hex>&n=CYD-DASH

// Command opcodes (ESP -> phone)
#define CMD_METERS_REFRESH 0x01
#define CMD_JOURNEY_TICK   0x02
#define CMD_FULL_RESYNC    0x03
#define CMD_NEED_PAIR      0x04  // connection not authorised — app should show/scan QR

// Timings
#define JOURNEY_TICK_MS      (120 * 1000UL)
#define JOURNEY_STALE_S      (5 * 60)
#define JOURNEY_DEAD_S       (15 * 60)
#define METERS_TIMEOUT_MS    (15 * 1000UL)
#define CLOCK_NVS_SAVE_MS    (15 * 60 * 1000UL)

// Night dimming (HK local time, minutes since midnight)
#define NIGHT_START_MIN (19 * 60 + 30)
#define NIGHT_END_MIN   (7 * 60)
#define NIGHT_BACKLIGHT 0.25f
#define DAY_BACKLIGHT   1.0f
#define TOUCH_WAKE_MS   (30 * 1000UL)
// CYD LDR on GPIO34 (CDS): higher ADC reading = darker with the 0dB
// attenuation the library configures. Tune after in-car testing.
#define LDR_DARK_RAW    3200
