# Time-varying toll schedule — private cars (633 scheme)

Source: Transport Department official schedule, verified 2026-07-10.
Encoded as plateau breakpoints; transitions ramp **±$2 every 2 minutes**.
All times are HK local, seconds since midnight.

## Weekdays (Mon–Sat, excluding public holidays)

### WHC 西隧 (profile W)

| From | To | Toll |
|------|----|------|
| 00:00:00 | 07:29:59 | $20 |
| 07:30:00 | 08:07:59 | ramp $22 → $58 (+$2/2min) |
| 08:08:00 | 10:14:59 | **$60** |
| 10:15:00 | 10:42:59 | ramp $58 → $32 (−$2/2min) |
| 10:43:00 | 16:29:59 | **$30** |
| 16:30:00 | 16:57:59 | ramp $32 → $58 |
| 16:58:00 | 18:59:59 | **$60** |
| 19:00:00 | 19:37:59 | ramp $58 → $22 |
| 19:38:00 | 23:59:59 | **$20** |

### CHT 紅隧 & EHC 東隧 (profile C)

| From | To | Toll |
|------|----|------|
| 00:00:00 | 07:29:59 | $20 |
| 07:30:00 | 07:47:59 | ramp $22 → $38 |
| 07:48:00 | 10:14:59 | **$40** |
| 10:15:00 | 10:22:59 | ramp $38 → $32 |
| 10:23:00 | 16:29:59 | **$30** |
| 16:30:00 | 16:37:59 | ramp $32 → $38 |
| 16:38:00 | 18:59:59 | **$40** |
| 19:00:00 | 19:17:59 | ramp $38 → $22 |
| 19:18:00 | 23:59:59 | **$20** |

## Sundays & public holidays (all three crossings, profile S)

| From | To | Toll |
|------|----|------|
| 00:00:00 | 10:10:59 | $20 |
| 10:11:00 | 10:12:59 | $21 |
| 10:13:00 | 10:14:59 | $23 |
| 10:15:00 | 19:14:59 | **$25** |
| 19:15:00 | 19:16:59 | $23 |
| 19:17:00 | 19:18:59 | $21 |
| 19:19:00 | 23:59:59 | **$20** |

Other classes (not displayed in v1): taxis flat $25; motorcycles 40% of private car; commercial flat $50.

## Ramp formula

Within a ramp starting at `t0` with start value `v0` going toward plateau `v1`:
`toll = v0 + direction * 2 * floor((t - t0) / 120)` clamped to `[min(v0,v1), max(v0,v1)]`.

## Shared test vectors (weekday profile W / C, Sunday profile S)

| Time | W | C | S |
|------|---|---|---|
| 00:00:00 | 20 | 20 | 20 |
| 07:29:59 | 20 | 20 | 20 |
| 07:30:00 | 22 | 22 | 20 |
| 07:31:59 | 22 | 22 | 20 |
| 07:32:00 | 24 | 24 | 20 |
| 07:47:59 | 38 | 38 | 20 |
| 07:48:00 | 40 | 40 | 20 |
| 08:07:59 | 58 | 40 | 20 |
| 08:08:00 | 60 | 40 | 20 |
| 10:11:30 | 60 | 40 | 21 |
| 10:14:59 | 60 | 40 | 23 |
| 10:15:00 | 58 | 38 | 25 |
| 10:22:59 | 52 | 32 | 25 |
| 10:23:00 | 50 | 30 | 25 |
| 10:42:59 | 32 | 30 | 25 |
| 10:43:00 | 30 | 30 | 25 |
| 16:29:59 | 30 | 30 | 25 |
| 16:30:00 | 32 | 32 | 25 |
| 16:37:59 | 38 | 38 | 25 |
| 16:38:00 | 40 | 40 | 25 |
| 16:57:59 | 58 | 40 | 25 |
| 16:58:00 | 60 | 40 | 25 |
| 18:59:59 | 60 | 40 | 25 |
| 19:00:00 | 58 | 38 | 25 |
| 19:14:59 | 44 | 24 | 25 |
| 19:15:00 | 44 | 24 | 23 |
| 19:17:59 | 42 | 22 | 21 |
| 19:18:00 | 40 | 20 | 21 |
| 19:19:00 | 40 | 20 | 20 |
| 19:37:59 | 22 | 20 | 20 |
| 19:38:00 | 20 | 20 | 20 |
| 23:59:59 | 20 | 20 | 20 |

Both `firmware/src/model/toll_engine.cpp` and `ios-app/.../TollEngine.swift`
must pass every row above, plus full-day parity sweeps at 1-minute resolution.
