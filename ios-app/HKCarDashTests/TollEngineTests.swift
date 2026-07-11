// Parity tests — same shared vectors as firmware test_toll_engine
// (docs/toll-schedule.md). If these change, both sides must change.
import XCTest
@testable import HKCarDash

final class TollEngineTests: XCTestCase {
    // (h, m, s, WHC weekday, CHT/EHC weekday, Sun/PH)
    private let vectors: [(Int, Int, Int, Int, Int, Int)] = [
        (0, 0, 0, 20, 20, 20), (7, 29, 59, 20, 20, 20), (7, 30, 0, 22, 22, 20),
        (7, 31, 59, 22, 22, 20), (7, 32, 0, 24, 24, 20), (7, 47, 59, 38, 38, 20),
        (7, 48, 0, 40, 40, 20), (8, 7, 59, 58, 40, 20), (8, 8, 0, 60, 40, 20),
        (10, 11, 30, 60, 40, 21), (10, 14, 59, 60, 40, 23), (10, 15, 0, 58, 38, 25),
        (10, 22, 59, 52, 32, 25), (10, 23, 0, 50, 30, 25), (10, 42, 59, 32, 30, 25),
        (10, 43, 0, 30, 30, 25), (16, 29, 59, 30, 30, 25), (16, 30, 0, 32, 32, 25),
        (16, 37, 59, 38, 38, 25), (16, 38, 0, 40, 40, 25), (16, 57, 59, 58, 40, 25),
        (16, 58, 0, 60, 40, 25), (18, 59, 59, 60, 40, 25), (19, 0, 0, 58, 38, 25),
        (19, 14, 59, 44, 24, 25), (19, 15, 0, 44, 24, 23), (19, 17, 59, 42, 22, 21),
        (19, 18, 0, 40, 20, 21), (19, 19, 0, 40, 20, 20), (19, 37, 59, 22, 20, 20),
        (19, 38, 0, 20, 20, 20), (23, 59, 59, 20, 20, 20),
    ]

    func testSharedVectors() {
        for (h, m, s, w, c, sun) in vectors {
            let t = h * 3600 + m * 60 + s
            let label = String(format: "%02d:%02d:%02d", h, m, s)
            XCTAssertEqual(TollEngine.query(.whc, secOfDay: t, sundayOrPH: false).dollars, w,
                           "WHC weekday @\(label)")
            XCTAssertEqual(TollEngine.query(.cht, secOfDay: t, sundayOrPH: false).dollars, c,
                           "CHT weekday @\(label)")
            XCTAssertEqual(TollEngine.query(.ehc, secOfDay: t, sundayOrPH: false).dollars, c,
                           "EHC weekday @\(label)")
            XCTAssertEqual(TollEngine.query(.whc, secOfDay: t, sundayOrPH: true).dollars, sun,
                           "Sun/PH @\(label)")
        }
    }

    func testMinuteSweepConsistency() {
        for sunPH in [false, true] {
            for crossing in TollEngine.Crossing.allCases {
                var prev = TollEngine.query(crossing, secOfDay: 0, sundayOrPH: sunPH).dollars
                for t in stride(from: 60, to: 86400, by: 60) {
                    let r = TollEngine.query(crossing, secOfDay: t, sundayOrPH: sunPH)
                    XCTAssertTrue((20...60).contains(r.dollars))
                    XCTAssertLessThanOrEqual(abs(r.dollars - prev), 2)
                    prev = r.dollars
                }
            }
        }
    }

    func testNextChangeHonesty() {
        for sunPH in [false, true] {
            for t in stride(from: 0, to: 86400, by: 30) {
                let q = TollEngine.query(.whc, secOfDay: t, sundayOrPH: sunPH)
                if q.nextChangeSec < 86400 {
                    XCTAssertEqual(
                        TollEngine.query(.whc, secOfDay: q.nextChangeSec - 1,
                                         sundayOrPH: sunPH).dollars, q.dollars)
                    XCTAssertEqual(
                        TollEngine.query(.whc, secOfDay: q.nextChangeSec,
                                         sundayOrPH: sunPH).dollars, q.nextDollars)
                    XCTAssertNotEqual(q.nextDollars, q.dollars)
                }
            }
        }
    }
}

final class ProtocolTests: XCTestCase {
    func testTimeSyncLayout() {
        let d = DashProtocol.encodeTimeSync(
            now: Date(timeIntervalSince1970: 0x01020304), sunPHFlags: 0b0101)
        XCTAssertEqual([UInt8](d), [2, 0x04, 0x03, 0x02, 0x01, 0xE0, 0x01, 0x05])
    }

    func testJourneyLayout() {
        let d = DashProtocol.encodeJourney(
            captureEpoch: 100,
            entries: [.init(slot: 1, minutes: 12, colour: 3)])
        XCTAssertEqual([UInt8](d), [2, 100, 0, 0, 0, 1, 1, 12, 3])
    }

    func testMetersLayoutWithLPP() {
        let d = DashProtocol.encodeMeters(
            fetchEpoch: 1, status: 0,
            groups: [.init(name: "AB", distM: 0x0102, vacant: 3, total: 9, lpp: 120)])
        XCTAssertEqual([UInt8](d), [2, 1, 0, 0, 0, 0, 1, 0x02, 0x01, 3, 9, 120, 2, 0x41, 0x42])
    }

    func testSlotNamesLayout() {
        let d = DashProtocol.encodeSlotNames([(slot: 7, name: "獅隧")])
        XCTAssertEqual([UInt8](d.prefix(4)), [2, 1, 7, 6])  // 2 CJK chars = 6 bytes
        XCTAssertEqual(d.count, 4 + 6)
    }

    func testFuelPricesLayout() {
        var cents: [[UInt16?]] = Array(repeating: Array(repeating: nil, count: 3), count: 5)
        cents[0][0] = 3184  // Sinopec standard $31.84
        let d = DashProtocol.encodeFuelPrices(fetchEpoch: 7, cents: cents)
        XCTAssertEqual(d.count, 35)
        XCTAssertEqual([UInt8](d.prefix(7)), [2, 7, 0, 0, 0, 0x70, 0x0C])  // 3184 = 0x0C70
        XCTAssertEqual([UInt8](d.suffix(2)), [0xFF, 0xFF])  // trailing N/A
    }

    func testFuelJSONParse() {
        let json = """
        [{"type":{"en":"Standard Petrol"},"prices":[
          {"vendor":{"en":"Shell"},"price":"31.84"},
          {"vendor":{"en":"Caltex"},"price":"31.50"}]},
         {"type":{"en":"Diesel"},"prices":[
          {"vendor":{"en":"Esso"},"price":"33.72"}]}]
        """.data(using: .utf8)!
        let cents = FuelPriceService.parse(json)
        XCTAssertNotNil(cents)
        XCTAssertEqual(cents?[4][0], 3184)  // Shell standard
        XCTAssertEqual(cents?[2][0], 3150)  // Caltex standard
        XCTAssertEqual(cents?[3][2], 3372)  // Esso diesel
        XCTAssertNil(cents?[0][0])          // Sinopec missing
    }
}

final class OperatingPeriodTests: XCTestCase {
    typealias OP = OperatingPeriod

    func testNormalize() {
        XCTAssertEqual(OP.normalize("3A"), "A")
        XCTAssertEqual(OP.normalize("4J"), "J")
        XCTAssertEqual(OP.normalize("7J"), "J")
        XCTAssertEqual(OP.normalize("5T"), "T")
        XCTAssertEqual(OP.normalize(" a "), "A")
    }

    func testExplicitNoParkingWindows() {
        // P: no parking on Sun/PH, parkable Mon-Sat
        XCTAssertFalse(OP.isParkable(code: "P", dayKind: .sunPH, minutesOfDay: 12 * 60))
        XCTAssertTrue(OP.isParkable(code: "4P", dayKind: .weekday, minutesOfDay: 12 * 60))
        // S: no parking Mon-Fri 08:00-17:00 only
        XCTAssertFalse(OP.isParkable(code: "S", dayKind: .weekday, minutesOfDay: 9 * 60))
        XCTAssertFalse(OP.isParkable(code: "4S", dayKind: .weekday, minutesOfDay: 16 * 60 + 59))
        XCTAssertTrue(OP.isParkable(code: "S", dayKind: .weekday, minutesOfDay: 17 * 60))
        XCTAssertTrue(OP.isParkable(code: "S", dayKind: .weekday, minutesOfDay: 7 * 60))
        XCTAssertTrue(OP.isParkable(code: "S", dayKind: .saturday, minutesOfDay: 9 * 60))
        XCTAssertTrue(OP.isParkable(code: "S", dayKind: .sunPH, minutesOfDay: 12 * 60))
        // Everything else: always parkable (paid or free)
        for code in ["A", "B", "D", "E", "F", "G", "H", "J", "N", "Q", "T"] {
            XCTAssertTrue(OP.isParkable(code: code, dayKind: .weekday, minutesOfDay: 3 * 60))
            XCTAssertTrue(OP.isParkable(code: code, dayKind: .sunPH, minutesOfDay: 12 * 60))
        }
    }

    func testChargingWindows() {
        // A: Mon-Sat 08-24, free on Sun/PH
        XCTAssertTrue(OP.isCharging(code: "A", dayKind: .weekday, minutesOfDay: 9 * 60))
        XCTAssertFalse(OP.isCharging(code: "A", dayKind: .weekday, minutesOfDay: 7 * 60))
        XCTAssertFalse(OP.isCharging(code: "3A", dayKind: .sunPH, minutesOfDay: 12 * 60))
        // D: Sun/PH 10-22
        XCTAssertTrue(OP.isCharging(code: "3D", dayKind: .sunPH, minutesOfDay: 12 * 60))
        XCTAssertFalse(OP.isCharging(code: "D", dayKind: .sunPH, minutesOfDay: 9 * 60))
        // N: evenings 19-24 daily
        XCTAssertTrue(OP.isCharging(code: "N", dayKind: .weekday, minutesOfDay: 20 * 60))
        XCTAssertFalse(OP.isCharging(code: "4N", dayKind: .weekday, minutesOfDay: 12 * 60))
        // T: Mon-Fri 17:30-24
        XCTAssertFalse(OP.isCharging(code: "5T", dayKind: .weekday, minutesOfDay: 17 * 60))
        XCTAssertTrue(OP.isCharging(code: "T", dayKind: .weekday, minutesOfDay: 17 * 60 + 30))
        // E: 07-20 daily
        XCTAssertTrue(OP.isCharging(code: "E", dayKind: .sunPH, minutesOfDay: 7 * 60))
        XCTAssertFalse(OP.isCharging(code: "E", dayKind: .saturday, minutesOfDay: 20 * 60))
    }
}
