#include "auth_token.h"

#include <Preferences.h>
#include <esp_random.h>

#include "../../include/app_config.h"

namespace authtoken {
namespace {

uint8_t g_token[kLen];

void generate() {
  for (size_t i = 0; i < kLen; i += 4) {
    uint32_t r = esp_random();
    memcpy(g_token + i, &r, 4);
  }
}

void save() {
  Preferences p;
  p.begin("auth", false);
  p.putBytes("token", g_token, kLen);
  p.end();
}

}  // namespace

void begin() {
  Preferences p;
  p.begin("auth", false);
  if (p.getBytesLength("token") == kLen) {
    p.getBytes("token", g_token, kLen);
    p.end();
  } else {
    p.end();
    generate();
    save();
    log_i("Auth token generated");
  }
}

const uint8_t* bytes() { return g_token; }

bool matches(const uint8_t* d, size_t len) {
  if (len != kLen) return false;
  // constant-time compare
  uint8_t diff = 0;
  for (size_t i = 0; i < kLen; i++) diff |= d[i] ^ g_token[i];
  return diff == 0;
}

String hex() {
  static const char* kHex = "0123456789abcdef";
  String s;
  s.reserve(kLen * 2);
  for (size_t i = 0; i < kLen; i++) {
    s += kHex[g_token[i] >> 4];
    s += kHex[g_token[i] & 0x0F];
  }
  return s;
}

String pairUrl() {
  return String(PAIR_URL_SCHEME) + "://pair?t=" + hex() + "&n=" + BLE_DEVICE_NAME;
}

void regenerate() {
  generate();
  save();
  log_w("Auth token regenerated");
}

}  // namespace authtoken
