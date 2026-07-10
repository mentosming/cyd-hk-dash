# CYD-DASH BLE Protocol (normative)

`PROTOCOL_VERSION = 2`. All multi-byte integers are **little-endian**.
Firmware (`firmware/src/ble/protocol.h`) and iOS (`ios-app/CYDDash/BLE/DashProtocol.swift`)
must both implement exactly this document. Every payload starts with a
version byte = 2; receivers reject other versions.

## Device

- BLE device name: `CYD-DASH`
- Advertises the primary service UUID below (so iOS can background-scan filtered).
- MTU: firmware requests 512; payloads are all designed to fit in **≤180 bytes**
  so they work at the iOS-typical 185-byte usable MTU without chunking.

## GATT table

Base UUID: `9A3Fxxxx-6D2C-4C8A-9B4E-1F2E3D4C5B6A`

| UUID `xxxx` | Name       | Properties   | Direction   | Payload |
|-------------|------------|--------------|-------------|---------|
| `0001`      | Service    | —            | —           | — |
| `0002`      | Journey    | Write, Read  | phone → ESP | Journey |
| `0003`      | TimeSync   | Write        | phone → ESP | TimeSync |
| `0004`      | Meters     | Write, Read  | phone → ESP | Meters |
| `0005`      | Command    | Notify, Read | ESP → phone | 1-byte opcode |
| `0006`      | Status     | Read         | phone ← ESP | Status |
| `0008`      | SlotNames  | Write        | phone → ESP | SlotNames |
| `0009`      | FuelPrices | Write, Read  | phone → ESP | FuelPrices |
| `000A`      | Auth       | Write(enc)   | phone → ESP | 8-byte pairing token |

(`0007` was the v1 radar MeterMap — removed in v2.)

## App-layer pairing (QR + token)

On top of BLE bonding, data writes require an **app-layer token**. The device
holds a random 8-byte token (NVS, regenerated when bonds are cleared) and shows
it as an on-screen QR encoding a deep link:

`cyddash://pair?t=<16 hex chars>&n=CYD-DASH`

The phone scans it with the Camera app → the deep link opens CYDDash → the app
stores the token and writes it to the **Auth** characteristic. Until a
connection presents the correct token, the device ignores every data write and
notifies opcode `0x04` (NEED_PAIR); the QR overlay is shown while connected but
unauthorised (also togglable by tapping the on-screen BT dot). Set firmware
`APP_TOKEN_REQUIRED 0` to disable.

## Payloads

### TimeSync (8 bytes) — phone → ESP, written on every connect and journey push

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0 | u8  | ver        | = 2 |
| 1 | u32 | epoch_utc  | current Unix time (UTC seconds) |
| 5 | i16 | tz_min     | minutes east of UTC; HK = 480 |
| 7 | u8  | flags      | bits 0–3: today / +1 / +2 / +3 days use the Sun/PH toll schedule (HK local dates) — covers long holiday runs while disconnected |

### Journey (6 + 3n bytes) — phone → ESP

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0 | u8  | ver           | = 2 |
| 1 | u32 | capture_epoch | Unix time of the TD `CAPTURE_DATE` |
| 5 | u8  | count         | n ≤ 12 |
| 6+3i | u8 | slot        | see slot registry |
| 7+3i | u8 | minutes     | journey minutes; sentinels: `0xFF` N/A, `0xFE` congestion, `0xFD` closed |
| 8+3i | u8 | colour      | 1 red, 2 amber, 3 green, 0 none |

### Slot registry

Slots 1–6 fixed (harbour page): 1-3 = H2→CH/EH/WH (港→九), 4-6 = K03→CH/EH/WH (九→港).
Slots 7–9 are **user-configurable** in the app (default SJ1→LRT 獅隧, SJ2→TCT 大老山,
SJ2→TSCA 青沙); their display names come via SlotNames. 10–12 reserved.

### Meters (7 + variable) — phone → ESP

The phone searches ≤4 km and reports the nearest streets **with vacant,
currently-parkable, private-car (VehicleType A) meters** (status 0).
If everything in range is full → nearest streets with status 4.
Spaces with PoleId > 90000 (official test meters) are excluded. A space is
"currently parkable" per the official OperatingPeriod table: inside operating
hours = paid parking; outside = free parking allowed EXCEPT explicit
no-parking windows (code P: Sundays; code S: Mon–Fri 08:00–17:00).

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0 | u8  | ver         | = 2 |
| 1 | u32 | fetch_epoch | Unix time of the occupancy fetch |
| 5 | u8  | status      | 0 ok, 1 no-GPS, 2 fetch error, 3 no meters ≤4 km, 4 no vacancy ≤4 km |
| 6 | u8  | count       | n ≤ 4 street groups |
| — | per group: | | |
|   | u16 | dist_m      | distance to nearest space in group |
|   | u8  | vacant      | vacant parkable spaces |
|   | u8  | total       | working parkable spaces (`ParkingMeterStatus == N`) |
|   | u8  | lpp         | longest parking period of the vacant spaces, minutes (30/60/120; min over group, 0 unknown) |
|   | u8  | name_len    | ≤ 36 |
|   | u8[name_len] | name | street name UTF-8 (**Chinese**, `Street_tc`), char-boundary truncated |

4 groups ≈ 179 bytes worst case.

### SlotNames (2 + variable) — phone → ESP, written when route config changes

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0 | u8 | ver      | = 2 |
| 1 | u8 | count    | n ≤ 12 |
| — | per entry: | | |
|   | u8 | slot     | 1..12 (currently 7-9 used) |
|   | u8 | name_len | ≤ 24 |
|   | u8[name_len] | name | route display name UTF-8 (Chinese, ≤8 chars) |

Firmware persists to NVS; routes page renders these labels.

### FuelPrices (35 bytes) — phone → ESP, on connect + every ~6 h

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0 | u8  | ver         | = 2 |
| 1 | u32 | fetch_epoch | Unix time of the Consumer Council fetch |
| 5 | u16×15 | cents    | price × 100, ordered [brand][type]; `0xFFFF` = N/A |

Brand order: 中石化 Sinopec, 中國石油 PetroChina, 加德士 Caltex, 埃索 Esso, 蜆殼 Shell.
Type order: 無鉛 Standard Petrol, 特級無鉛 Premium Petrol, 柴油 Diesel.
Source: Consumer Council Oil Price Watch open data (list/pump prices).

### Command (1 byte) — ESP → phone via Notify

| Opcode | Meaning |
|--------|---------|
| `0x01` | User tapped 掃一掃 — run meters flow, write Meters |
| `0x02` | Journey tick (every 120 s while connected) — refresh journey if stale; also drives meters auto-refresh window and 6-hourly fuel refresh |
| `0x03` | Full resync request (sent when phone subscribes) — write TimeSync, Journey, FuelPrices, SlotNames |

### Status (12 bytes) — phone ← ESP, Read

| Offset | Type | Field |
|--------|------|-------|
| 0 | u8  | protocol_ver (=2) |
| 1 | u8  | fw_major |
| 2 | u8  | fw_minor |
| 3 | u8  | reserved |
| 4 | u32 | uptime_s |
| 8 | u16 | journey_age_s (0xFFFF = never) |
| 10 | u16 | meters_age_s (0xFFFF = never) |

## Connect sequence (phone side)

1. Connect, discover service, subscribe to Command.
2. **Write the stored pairing token to Auth FIRST** (writes are FIFO, so it lands
   before any data write). If no token stored, prompt the user to scan the QR.
3. Read Status → check `protocol_ver == 2` (mismatch: show update prompt, stop).
4. Write TimeSync → fetch JTI XML → write Journey.
5. Write FuelPrices (cached ok) and SlotNames (if configured).
6. Handle notifies: `0x02` → journey if >110 s; meters auto-refresh if window open;
   fuel if >6 h. `0x01` → meters flow. `0x04` → (re)write token or prompt to scan QR.
