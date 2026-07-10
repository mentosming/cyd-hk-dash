#pragma once
// App-layer pairing token. A random 8-byte secret generated on first boot and
// persisted to NVS. Shown on screen as a QR deep link; the phone reads it and
// writes it back over the Auth characteristic to authorise data writes.
#include <Arduino.h>

namespace authtoken {

constexpr size_t kLen = 8;

void begin();                                   // load or generate + persist
const uint8_t* bytes();                         // kLen bytes
bool matches(const uint8_t* d, size_t len);
String hex();                                   // 16 lowercase hex chars
String pairUrl();                               // cyddash://pair?t=<hex>&n=CYD-DASH
void regenerate();                              // new token (invalidates all apps)

}  // namespace authtoken
