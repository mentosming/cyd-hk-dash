// Parity tests — same shared vectors as firmware test_toll_engine
// (docs/toll-schedule.md). If these change, both sides must change.
import XCTest
@testable import CYDDash

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
            now: Date(timeIntervalSince1970: 0x01020304), todaySunPH: true, tomorrowSunPH: false)
        XCTAssertEqual([UInt8](d), [1, 0x04, 0x03, 0x02, 0x01, 0xE0, 0x01, 0x01])
    }

    func testJourneyLayout() {
        let d = DashProtocol.encodeJourney(
            captureEpoch: 100,
            entries: [.init(slot: 1, minutes: 12, colour: 3)])
        XCTAssertEqual([UInt8](d), [1, 100, 0, 0, 0, 1, 1, 12, 3])
    }

    func testMetersLayout() {
        let d = DashProtocol.encodeMeters(
            fetchEpoch: 1, status: 0,
            groups: [.init(name: "AB", distM: 0x0102, vacant: 3, total: 9)])
        XCTAssertEqual([UInt8](d), [1, 1, 0, 0, 0, 0, 1, 0x02, 0x01, 3, 9, 2, 0x41, 0x42])
    }
}
