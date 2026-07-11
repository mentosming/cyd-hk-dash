// 隧道收費 widget — the flagship: tolls are a pure function of the clock, so the
// timeline is precomputed from TollEngine's own breakpoints. Zero network, and
// it flips at the exact second the price changes.
import SwiftUI
import WidgetKit

struct TollEntry: TimelineEntry {
    let date: Date
    let tolls: [(crossing: TollEngine.Crossing, result: TollEngine.Result)]
    let secOfDay: Int
}

struct TollProvider: TimelineProvider {
    private let holidays = HolidayService()

    private func entry(at date: Date) -> TollEntry {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = WidgetFormat.hkTimeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let sec = (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
        let sunPH = holidays.isSundayOrPH(date)
        return TollEntry(
            date: date,
            tolls: TollEngine.Crossing.allCases.map {
                ($0, TollEngine.query($0, secOfDay: sec, sundayOrPH: sunPH))
            },
            secOfDay: sec)
    }

    func placeholder(in context: Context) -> TollEntry { entry(at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (TollEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TollEntry>) -> Void) {
        // Walk TollEngine's next-change boundaries forward for ~12 h. Each entry
        // is scheduled exactly when a price changes (ramp steps are 2 min apart,
        // plateaus are hours), so WidgetKit renders the new price on time.
        var entries: [TollEntry] = []
        var cursor = Date()
        let horizon = cursor.addingTimeInterval(12 * 3600)

        while cursor < horizon, entries.count < 100 {
            let e = entry(at: cursor)
            entries.append(e)

            // Earliest next change across the three crossings. Land exactly on
            // the boundary — a 60 s floor here would overshoot a ramp step and
            // leave the widget one $2 step stale for up to a minute.
            let nextSec = e.tolls.map(\.result.nextChangeSec).min() ?? 86400
            let delta = nextSec > e.secOfDay
                ? TimeInterval(nextSec - e.secOfDay)
                : TimeInterval(86400 - e.secOfDay)  // rolls past midnight
            cursor = cursor.addingTimeInterval(max(delta, 1))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TollWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: TollEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreenView
        case .accessoryInline:
            Text("三隧 " + entry.tolls.map { "$\($0.result.dollars)" }.joined(separator: "/"))
        case .systemSmall: smallView
        default: mediumView
        }
    }

    private var lockScreenView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("隧道收費").font(.caption2).opacity(0.7)
            HStack(spacing: 10) {
                ForEach(entry.tolls, id: \.crossing.name) { t in
                    VStack(spacing: 0) {
                        Text(t.crossing.name).font(.system(size: 9))
                        Text("$\(t.result.dollars)").font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("隧道收費", systemImage: "dollarsign.circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Brand.teal)
            ForEach(entry.tolls, id: \.crossing.name) { t in
                HStack {
                    Text(t.crossing.name).font(.subheadline)
                    Spacer()
                    Text("$\(t.result.dollars)")
                        .font(.subheadline.weight(.bold)).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            nextChangeLine.font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("隧道收費", systemImage: "dollarsign.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.teal)
                Spacer()
                nextChangeLine.font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(entry.tolls, id: \.crossing.name) { t in
                    VStack(spacing: 4) {
                        Text(t.crossing.name).font(.caption).foregroundStyle(.secondary)
                        Text("$\(t.result.dollars)")
                            .font(.title2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Brand.teal, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    /// The soonest upcoming change across the three crossings.
    private var nextChangeLine: some View {
        let soonest = entry.tolls
            .filter { $0.result.nextChangeSec < 86400 }
            .min { $0.result.nextChangeSec < $1.result.nextChangeSec }
        return Group {
            if let s = soonest,
               let txt = WidgetFormat.nextTollText(s.result, secOfDay: entry.secOfDay) {
                Text("\(s.crossing.name) \(txt)")
            } else {
                Text("今日冇再轉價")
            }
        }
    }
}

struct TollWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TollWidget", provider: TollProvider()) { entry in
            TollWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "hkcardash://tab/dashboard"))
        }
        .configurationDisplayName("隧道收費")
        .description("三條過海隧道現時時段收費同下次轉價時間。")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryInline])
    }
}
