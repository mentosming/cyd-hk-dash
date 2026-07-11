// Official TD metered-parking OperatingPeriod table (data spec, 2026-07).
// Semantics: inside operating hours = paid parking allowed; outside = free
// parking allowed EXCEPT the explicit no-parking windows some codes define
// (P: no parking on Sundays; S: no parking Mon–Fri 08:00–17:00).
import Foundation

enum OperatingPeriod {
    struct Window {
        let startMin: Int   // minutes since midnight
        let endMin: Int     // exclusive; 1440 = midnight
    }

    enum DayKind {
        case weekday        // Mon–Fri
        case saturday
        case sunPH          // Sunday or public holiday
    }

    /// True if a private car may park at this space right now (paid or free).
    static func isParkable(code rawCode: String, dayKind: DayKind, minutesOfDay m: Int) -> Bool {
        let code = normalize(rawCode)
        // Explicit no-parking windows override everything.
        switch code {
        case "P":
            if dayKind == .sunPH { return false }  // spec: "no parking on Sundays"
        case "S":
            if dayKind == .weekday && m >= 8 * 60 && m < 17 * 60 { return false }
        default:
            break
        }
        return true
    }

    /// True if the meter is charging now (inside operating hours). Outside
    /// operating hours parking is free (when parkable at all).
    static func isCharging(code rawCode: String, dayKind: DayKind, minutesOfDay m: Int) -> Bool {
        for w in operatingWindows(code: normalize(rawCode), dayKind: dayKind) {
            if m >= w.startMin && m < w.endMin { return true }
        }
        return false
    }

    /// Strip the numeric prefix variants (3A→A, 4J/7J→J, 5T→T, …).
    static func normalize(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        return String(s.drop(while: { $0.isNumber }))
    }

    static func operatingWindows(code: String, dayKind: DayKind) -> [Window] {
        func w(_ sh: Int, _ sm: Int, _ eh: Int, _ em: Int) -> Window {
            Window(startMin: sh * 60 + sm, endMin: eh * 60 + em)
        }
        switch code {
        case "A":  // Mon–Sat 08:00–24:00
            return dayKind == .sunPH ? [] : [w(8, 0, 24, 0)]
        case "B":  // Mon–Sat 08:00–20:00
            return dayKind == .sunPH ? [] : [w(8, 0, 20, 0)]
        case "D":  // Mon–Sat 08:00–24:00; Sun/PH 10:00–22:00
            return dayKind == .sunPH ? [w(10, 0, 22, 0)] : [w(8, 0, 24, 0)]
        case "E": return [w(7, 0, 20, 0)]   // daily
        case "F": return [w(8, 0, 21, 0)]   // daily
        case "G": return [w(7, 0, 19, 0)]   // daily
        case "H": return [w(8, 0, 20, 0)]   // daily
        case "J": return [w(8, 0, 24, 0)]   // daily
        case "N": return [w(19, 0, 24, 0)]  // daily evenings
        case "P":  // Mon–Sat 08:00–20:00; Sundays: no parking (handled above)
            return dayKind == .sunPH ? [] : [w(8, 0, 20, 0)]
        case "Q":  // Mon–Sat 08:00–20:00; Sun/PH 10:00–22:00
            return dayKind == .sunPH ? [w(10, 0, 22, 0)] : [w(8, 0, 20, 0)]
        case "S":  // Mon–Fri 17:00–24:00; Sat 08:00–24:00; Sun/PH 10:00–22:00
            switch dayKind {
            case .weekday: return [w(17, 0, 24, 0)]
            case .saturday: return [w(8, 0, 24, 0)]
            case .sunPH: return [w(10, 0, 22, 0)]
            }
        case "T":  // Mon–Fri 17:30–24:00; Sat 08:00–24:00; Sun/PH 10:00–22:00
            switch dayKind {
            case .weekday: return [w(17, 30, 24, 0)]
            case .saturday: return [w(8, 0, 24, 0)]
            case .sunPH: return [w(10, 0, 22, 0)]
            }
        default:  // unknown code — assume standard A hours, parkable
            return dayKind == .sunPH ? [] : [w(8, 0, 24, 0)]
        }
    }

    /// Resolve HK-local day kind + minutes for a date.
    static func context(for date: Date, isSunPH: Bool) -> (DayKind, Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: date)
        let dayKind: DayKind
        if isSunPH {
            dayKind = .sunPH
        } else if comps.weekday == 7 {
            dayKind = .saturday
        } else {
            dayKind = .weekday
        }
        return (dayKind, (comps.hour ?? 0) * 60 + (comps.minute ?? 0))
    }
}
