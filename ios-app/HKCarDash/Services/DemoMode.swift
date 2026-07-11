// Demo mode — lets an App Review reviewer (or a curious user) see every screen
// without the physical display. It only fakes the *hardware-dependent* bits:
// the connection state and a plausible occupancy snapshot. Journey times, tolls
// and fuel prices stay real, because they never needed the hardware.
import Foundation

enum DemoMode {
    /// Also used as the @AppStorage key in views so SwiftUI observes the flip.
    static let key = "demoModeEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static let deviceInfo = "fw 0.2 · 示範模式"
    static let connectionState = "已連接（示範）"

    /// Deterministic occupancy so the map always shows a believable mix.
    /// Hash of the space id decides the state — stable across refreshes.
    static func occupancy(for id: String) -> MeterQueryService.Occupancy {
        var h: UInt64 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt64(b) }
        switch h % 10 {
        case 0: return .init(working: false, vacant: false)   // 10% suspended
        case 1, 2, 3: return .init(working: true, vacant: true)  // 30% vacant
        default: return .init(working: true, vacant: false)
        }
    }

    static func occupancySnapshot(for ids: [String]) -> [String: MeterQueryService.Occupancy] {
        // NOT `uniqueKeysWithValues`: ParkingSpaceId comes straight from a
        // third-party CSV, and one duplicate would trap and crash the app.
        Dictionary(ids.map { ($0, occupancy(for: $0)) }, uniquingKeysWith: { a, _ in a })
    }
}
