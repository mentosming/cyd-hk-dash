#!/usr/bin/env python3
"""Fake-phone simulator for CYD-DASH.

Connects to the ESP32 over BLE from this Mac, pushes TimeSync + Journey
(fetched LIVE from data.gov.hk unless --fake) and answers 掃一掃 requests
with either fake meter data or live occupancy data.

Usage:
  python3 -m pip install bleak requests
  python3 tools/ble_sim.py            # live journey data, fake meters
  python3 tools/ble_sim.py --fake     # all-fake payloads (offline test)
"""

import argparse
import asyncio
import struct
import sys
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone, timedelta

try:
    from bleak import BleakClient, BleakScanner
except ImportError:
    sys.exit("pip3 install bleak")

UUID_SERVICE = "9a3f0001-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_JOURNEY = "9a3f0002-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_TIMESYNC = "9a3f0003-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_METERS = "9a3f0004-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_COMMAND = "9a3f0005-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_STATUS = "9a3f0006-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_METERMAP = "9a3f0007-6d2c-4c8a-9b4e-1f2e3d4c5b6a"

JTI_URL = "https://resource.data.one.gov.hk/td/jss/Journeytimev2.xml"
HKT = timezone(timedelta(hours=8))

# slot -> (LOCATION_ID, DESTINATION_ID), mirrors docs/ble-protocol.md
SLOTS = {
    1: ("H2", "CH"), 2: ("H2", "EH"), 3: ("H2", "WH"),
    4: ("K03", "CH"), 5: ("K03", "EH"), 6: ("K03", "WH"),
    7: ("SJ1", "LRT"), 8: ("SJ2", "TCT"), 9: ("SJ2", "TSCA"),
}

MIN_NA, MIN_CONGESTION, MIN_CLOSED = 0xFF, 0xFE, 0xFD


def timesync_payload() -> bytes:
    now = datetime.now(HKT)
    is_sun = now.weekday() == 6  # PH lookup omitted in the simulator
    tomorrow_sun = (now + timedelta(days=1)).weekday() == 6
    flags = (1 if is_sun else 0) | (2 if tomorrow_sun else 0)
    return struct.pack("<BIhB", 1, int(time.time()), 480, flags)


def fake_journey_payload() -> bytes:
    entries = [(1, 12, 2), (2, 8, 3), (3, 6, 3), (4, 18, 1), (5, 9, 3),
               (6, 7, 3), (7, 11, 2), (8, 9, 3), (9, 13, 2)]
    out = struct.pack("<BIB", 1, int(time.time()), len(entries))
    for slot, mins, col in entries:
        out += struct.pack("<BBB", slot, mins, col)
    return out


def live_journey_payload() -> bytes:
    import requests
    xml = requests.get(JTI_URL, timeout=10).text
    root = ET.fromstring(xml)
    by_pair = {}
    capture_epoch = int(time.time())

    def local(tag):  # the feed uses a default namespace: strip it
        return tag.split("}")[-1]

    for rec in root.iter():
        if local(rec.tag) != "jtis_journey_time":
            continue
        f = {local(ch.tag): (ch.text or "").strip() for ch in rec}
        loc = f.get("LOCATION_ID", "")
        dest = f.get("DESTINATION_ID", "")
        jtype = f.get("JOURNEY_TYPE", "")
        jdata = f.get("JOURNEY_DATA", "-1")
        colour = f.get("COLOUR_ID", "-1")
        cap = f.get("CAPTURE_DATE", "")
        if cap:
            try:
                capture_epoch = int(
                    datetime.fromisoformat(cap).replace(tzinfo=HKT).timestamp())
            except ValueError:
                pass
        by_pair[(loc, dest)] = (jtype, jdata, colour)

    entries = []
    for slot, pair in SLOTS.items():
        rec = by_pair.get(pair)
        if rec is None:
            entries.append((slot, MIN_NA, 0))
            continue
        jtype, jdata, colour = rec
        col = int(colour) if colour in ("1", "2", "3") else 0
        if jtype == "1" and jdata.lstrip("-").isdigit() and int(jdata) >= 0:
            entries.append((slot, min(int(jdata), 250), col))
        elif jtype == "2" and jdata == "1":
            entries.append((slot, MIN_CONGESTION, col))
        elif jtype == "2" and jdata == "3":
            entries.append((slot, MIN_CLOSED, col))
        else:
            entries.append((slot, MIN_NA, 0))
        print(f"  slot {slot} {pair[0]}→{pair[1]}: {entries[-1][1]} min (colour {col})")

    out = struct.pack("<BIB", 1, capture_epoch, len(entries))
    for slot, mins, col in entries:
        out += struct.pack("<BBB", slot, mins, col)
    return out


def fake_meters_payload() -> bytes:
    groups = [("Hennessy Road", 120, 3, 16), ("Lockhart Road", 210, 0, 12),
              ("Jaffe Road", 260, 5, 8)]
    out = struct.pack("<BIBB", 1, int(time.time()), 0, len(groups))
    for name, dist, vac, tot in groups:
        nb = name.encode()[:20]
        out += struct.pack("<HBBB", dist, vac, tot, len(nb)) + nb
    return out


def fake_metermap_payload() -> bytes:
    # A street running east-west 120 m north of the car, another to the south,
    # mixing vacant / occupied / suspended — mimics the HKeMeter dot map.
    import random
    random.seed(7)
    points = []
    for i in range(14):  # north street (Hennessy Rd)
        points.append((-130 + i * 20, 120, random.choice([0, 1, 1, 1])))
    for i in range(10):  # south street (Lockhart Rd)
        points.append((-90 + i * 20, -150, random.choice([0, 1, 1, 2])))
    for i in range(6):   # west side street
        points.append((-180, -60 + i * 25, random.choice([0, 1])))
    radius = 250  # effective radius; dx/dy encoded as fraction of it (/127)
    out = struct.pack("<BIHB", 1, int(time.time()), radius, len(points))
    for dx, dy, st in points:
        out += struct.pack("<bbB", max(-127, min(127, round(dx / radius * 127))),
                           max(-127, min(127, round(dy / radius * 127))), st)
    return out


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fake", action="store_true", help="use fake data, no network")
    args = ap.parse_args()

    print("Scanning for CYD-DASH ...")
    dev = await BleakScanner.find_device_by_name("CYD-DASH", timeout=15)
    if not dev:
        sys.exit("CYD-DASH not found — is the board powered?")
    print(f"Found {dev.address}, connecting ...")

    async with BleakClient(dev) as client:
        status = await client.read_gatt_char(UUID_STATUS)
        proto_ver, fw_maj, fw_min = status[0], status[1], status[2]
        uptime, j_age, m_age = struct.unpack_from("<IHH", status, 4)
        print(f"Connected. fw {fw_maj}.{fw_min} proto {proto_ver} uptime {uptime}s "
              f"journey_age {j_age} meters_age {m_age}")
        assert proto_ver == 1, "protocol version mismatch"

        loop = asyncio.get_running_loop()
        wants_meters = asyncio.Event()
        wants_journey = asyncio.Event()

        def on_command(_, data: bytearray):
            op = data[0] if data else 0
            print(f"<< command 0x{op:02x}")
            if op == 0x01:
                loop.call_soon_threadsafe(wants_meters.set)
            elif op in (0x02, 0x03):
                loop.call_soon_threadsafe(wants_journey.set)

        await client.start_notify(UUID_COMMAND, on_command)
        wants_journey.set()  # initial push without waiting for 0x03

        async def push_journey():
            await client.write_gatt_char(UUID_TIMESYNC, timesync_payload(), response=True)
            print(">> timesync")
            payload = fake_journey_payload() if args.fake else live_journey_payload()
            await client.write_gatt_char(UUID_JOURNEY, payload, response=True)
            print(f">> journey ({len(payload)} B)")

        print("Running. Tap 掃一掃 on the board to test meters. Ctrl-C to quit.")
        while True:
            done, _ = await asyncio.wait(
                [asyncio.create_task(wants_journey.wait()),
                 asyncio.create_task(wants_meters.wait())],
                timeout=130, return_when=asyncio.FIRST_COMPLETED)
            if wants_journey.is_set():
                wants_journey.clear()
                await push_journey()
            if wants_meters.is_set():
                wants_meters.clear()
                await client.write_gatt_char(UUID_METERS, fake_meters_payload(), response=True)
                await client.write_gatt_char(UUID_METERMAP, fake_metermap_payload(), response=True)
                print(">> meters + metermap (fake)")
            if not done:  # periodic keep-fresh even if 0x02 was missed
                await push_journey()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
