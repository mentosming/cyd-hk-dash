// pio test -e native
#include <unity.h>

#include <cstdio>

#include "../../src/model/toll_engine.h"

using toll::Crossing;

static uint32_t S(int h, int m, int s) { return h * 3600 + m * 60 + s; }

struct Vec {
  int h, m, s;
  uint8_t w, c, sun;
};

// Shared test vectors — must match docs/toll-schedule.md exactly.
static const Vec kVectors[] = {
    {0, 0, 0, 20, 20, 20},    {7, 29, 59, 20, 20, 20},  {7, 30, 0, 22, 22, 20},
    {7, 31, 59, 22, 22, 20},  {7, 32, 0, 24, 24, 20},   {7, 47, 59, 38, 38, 20},
    {7, 48, 0, 40, 40, 20},   {8, 7, 59, 58, 40, 20},   {8, 8, 0, 60, 40, 20},
    {10, 11, 30, 60, 40, 21}, {10, 14, 59, 60, 40, 23}, {10, 15, 0, 58, 38, 25},
    {10, 22, 59, 52, 32, 25}, {10, 23, 0, 50, 30, 25},  {10, 42, 59, 32, 30, 25},
    {10, 43, 0, 30, 30, 25},  {16, 29, 59, 30, 30, 25}, {16, 30, 0, 32, 32, 25},
    {16, 37, 59, 38, 38, 25}, {16, 38, 0, 40, 40, 25},  {16, 57, 59, 58, 40, 25},
    {16, 58, 0, 60, 40, 25},  {18, 59, 59, 60, 40, 25}, {19, 0, 0, 58, 38, 25},
    {19, 14, 59, 44, 24, 25}, {19, 15, 0, 44, 24, 23},  {19, 17, 59, 42, 22, 21},
    {19, 18, 0, 40, 20, 21},  {19, 19, 0, 40, 20, 20},  {19, 37, 59, 22, 20, 20},
    {19, 38, 0, 20, 20, 20},  {23, 59, 59, 20, 20, 20},
};

void test_vectors() {
  for (auto& v : kVectors) {
    uint32_t t = S(v.h, v.m, v.s);
    char msg[64];
    snprintf(msg, sizeof(msg), "WHC weekday @%02d:%02d:%02d", v.h, v.m, v.s);
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(v.w, toll::query(Crossing::WHC, t, false).dollars, msg);
    snprintf(msg, sizeof(msg), "CHT weekday @%02d:%02d:%02d", v.h, v.m, v.s);
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(v.c, toll::query(Crossing::CHT, t, false).dollars, msg);
    snprintf(msg, sizeof(msg), "EHC weekday @%02d:%02d:%02d", v.h, v.m, v.s);
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(v.c, toll::query(Crossing::EHC, t, false).dollars, msg);
    snprintf(msg, sizeof(msg), "Sun/PH @%02d:%02d:%02d", v.h, v.m, v.s);
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(v.sun, toll::query(Crossing::WHC, t, true).dollars, msg);
    TEST_ASSERT_EQUAL_UINT8_MESSAGE(v.sun, toll::query(Crossing::CHT, t, true).dollars, msg);
  }
}

// Sweep every second of the day: tolls stay in [20,60], change in ±$2 steps max
// (Sunday profile also has ±1 steps at plateau edges: allow <= 2), and
// next_change_sec is honest (value really changes there, not before).
void test_sweep_consistency() {
  for (int sun = 0; sun <= 1; sun++) {
    for (int c = 0; c < 3; c++) {
      uint8_t prev = toll::query((Crossing)c, 0, sun).dollars;
      for (uint32_t t = 1; t < 86400; t++) {
        auto r = toll::query((Crossing)c, t, sun);
        TEST_ASSERT_TRUE(r.dollars >= 20 && r.dollars <= 60);
        int delta = (int)r.dollars - (int)prev;
        TEST_ASSERT_TRUE_MESSAGE(delta >= -2 && delta <= 2, "toll jumped more than $2");
        prev = r.dollars;
      }
    }
  }
}

void test_next_change() {
  // Plateau: 09:00 weekday WHC $60 until 10:15 -> $58
  auto r = toll::query(Crossing::WHC, S(9, 0, 0), false);
  TEST_ASSERT_EQUAL_UINT8(60, r.dollars);
  TEST_ASSERT_EQUAL_UINT32(S(10, 15, 0), r.next_change_sec);
  TEST_ASSERT_EQUAL_UINT8(58, r.next_dollars);

  // Mid-ramp: 07:33 weekday CHT $24, next step 07:34 -> $26
  r = toll::query(Crossing::CHT, S(7, 33, 0), false);
  TEST_ASSERT_EQUAL_UINT8(24, r.dollars);
  TEST_ASSERT_EQUAL_UINT32(S(7, 34, 0), r.next_change_sec);
  TEST_ASSERT_EQUAL_UINT8(26, r.next_dollars);

  // Late night: no more changes today
  r = toll::query(Crossing::EHC, S(22, 0, 0), false);
  TEST_ASSERT_EQUAL_UINT8(20, r.dollars);
  TEST_ASSERT_EQUAL_UINT32(86400, r.next_change_sec);

  // next_change honesty across the whole day at 1s resolution
  for (int sun = 0; sun <= 1; sun++) {
    for (uint32_t t = 0; t < 86400; t += 1) {
      auto q = toll::query(Crossing::WHC, t, sun);
      if (q.next_change_sec < 86400) {
        TEST_ASSERT_EQUAL_UINT8(q.dollars,
                                toll::query(Crossing::WHC, q.next_change_sec - 1, sun).dollars);
        TEST_ASSERT_EQUAL_UINT8(q.next_dollars,
                                toll::query(Crossing::WHC, q.next_change_sec, sun).dollars);
        TEST_ASSERT_TRUE(q.next_dollars != q.dollars);
      }
    }
  }
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_vectors);
  RUN_TEST(test_sweep_consistency);
  RUN_TEST(test_next_change);
  return UNITY_END();
}
