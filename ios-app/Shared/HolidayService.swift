// HK public holidays from the 1823 iCal JSON feed, cached in UserDefaults
// and refreshed opportunistically (the feed covers the current + next year).
import Foundation

final class HolidayService {
    static let url = URL(string: "https://www.1823.gov.hk/common/ical/en.json")!
    private static let cacheKey = "phDates"       // ["yyyyMMdd"]
    private static let cachedAtKey = "phFetchedAt"

    private var dates: Set<String>

    init() {
        dates = Set(AppGroup.defaults.stringArray(forKey: Self.cacheKey) ?? [])
    }

    /// bits 0-3: today / +1 / +2 / +3 days (HK local) use the Sun/PH schedule.
    var sunPHFlags: UInt8 {
        var flags: UInt8 = 0
        for i in 0..<4 where isSundayOrPH(Date().addingTimeInterval(Double(i) * 86400)) {
            flags |= 1 << i
        }
        return flags
    }

    /// True if `date` (HK time) is a Sunday or a public holiday.
    func isSundayOrPH(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        if cal.component(.weekday, from: date) == 1 { return true }
        return dates.contains(Self.dayKey(date))
    }

    func refreshIfStale() async {
        let fetchedAt = AppGroup.defaults.double(forKey: Self.cachedAtKey)
        let weekAgo = Date().timeIntervalSince1970 - 7 * 86400
        guard dates.isEmpty || fetchedAt < weekAgo else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.url)
            let parsed = Self.parse(data)
            guard !parsed.isEmpty else { return }
            dates = parsed
            AppGroup.defaults.set(Array(parsed), forKey: Self.cacheKey)
            AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: Self.cachedAtKey)
        } catch {
            // keep the stale cache; Sundays still work without it
        }
    }

    /// 1823 vcalendar JSON: vevent[].dtstart = ["yyyyMMdd", ...]
    static func parse(_ data: Data) -> Set<String> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cal = root["vcalendar"] as? [[String: Any]],
              let events = cal.first?["vevent"] as? [[String: Any]] else { return [] }
        var out = Set<String>()
        for ev in events {
            if let dt = ev["dtstart"] as? [Any], let day = dt.first as? String, day.count == 8 {
                out.insert(day)
            }
        }
        return out
    }

    static func dayKey(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        return df.string(from: date)
    }
}
