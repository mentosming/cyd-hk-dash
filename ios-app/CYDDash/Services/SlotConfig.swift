// User-configurable routes for slots 7-9 (the 主要幹道 page).
// Selection is stored in UserDefaults; display names go to the device
// via the SlotNames payload.
import Foundation

struct RouteOption: Identifiable, Equatable {
    let location: String     // JTI LOCATION_ID
    let destination: String  // JTI DESTINATION_ID
    let name: String         // Chinese display name (≤8 chars for the device)
    var id: String { "\(location)|\(destination)" }
}

enum SlotConfig {
    static let configurableSlots: [UInt8] = [7, 8, 9]

    /// Common LOCATION→DESTINATION pairs (verified in the live JTI v2 feed).
    static let options: [RouteOption] = [
        RouteOption(location: "SJ1", destination: "LRT", name: "獅隧"),
        RouteOption(location: "SJ2", destination: "TCT", name: "大老山"),
        RouteOption(location: "SJ2", destination: "TSCA", name: "青沙"),
        RouteOption(location: "SJ3", destination: "LRT", name: "獅隧·吐露"),
        RouteOption(location: "SJ3", destination: "TCT", name: "大老山·吐露"),
        RouteOption(location: "SJ3", destination: "TSCA", name: "青沙·吐露"),
        RouteOption(location: "SJ1", destination: "SMT", name: "城隧"),
        RouteOption(location: "SJ4", destination: "TKTL", name: "屯赤隧道"),
        RouteOption(location: "SJ4", destination: "TKTM", name: "屯門隧道"),
        RouteOption(location: "SJ4", destination: "TMCLK", name: "屯赤往機場"),
        RouteOption(location: "SJ4", destination: "ATL", name: "機場隧道"),
        RouteOption(location: "SJ5", destination: "TWTM", name: "屯門公路"),
        RouteOption(location: "SJ5", destination: "TWCP", name: "青嶼幹線"),
        RouteOption(location: "N08", destination: "TKOLTT", name: "將藍隧道"),
        RouteOption(location: "N08", destination: "TKOT", name: "將隧"),
        RouteOption(location: "H4", destination: "ABT", name: "香港仔隧道"),
    ]

    private static let defaults: [UInt8: String] = [
        7: "SJ1|LRT", 8: "SJ2|TCT", 9: "SJ2|TSCA",
    ]

    static func selected(slot: UInt8) -> RouteOption {
        let key = UserDefaults.standard.string(forKey: "slot\(slot)") ?? defaults[slot]!
        return options.first { $0.id == key }
            ?? options.first { $0.id == defaults[slot]! }!
    }

    static func setSelected(slot: UInt8, option: RouteOption) {
        UserDefaults.standard.set(option.id, forKey: "slot\(slot)")
    }

    /// Full slot list for the journey fetch: fixed harbour slots + configured.
    static func journeySlots() -> [(slot: UInt8, location: String, destination: String)] {
        var slots = DashProtocol.fixedSlots
        for s in configurableSlots {
            let opt = selected(slot: s)
            slots.append((s, opt.location, opt.destination))
        }
        return slots
    }

    static func slotNamesPayloadEntries() -> [(slot: UInt8, name: String)] {
        configurableSlots.map { ($0, selected(slot: $0).name) }
    }
}
