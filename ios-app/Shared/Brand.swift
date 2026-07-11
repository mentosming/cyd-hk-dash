// Shared design tokens (app + widgets). Teal matches HKeToll's brand colour so
// the toll pills read as "the same thing you see on the road signs".
import SwiftUI

enum Brand {
    static let teal = Color(red: 0x18 / 255, green: 0xAD / 255, blue: 0x8E / 255)
    static let tealDark = Color(red: 0x0F / 255, green: 0x8A / 255, blue: 0x70 / 255)
    static let amber = Color(red: 0xFF / 255, green: 0xB0 / 255, blue: 0x20 / 255)
    static let red = Color(red: 0xFF / 255, green: 0x4D / 255, blue: 0x4F / 255)
    static let green = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)

    /// TD COLOUR_ID → SwiftUI colour (1 red, 2 amber, 3 green).
    static func journeyColour(_ id: UInt8) -> Color {
        switch id {
        case 1: return red
        case 2: return amber
        case 3: return green
        default: return .secondary
        }
    }
}

enum WidgetFormat {
    static let hkTimeZone = TimeZone(identifier: "Asia/Hong_Kong")!

    /// Journey minutes → display text, handling the protocol's sentinels.
    static func minutesText(_ m: UInt8) -> String {
        switch m {
        case DashProtocol.minutesNA: return "--"
        case DashProtocol.minutesCongestion: return "擠塞"
        case DashProtocol.minutesClosed: return "封閉"
        default: return "\(m)"
        }
    }

    static func isLiveMinutes(_ m: UInt8) -> Bool { m < DashProtocol.minutesClosed }

    /// Next toll change: imminent → count down; hours away → wall-clock time.
    /// ("283 分後" is true and useless.) Kept identical across the app, the
    /// widgets, the firmware and the web demo.
    static func nextTollText(_ r: TollEngine.Result, secOfDay: Int) -> String? {
        guard r.nextChangeSec < 86400 else { return nil }
        let mins = (r.nextChangeSec - secOfDay + 59) / 60
        if mins < 60 { return "\(mins)分後 $\(r.nextDollars)" }
        let h = r.nextChangeSec / 3600, m = (r.nextChangeSec % 3600) / 60
        return String(format: "%02d:%02d $%d", h, m, r.nextDollars)
    }

    static func ageText(_ date: Date?) -> String {
        guard let d = date else { return "--" }
        let mins = Int(-d.timeIntervalSinceNow / 60)
        if mins < 1 { return "啱啱更新" }
        if mins < 60 { return "\(mins) 分鐘前" }
        return "\(mins / 60) 小時前"
    }
}
