#pragma once
// Time-varying toll engine for the three harbour crossings (private cars).
// Pure logic, no Arduino deps — also compiled natively for unit tests.
// Schedule source of truth: docs/toll-schedule.md
#include <cstdint>

namespace toll {

enum class Crossing : uint8_t { WHC = 0, CHT = 1, EHC = 2 };

struct Result {
  uint8_t  dollars;          // current toll
  uint8_t  next_dollars;     // toll after the next change
  uint32_t next_change_sec;  // seconds-since-midnight of the next change (86400 if none today)
};

// secOfDay: HK local seconds since midnight [0, 86400)
// sundayOrPH: true = Sunday/public-holiday schedule
Result query(Crossing c, uint32_t secOfDay, bool sundayOrPH);

}  // namespace toll
