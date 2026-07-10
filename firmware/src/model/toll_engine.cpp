#include "toll_engine.h"

#include <cstddef>

namespace toll {
namespace {

// toll(t) = v0 + dir * 2 * floor((t - from) / 120), dir=0 => plateau
struct Seg {
  uint32_t from;  // inclusive, sec of day
  uint32_t to;    // exclusive
  uint8_t v0;
  int8_t dir;
};

constexpr uint32_t S(uint32_t h, uint32_t m, uint32_t s = 0) { return h * 3600 + m * 60 + s; }

// WHC 西隧, Mon-Sat excl. PH
constexpr Seg kProfileW[] = {
    {S(0, 0),   S(7, 30),  20, 0},
    {S(7, 30),  S(8, 8),   22, +1},  // -> $58
    {S(8, 8),   S(10, 15), 60, 0},
    {S(10, 15), S(10, 43), 58, -1},  // -> $32
    {S(10, 43), S(16, 30), 30, 0},
    {S(16, 30), S(16, 58), 32, +1},  // -> $58
    {S(16, 58), S(19, 0),  60, 0},
    {S(19, 0),  S(19, 38), 58, -1},  // -> $22
    {S(19, 38), 86400,     20, 0},
};

// CHT 紅隧 & EHC 東隧, Mon-Sat excl. PH
constexpr Seg kProfileC[] = {
    {S(0, 0),   S(7, 30),  20, 0},
    {S(7, 30),  S(7, 48),  22, +1},  // -> $38
    {S(7, 48),  S(10, 15), 40, 0},
    {S(10, 15), S(10, 23), 38, -1},  // -> $32
    {S(10, 23), S(16, 30), 30, 0},
    {S(16, 30), S(16, 38), 32, +1},  // -> $38
    {S(16, 38), S(19, 0),  40, 0},
    {S(19, 0),  S(19, 18), 38, -1},  // -> $22
    {S(19, 18), 86400,     20, 0},
};

// Sundays & public holidays, all three crossings
constexpr Seg kProfileS[] = {
    {S(0, 0),   S(10, 11), 20, 0},
    {S(10, 11), S(10, 13), 21, 0},
    {S(10, 13), S(10, 15), 23, 0},
    {S(10, 15), S(19, 15), 25, 0},
    {S(19, 15), S(19, 17), 23, 0},
    {S(19, 17), S(19, 19), 21, 0},
    {S(19, 19), 86400,     20, 0},
};

struct Profile {
  const Seg* segs;
  size_t n;
};

Profile profileFor(Crossing c, bool sundayOrPH) {
  if (sundayOrPH) return {kProfileS, sizeof(kProfileS) / sizeof(Seg)};
  if (c == Crossing::WHC) return {kProfileW, sizeof(kProfileW) / sizeof(Seg)};
  return {kProfileC, sizeof(kProfileC) / sizeof(Seg)};
}

uint8_t evalSeg(const Seg& s, uint32_t t) {
  if (s.dir == 0) return s.v0;
  return static_cast<uint8_t>(s.v0 + s.dir * 2 * static_cast<int>((t - s.from) / 120));
}

uint8_t evalAt(const Profile& p, uint32_t t) {
  for (size_t i = 0; i < p.n; i++)
    if (t >= p.segs[i].from && t < p.segs[i].to) return evalSeg(p.segs[i], t);
  return p.segs[p.n - 1].v0;  // unreachable for t < 86400
}

}  // namespace

Result query(Crossing c, uint32_t secOfDay, bool sundayOrPH) {
  if (secOfDay >= 86400) secOfDay %= 86400;
  const Profile p = profileFor(c, sundayOrPH);

  for (size_t i = 0; i < p.n; i++) {
    const Seg& s = p.segs[i];
    if (secOfDay < s.from || secOfDay >= s.to) continue;

    Result r;
    r.dollars = evalSeg(s, secOfDay);

    // Next change: next ramp step within this segment, else the segment boundary.
    uint32_t next = s.to;
    if (s.dir != 0) {
      uint32_t step = s.from + ((secOfDay - s.from) / 120 + 1) * 120;
      if (step < s.to) next = step;
    }
    if (next >= 86400) {
      r.next_change_sec = 86400;
      r.next_dollars = r.dollars;  // both schedules end and start the day at $20
    } else {
      r.next_change_sec = next;
      r.next_dollars = evalAt(p, next);
    }
    // Boundary may be value-neutral (e.g. plateau -> equal ramp start); skip ahead.
    while (r.next_change_sec < 86400 && r.next_dollars == r.dollars) {
      Result deeper = query(c, r.next_change_sec, sundayOrPH);
      r.next_change_sec = deeper.next_change_sec;
      r.next_dollars = deeper.next_dollars;
    }
    return r;
  }
  return {20, 20, 86400};
}

}  // namespace toll
