// The toll widget's whole value is that it flips at the exact moment the price
// changes. That relies on TollEngine.nextChangeSec being honest, so assert the
// timeline logic against the official schedule vectors (docs/toll-schedule.md).
import CoreLocation
import MapKit
import XCTest
@testable import HKCarDash

final class TollTimelineTests: XCTestCase {

    /// Walk the same next-change chain the widget's TimelineProvider walks and
    /// check every hop lands exactly on a real price change.
    func testTimelineHopsLandOnRealChanges() {
        for sunPH in [false, true] {
            var sec = 0
            var hops = 0
            while sec < 86400, hops < 200 {
                let results = TollEngine.Crossing.allCases.map {
                    TollEngine.query($0, secOfDay: sec, sundayOrPH: sunPH)
                }
                let next = results.map(\.nextChangeSec).min() ?? 86400
                guard next < 86400 else { break }

                // At least one crossing must actually change value at `next`
                let changed = TollEngine.Crossing.allCases.contains { c in
                    TollEngine.query(c, secOfDay: next - 1, sundayOrPH: sunPH).dollars
                        != TollEngine.query(c, secOfDay: next, sundayOrPH: sunPH).dollars
                }
                XCTAssertTrue(changed,
                              "timeline hop to \(next)s (\(sunPH ? "Sun/PH" : "weekday")) changes nothing")
                sec = next
                hops += 1
            }
            XCTAssertGreaterThan(hops, 5, "expected several price changes per day")
            XCTAssertLessThan(hops, 200, "timeline must not thrash")
        }
    }

    /// A weekday morning ramp steps every 2 minutes — the timeline must not
    /// collapse those into one entry, or the widget would show a stale price.
    func testRampStepsAreDistinctEntries() {
        // 07:31 weekday: CHT is mid-ramp, next step is 07:32
        let sec = 7 * 3600 + 31 * 60
        let r = TollEngine.query(.cht, secOfDay: sec, sundayOrPH: false)
        XCTAssertEqual(r.nextChangeSec, 7 * 3600 + 32 * 60)
        XCTAssertNotEqual(r.nextDollars, r.dollars)
    }

    func testNoChangesLateAtNight() {
        let r = TollEngine.query(.whc, secOfDay: 23 * 3600, sundayOrPH: false)
        XCTAssertEqual(r.nextChangeSec, 86400)   // widget shows "今日冇再轉價"
        XCTAssertEqual(r.dollars, 20)
    }
}

final class MapRegionTests: XCTestCase {
    private func makeStore() -> MeterStore {
        let store = MeterStore()
        let csv = """
        \u{FEFF}2026-07-11\r
        ,,,,,,,,,,,,,,,,,,,,,,,\r
        PoleId,ParkingSpaceId,Region,Region_tc,Region_sc,District,District_tc,District_sc,SubDistrict,SubDistrict_tc,SubDistrict_sc,Street,Street_tc,Street_sc,SectionOfStreet,SectionOfStreet_tc,SectionOfStreet_sc,Latitude,Longitude,VehicleType,LPP,OperatingPeriod,TimeUnit,PaymentUnit\r
        1,1A,HONG KONG,香港島,香港岛,WAN CHAI,灣仔,湾仔,WAN CHAI,灣仔,湾仔,LOCKHART ROAD,駱克道,骆克道,X,X,X,22.2800,114.1750,A,120,A,15,2\r
        2,2A,KOWLOON,九龍,九龙,YAU TSIM MONG,油尖旺,油尖旺,MONG KOK,旺角,旺角,NATHAN ROAD,彌敦道,弥敦道,X,X,X,22.3200,114.1690,A,60,A,15,2\r
        3,3A,KOWLOON,九龍,九龙,YAU TSIM MONG,油尖旺,油尖旺,MONG KOK,旺角,旺角,NATHAN ROAD,彌敦道,弥敦道,X,X,X,22.3201,114.1691,G,60,A,15,2\r
        90001,90001A,KOWLOON,九龍,九龙,TEST,測試,测试,TEST,測試,测试,TEST ROAD,測試路,测试路,X,X,X,22.3000,114.1700,A,60,A,15,2\r
        """
        store.ingest(Data(csv.utf8))
        return store
    }

    /// The map only materialises pins inside the visible rect; make sure the
    /// region query actually filters (a bug here means 20k annotations).
    func testRegionQueryFiltersToBounds() {
        let store = makeStore()
        // Goods-vehicle bay (G) and the >90000 test meter must be excluded
        XCTAssertEqual(store.count, 2)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.2800, longitude: 114.1750),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        let hits = store.spaces(inRegion: region)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.street, "駱克道")
        XCTAssertEqual(hits.first?.lpp, 120)
    }

    /// MKMapView can hand back a degenerate region before its first layout —
    /// Int(Double.nan) traps, so this must return empty, not crash.
    func testRegionQuerySurvivesDegenerateRegions() {
        let store = makeStore()
        let bad = [
            MKCoordinateRegion(center: .init(latitude: .nan, longitude: .nan),
                               span: .init(latitudeDelta: .nan, longitudeDelta: .nan)),
            MKCoordinateRegion(center: .init(latitude: 22.3, longitude: 114.17),
                               span: .init(latitudeDelta: 0, longitudeDelta: 0)),
            MKCoordinateRegion(center: .init(latitude: 22.3, longitude: 114.17),
                               span: .init(latitudeDelta: 180, longitudeDelta: 360)),
        ]
        for r in bad { XCTAssertTrue(store.spaces(inRegion: r).isEmpty) }
    }

    /// Concurrent loads must not publish `spaces` and `grid` out of step —
    /// that used to index the new array with a stale grid index and crash.
    func testConcurrentIngestAndRegionQueriesAreSafe() {
        let store = makeStore()
        let done = expectation(description: "concurrent")
        done.expectedFulfillmentCount = 2

        DispatchQueue.global().async {
            for _ in 0..<200 { store.ingest(Data(self.makeCSV().utf8)) }
            done.fulfill()
        }
        DispatchQueue.global().async {
            let r = MKCoordinateRegion(
                center: .init(latitude: 22.29, longitude: 114.17),
                span: .init(latitudeDelta: 0.1, longitudeDelta: 0.1))
            for _ in 0..<200 { _ = store.spaces(inRegion: r); _ = store.count; _ = store.allIDs }
            done.fulfill()
        }
        wait(for: [done], timeout: 20)
    }

    private func makeCSV() -> String {
        """
        \u{FEFF}2026-07-11\r
        ,,,,,,,,,,,,,,,,,,,,,,,\r
        PoleId,ParkingSpaceId,Region,Region_tc,Region_sc,District,District_tc,District_sc,SubDistrict,SubDistrict_tc,SubDistrict_sc,Street,Street_tc,Street_sc,SectionOfStreet,SectionOfStreet_tc,SectionOfStreet_sc,Latitude,Longitude,VehicleType,LPP,OperatingPeriod,TimeUnit,PaymentUnit\r
        1,1A,HONG KONG,香港島,香港岛,WAN CHAI,灣仔,湾仔,WAN CHAI,灣仔,湾仔,LOCKHART ROAD,駱克道,骆克道,X,X,X,22.2800,114.1750,A,120,A,15,2\r
        2,2A,KOWLOON,九龍,九龙,YAU TSIM MONG,油尖旺,油尖旺,MONG KOK,旺角,旺角,NATHAN ROAD,彌敦道,弥敦道,X,X,X,22.3200,114.1690,A,60,A,15,2\r
        """
    }
}

final class DemoModeTests: XCTestCase {
    /// The TD CSV is a third-party file; a duplicate ParkingSpaceId must not
    /// trap Dictionary(uniqueKeysWithValues:) and crash the map in demo mode.
    func testOccupancySnapshotToleratesDuplicateIDs() {
        let snap = DemoMode.occupancySnapshot(for: ["1A", "1A", "2B"])
        XCTAssertEqual(snap.count, 2)
        XCTAssertNotNil(snap["1A"])
        XCTAssertNotNil(snap["2B"])
    }

    /// Demo occupancy must be stable across calls, or pins would flicker colour
    /// on every 60 s refresh.
    func testOccupancyIsDeterministic() {
        let a = DemoMode.occupancy(for: "22730A")
        let b = DemoMode.occupancy(for: "22730A")
        XCTAssertEqual(a.working, b.working)
        XCTAssertEqual(a.vacant, b.vacant)
    }
}
