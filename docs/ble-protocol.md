# CYD-DASH BLE Protocol (normative)

`PROTOCOL_VERSION = 1`. All multi-byte integers are **little-endian**.
Firmware (`firmware/src/ble/protocol.h`) and iOS (`ios-app/CYDDash/BLE/DashProtocol.swift`)
must both implement exactly this document.

## Device

- BLE device name: `CYD-DASH`
- Advertises the primary service UUID below (so iOS can background-scan filtered).
- MTU: firmware requests 512; payloads are all designed to fit in **≤180 bytes**
  so they work at the iOS-typical 185-byte usable MTU without chunking.

## GATT table

Base UUID: `9A3Fxxxx-6D2C-4C8A-9B4E-1F2E3D4C5B6A`

| Handle | UUID `xxxx` | Name     | Properties        | Direction | Payload |
|--------|-------------|----------|-------------------|-----------|---------|
| svc    | `0001`      | Service  | —                 | —         | — |
| chr    | `0002`      | Journey  | Write, Read       | phone → ESP | Journey payload |
| chr    | `0003`      | TimeSync | Write             | phone → ESP | TimeSync payload |
| chr    | `0004`      | Meters   | Write, Read       | phone → ESP | Meters payload |
| chr    | `0005`      | Command  | Notify, Read      | ESP → phone | 1-byte opcode |
| chr    | `0006`      | Status   | Read              | phone ← ESP | Status payload |
| chr    | `0007`      | MeterMap | Write, Read       | phone → ESP | MeterMap payload |

Reads on Journey/Meters return the last written payload (debugging convenience).

## Payloads

### TimeSync (8 bytes) — phone → ESP, written on every connect and every journey push

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0 | u8  | ver        | = 1 |
| 1 | u32 | epoch_utc  | current Unix time (UTC seconds) |
| 5 | i16 | tz_min     | minutes east of UTC; HK = 480 |
| 7 | u8  | flags      | bit0: **today** uses Sun/PH toll schedule; bit1: **tomorrow** does (both evaluated in HK local time) |

### Journey (6 + 3n bytes) — phone → ESP

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0 | u8  | ver           | = 1 |
| 1 | u32 | capture_epoch | Unix time of the TD `CAPTURE_DATE` (converted to UTC) |
| 5 | u8  | count         | n ≤ 12 |
| 6+3i | u8 | slot        | see slot registry |
| 7+3i | u8 | minutes     | journey minutes; sentinels: `0xFF` N/A, `0xFE` congestion, `0xFD` tunnel closed |
| 8+3i | u8 | colour      | 1 red, 2 amber, 3 green, 0 none |

12 slots = 42 bytes.

### Slot registry (default; app-configurable — firmware only keys labels by slot)

| Slot | LOCATION_ID → DESTINATION_ID | Label on screen |
|------|------------------------------|-----------------|
| 1 | H2 → CH  | 紅隧 (港→九) |
| 2 | H2 → EH  | 東隧 (港→九) |
| 3 | H2 → WH  | 西隧 (港→九) |
| 4 | K03 → CH | 紅隧 (九→港) |
| 5 | K03 → EH | 東隧 (九→港) |
| 6 | K03 → WH | 西隧 (九→港) |
| 7 | SJ1 → LRT  | 獅隧 (往九龍) |
| 8 | SJ2 → TCT  | 大老山 (往九龍) |
| 9 | SJ2 → TSCA | 青沙 (往九龍) |
| 10–12 | spare | — |

### Meters (7 + variable) — phone → ESP

The phone searches up to 4 km and reports the nearest streets **with vacant
meters** (status 0). If everything in range is full it reports the nearest
streets anyway with status 4.

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0 | u8  | ver         | = 1 |
| 1 | u32 | fetch_epoch | Unix time of the occupancy fetch |
| 5 | u8  | status      | 0 ok (vacant streets), 1 no-GPS/denied, 2 fetch error, 3 no meters ≤4 km, 4 no vacancy ≤4 km (groups = nearest full streets) |
| 6 | u8  | count       | n ≤ 4 street groups |
| — | per group: | | |
|   | u16 | dist_m      | distance to nearest space in group |
|   | u8  | vacant      | count of `V` spaces |
|   | u8  | total       | working meters in group (`ParkingMeterStatus == N`) |
|   | u8  | name_len    | ≤ 36 |
|   | u8[name_len] | name | street name UTF-8 (**Chinese**, `Street_tc`), truncated at a character boundary |

4 groups ≈ 171 bytes worst case (longest TC street name = 11 chars).

### MeterMap (8 + 3n) — phone → ESP, written right after Meters

Radar view data: individual meter positions relative to the car.

| Offset | Type | Field | Notes |
|--------|------|-------|-------|
| 0 | u8  | ver         | = 1 |
| 1 | u32 | fetch_epoch | same fetch as the Meters payload |
| 5 | u16 | radius_m    | effective radar radius (max distance of included points) |
| 7 | u8  | count       | n ≤ 48 |
| — | per point: | | |
|   | i8  | dx          | east offset as a fraction of radius: metres = dx / 127 × radius_m |
|   | i8  | dy          | north offset, same encoding |
|   | u8  | status      | 0 vacant, 1 occupied, 2 suspended/unknown |

48 points = 152 bytes. The fraction encoding lets one payload cover any radius
(nearest-K search grows 500 m → 4 km until it finds meters); worst-case
precision is radius/127 (≈4 m at 500 m, ≈31 m at 4 km).

### Command (1 byte) — ESP → phone via Notify

| Opcode | Meaning |
|--------|---------|
| `0x01` | User tapped 掃一掃 — please run meters flow and write Meters |
| `0x02` | Journey tick (sent every 120 s while connected) — refresh + write Journey if stale |
| `0x03` | Full resync request (sent when phone subscribes) — write TimeSync + Journey |

The ESP32 is the metronome: `0x02` notifications wake the suspended iOS app,
replacing unreliable background timers.

### Status (12 bytes) — phone ← ESP, Read

| Offset | Type | Field |
|--------|------|-------|
| 0 | u8  | protocol_ver (=1) |
| 1 | u8  | fw_major |
| 2 | u8  | fw_minor |
| 3 | u8  | reserved |
| 4 | u32 | uptime_s |
| 8 | u16 | journey_age_s (0xFFFF = never) |
| 10 | u16 | meters_age_s (0xFFFF = never) |

## Connect sequence (phone side)

1. Connect, discover service, subscribe to Command.
2. Read Status → check `protocol_ver == 1` (mismatch: show update prompt, stop).
3. Write TimeSync.
4. Fetch JTI XML → write Journey.
5. Handle notifies: `0x02` → step 3+4 if last fetch > 110 s; `0x01` → meters flow.
