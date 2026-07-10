#!/usr/bin/env python3
"""Fake-phone simulator for CYD-DASH (protocol v2).

Connects to the ESP32 over BLE from this Mac, pushes TimeSync + Journey
(fetched LIVE from data.gov.hk unless --fake), fuel prices (Consumer
Council) and slot names, and answers 掃一掃 requests with fake meter data.

Note: with BLE_REQUIRE_BONDING firmware, macOS will show a pairing dialog
on the first write — enter the PIN shown on the CYD screen.

Usage:
  uv run --with bleak --with requests python tools/ble_sim.py [--fake]
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

PROTO_VER = 2

UUID_SERVICE = "9a3f0001-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_JOURNEY = "9a3f0002-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_TIMESYNC = "9a3f0003-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_METERS = "9a3f0004-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_COMMAND = "9a3f0005-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_STATUS = "9a3f0006-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_SLOTNAMES = "9a3f0008-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_FUELPRICES = "9a3f0009-6d2c-4c8a-9b4e-1f2e3d4c5b6a"
UUID_AUTH = "9a3f000a-6d2c-4c8a-9b4e-1f2e3d4c5b6a"

JTI_URL = "https://resource.data.one.gov.hk/td/jss/Journeytimev2.xml"
FUEL_URL = "https://www.consumer.org.hk/pricewatch/oilwatch/opendata/oilprice.json"
HKT = timezone(timedelta(hours=8))

# slot -> (LOCATION_ID, DESTINATION_ID), defaults per docs/ble-protocol.md
SLOTS = {
    1: ("H2", "CH"), 2: ("H2", "EH"), 3: ("H2", "WH"),
    4: ("K03", "CH"), 5: ("K03", "EH"), 6: ("K03", "WH"),
    7: ("SJ1", "LRT"), 8: ("SJ2", "TCT"), 9: ("SJ2", "TSCA"),
}
FUEL_BRANDS = ["Sinopec", "PetroChina", "Caltex", "Esso", "Shell"]
FUEL_TYPES = ["Standard Petrol", "Premium Petrol", "Diesel"]

MIN_NA, MIN_CONGESTION, MIN_CLOSED = 0xFF, 0xFE, 0xFD


def timesync_payload() -> bytes:
    # bits 0-3: today/+1/+2/+3 are Sun (PH lookup omitted in the simulator)
    flags = 0
    now = datetime.now(HKT)
    for i in range(4):
        if (now + timedelta(days=i)).weekday() == 6:
            flags |= 1 << i
    return struct.pack("<BIhB", PROTO_VER, int(time.time()), 480, flags)


def fake_journey_payload() -> bytes:
    entries = [(1, 12, 2), (2, 8, 3), (3, 6, 3), (4, 18, 1), (5, 9, 3),
               (6, 7, 3), (7, 11, 2), (8, 9, 3), (9, 13, 2)]
    out = struct.pack("<BIB", PROTO_VER, int(time.time()), len(entries))
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
        loc, dest = f.get("LOCATION_ID", ""), f.get("DESTINATION_ID", "")
        cap = f.get("CAPTURE_DATE", "")
        if cap:
            try:
                capture_epoch = int(
                    datetime.fromisoformat(cap).replace(tzinfo=HKT).timestamp())
            except ValueError:
                pass
        by_pair[(loc, dest)] = f

    entries = []
    for slot, pair in SLOTS.items():
        f = by_pair.get(pair)
        if f is None:
            entries.append((slot, MIN_NA, 0))
            continue
        jtype, jdata = f.get("JOURNEY_TYPE", ""), f.get("JOURNEY_DATA", "-1")
        colour = f.get("COLOUR_ID", "-1")
        col = int(colour) if colour in ("1", "2", "3") else 0
        if jtype == "1" and jdata.lstrip("-").isdigit() and int(jdata) >= 0:
            entries.append((slot, min(int(jdata), 250), col))
        elif jtype == "2" and jdata == "1":
            entries.append((slot, MIN_CONGESTION, col))
        elif jtype == "2" and jdata == "3":
            entries.append((slot, MIN_CLOSED, col))
        else:
            entries.append((slot, MIN_NA, 0))
        print(f"  slot {slot} {pair[0]}→{pair[1]}: {entries[-1][1]} min")

    out = struct.pack("<BIB", PROTO_VER, capture_epoch, len(entries))
    for slot, mins, col in entries:
        out += struct.pack("<BBB", slot, mins, col)
    return out


def fake_meters_payload() -> bytes:
    groups = [("軒尼詩道", 120, 3, 16, 120), ("駱克道", 210, 0, 12, 60),
              ("謝斐道", 260, 5, 8, 120), ("盧押道", 300, 2, 6, 30)]
    out = struct.pack("<BIBB", PROTO_VER, int(time.time()), 0, len(groups))
    for name, dist, vac, tot, lpp in groups:
        nb = name.encode()[:36]
        out += struct.pack("<HBBBB", dist, vac, tot, lpp, len(nb)) + nb
    return out


def slotnames_payload() -> bytes:
    names = [(7, "獅隧"), (8, "大老山"), (9, "青沙")]
    out = struct.pack("<BB", PROTO_VER, len(names))
    for slot, name in names:
        nb = name.encode()[:24]
        out += struct.pack("<BB", slot, len(nb)) + nb
    return out


def fuel_payload(fake: bool) -> bytes:
    cents = [[0xFFFF] * 3 for _ in range(5)]
    if fake:
        cents = [[3184, 3364, 3372], [3184, 3184, 3372], [3184, 3364, 3392],
                 [3184, 3364, 3372], [3184, 3364, 3372]]
    else:
        import requests
        data = requests.get(FUEL_URL, timeout=10).json()
        for entry in data:
            t = entry.get("type", {}).get("en")
            if t not in FUEL_TYPES:
                continue
            ti = FUEL_TYPES.index(t)
            for p in entry.get("prices", []):
                v = p.get("vendor", {}).get("en")
                if v in FUEL_BRANDS:
                    try:
                        cents[FUEL_BRANDS.index(v)][ti] = int(round(float(p["price"]) * 100))
                    except (ValueError, KeyError):
                        pass
    out = struct.pack("<BI", PROTO_VER, int(time.time()))
    for b in range(5):
        for t in range(3):
            out += struct.pack("<H", cents[b][t])
    return out


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fake", action="store_true", help="use fake data, no network")
    ap.add_argument("--token", help="pairing token hex (from the boot 'Pair URL' log or QR)")
    args = ap.parse_args()

    print("Scanning for CYD-DASH ...")
    dev = await BleakScanner.find_device_by_name("CYD-DASH", timeout=15)
    if not dev:
        sys.exit("CYD-DASH not found — is the board powered?")
    print(f"Found {dev.address}, connecting ...")

    async with BleakClient(dev) as client:
        status = await client.read_gatt_char(UUID_STATUS)
        proto_ver, fw_maj, fw_min = status[0], status[1], status[2]
        print(f"Connected. fw {fw_maj}.{fw_min} proto {proto_ver}")
        assert proto_ver == PROTO_VER, f"protocol mismatch: fw={proto_ver} sim={PROTO_VER}"

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

        # App-layer auth: present the token BEFORE any data write, or the
        # firmware (APP_TOKEN_REQUIRED) rejects everything and shows its QR.
        if args.token:
            await client.write_gatt_char(UUID_AUTH, bytes.fromhex(args.token), response=True)
            print(f">> auth token ({len(args.token)//2} B)")
        else:
            print("!! no --token given; firmware will reject writes and show the QR")

        wants_journey.set()

        async def push_journey():
            await client.write_gatt_char(UUID_TIMESYNC, timesync_payload(), response=True)
            print(">> timesync")
            payload = fake_journey_payload() if args.fake else live_journey_payload()
            await client.write_gatt_char(UUID_JOURNEY, payload, response=True)
            print(f">> journey ({len(payload)} B)")

        # initial extras
        await client.write_gatt_char(UUID_SLOTNAMES, slotnames_payload(), response=True)
        print(">> slotnames")
        fp = fuel_payload(args.fake)
        await client.write_gatt_char(UUID_FUELPRICES, fp, response=True)
        print(f">> fuelprices ({len(fp)} B)")

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
                print(">> meters (fake, Chinese names + LPP)")
            if not done:
                await push_journey()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
