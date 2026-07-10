// Payload encoders — normative spec: docs/ble-protocol.md (PROTOCOL_VERSION 2)
// Mirrors firmware/src/ble/protocol.h. All integers little-endian.
import Foundation

enum DashProtocol {
    static let protocolVersion: UInt8 = 2

    enum UUIDs {
        static let service = "9A3F0001-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
        static let journey = "9A3F0002-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
        static let timeSync = "9A3F0003-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
        static let meters = "9A3F0004-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
        static let command = "9A3F0005-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
        static let status = "9A3F0006-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
        static let slotNames = "9A3F0008-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
        static let fuelPrices = "9A3F0009-6D2C-4C8A-9B4E-1F2E3D4C5B6A"
    }

    enum Opcode: UInt8 {
        case metersRefresh = 0x01
        case journeyTick = 0x02
        case fullResync = 0x03
    }

    // Journey minutes sentinels
    static let minutesNA: UInt8 = 0xFF
    static let minutesCongestion: UInt8 = 0xFE
    static let minutesClosed: UInt8 = 0xFD

    // Fixed harbour slots 1-6; slots 7-9 user-configurable (SlotConfig)
    static let fixedSlots: [(slot: UInt8, location: String, destination: String)] = [
        (1, "H2", "CH"), (2, "H2", "EH"), (3, "H2", "WH"),
        (4, "K03", "CH"), (5, "K03", "EH"), (6, "K03", "WH"),
    ]

    struct JourneyEntry {
        let slot: UInt8
        let minutes: UInt8
        let colour: UInt8
    }

    struct MeterGroup {
        let name: String     // Chinese street name (Street_tc)
        let distM: UInt16
        let vacant: UInt8
        let total: UInt8
        let lpp: UInt8       // minutes 30/60/120, 0 unknown
    }

    struct DeviceStatus {
        let protocolVersion: UInt8
        let fwMajor: UInt8
        let fwMinor: UInt8
        let uptimeS: UInt32
        let journeyAgeS: UInt16
        let metersAgeS: UInt16
    }

    // MARK: Encoders

    /// sunPHFlags bits 0-3: today / +1 / +2 / +3 days (HK local) use Sun/PH schedule.
    static func encodeTimeSync(now: Date = Date(), sunPHFlags: UInt8) -> Data {
        var d = Data([protocolVersion])
        d.appendLE(UInt32(now.timeIntervalSince1970))
        d.appendLE(UInt16(bitPattern: 480))  // HK = UTC+8
        d.append(sunPHFlags & 0x0F)
        return d
    }

    static func encodeJourney(captureEpoch: UInt32, entries: [JourneyEntry]) -> Data {
        var d = Data([protocolVersion])
        d.appendLE(captureEpoch)
        d.append(UInt8(entries.count))
        for e in entries.prefix(12) {
            d.append(contentsOf: [e.slot, e.minutes, e.colour])
        }
        return d
    }

    static func encodeMeters(fetchEpoch: UInt32, status: UInt8, groups: [MeterGroup]) -> Data {
        var d = Data([protocolVersion])
        d.appendLE(fetchEpoch)
        d.append(status)
        let capped = groups.prefix(4)
        d.append(UInt8(capped.count))
        for g in capped {
            // 12 chars keeps CJK names ≤36 bytes and never splits a character
            let name = Data(String(g.name.prefix(12)).utf8)
            d.appendLE(g.distM)
            d.append(g.vacant)
            d.append(g.total)
            d.append(g.lpp)
            d.append(UInt8(name.count))
            d.append(name)
        }
        return d
    }

    static func encodeSlotNames(_ names: [(slot: UInt8, name: String)]) -> Data {
        var d = Data([protocolVersion])
        let capped = names.prefix(12)
        d.append(UInt8(capped.count))
        for e in capped {
            let name = Data(String(e.name.prefix(8)).utf8)  // ≤24 bytes
            d.append(e.slot)
            d.append(UInt8(name.count))
            d.append(name)
        }
        return d
    }

    /// cents[brand][type], 5 brands × 3 types; nil → 0xFFFF.
    static func encodeFuelPrices(fetchEpoch: UInt32, cents: [[UInt16?]]) -> Data {
        var d = Data([protocolVersion])
        d.appendLE(fetchEpoch)
        for b in 0..<5 {
            for t in 0..<3 {
                let v = (b < cents.count && t < cents[b].count) ? (cents[b][t] ?? 0xFFFF) : 0xFFFF
                d.appendLE(v)
            }
        }
        return d
    }

    static func decodeStatus(_ d: Data) -> DeviceStatus? {
        guard d.count >= 12 else { return nil }
        let b = [UInt8](d)
        return DeviceStatus(
            protocolVersion: b[0], fwMajor: b[1], fwMinor: b[2],
            uptimeS: UInt32(b[4]) | UInt32(b[5]) << 8 | UInt32(b[6]) << 16 | UInt32(b[7]) << 24,
            journeyAgeS: UInt16(b[8]) | UInt16(b[9]) << 8,
            metersAgeS: UInt16(b[10]) | UInt16(b[11]) << 8)
    }
}

extension Data {
    mutating func appendLE(_ v: UInt32) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
                            UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }
    mutating func appendLE(_ v: UInt16) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }
}
