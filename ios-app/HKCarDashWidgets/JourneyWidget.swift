// 過海時間 widget — live journey times from the TD feed. Network-backed, so it
// refreshes on WidgetKit's budget (~15 min) and always shows how old the data is.
import SwiftUI
import WidgetKit

struct JourneyEntry: TimelineEntry {
    let date: Date
    let minutes: [UInt8: UInt8]   // slot -> minutes (sentinels preserved)
    let colours: [UInt8: UInt8]
    let fetchedAt: Date?
    let failed: Bool
}

struct JourneyProvider: TimelineProvider {
    private static let cacheKey = "widgetJourneyCache"       // [slot: minutes]
    private static let cacheColourKey = "widgetJourneyColour"
    private static let cacheAtKey = "widgetJourneyAt"

    private func cached() -> JourneyEntry {
        let mins = (AppGroup.defaults.dictionary(forKey: Self.cacheKey) as? [String: Int]) ?? [:]
        let cols = (AppGroup.defaults.dictionary(forKey: Self.cacheColourKey) as? [String: Int]) ?? [:]
        let at = AppGroup.defaults.double(forKey: Self.cacheAtKey)
        return JourneyEntry(
            date: Date(),
            minutes: Dictionary(uniqueKeysWithValues: mins.compactMap {
                guard let k = UInt8($0.key) else { return nil }
                return (k, UInt8(clamping: $0.value))
            }),
            colours: Dictionary(uniqueKeysWithValues: cols.compactMap {
                guard let k = UInt8($0.key) else { return nil }
                return (k, UInt8(clamping: $0.value))
            }),
            fetchedAt: at > 0 ? Date(timeIntervalSince1970: at) : nil,
            failed: false)
    }

    private func store(_ entries: [DashProtocol.JourneyEntry]) {
        AppGroup.defaults.set(
            Dictionary(uniqueKeysWithValues: entries.map { ("\($0.slot)", Int($0.minutes)) }),
            forKey: Self.cacheKey)
        AppGroup.defaults.set(
            Dictionary(uniqueKeysWithValues: entries.map { ("\($0.slot)", Int($0.colour)) }),
            forKey: Self.cacheColourKey)
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: Self.cacheAtKey)
    }

    func placeholder(in context: Context) -> JourneyEntry {
        JourneyEntry(date: Date(), minutes: [1: 8, 2: 12, 3: 6, 4: 10, 5: 15, 6: 7],
                     colours: [1: 3, 2: 2, 3: 3, 4: 3, 5: 1, 6: 3],
                     fetchedAt: Date(), failed: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (JourneyEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : cached())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JourneyEntry>) -> Void) {
        Task {
            var entry: JourneyEntry
            do {
                let (_, entries) = try await JourneyTimeService().fetch()
                store(entries)
                entry = cached()
            } catch {
                entry = cached()   // fall back to the last good data, aged
                entry = JourneyEntry(date: entry.date, minutes: entry.minutes,
                                     colours: entry.colours, fetchedAt: entry.fetchedAt,
                                     failed: entry.fetchedAt == nil)
            }
            // The TD feed updates every 2 min; WidgetKit will not honour that,
            // so ask for ~15 min and let the "更新於" line manage expectations.
            let next = Date().addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct JourneyWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: JourneyEntry

    // Harbour slots: 1-3 = 港→九 (CH/EH/WH), 4-6 = 九→港
    private let tunnels: [(name: String, toKln: UInt8, toHK: UInt8)] = [
        ("紅隧", 1, 4), ("東隧", 2, 5), ("西隧", 3, 6),
    ]

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreenView
        default: mediumView
        }
    }

    private var lockScreenView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("過海 港→九").font(.caption2).opacity(0.7)
            HStack(spacing: 12) {
                ForEach(tunnels, id: \.name) { t in
                    VStack(spacing: 0) {
                        Text(t.name).font(.system(size: 9))
                        Text(WidgetFormat.minutesText(entry.minutes[t.toKln] ?? 0xFF))
                            .font(.system(size: 15, weight: .bold)).monospacedDigit()
                    }
                }
            }
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("過海隧道", systemImage: "car.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(Brand.teal)
                Spacer()
                Text(entry.fetchedAt == nil ? "冇數據" : WidgetFormat.ageText(entry.fetchedAt))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                Text("").frame(width: 40)
                Text("港→九").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Text("九→港").font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }

            ForEach(tunnels, id: \.name) { t in
                HStack(spacing: 0) {
                    Text(t.name).font(.subheadline.weight(.medium))
                        .frame(width: 40, alignment: .leading)
                    minutesCell(slot: t.toKln)
                    minutesCell(slot: t.toHK)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func minutesCell(slot: UInt8) -> some View {
        let m = entry.minutes[slot] ?? 0xFF
        let c = entry.colours[slot] ?? 0
        return HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(WidgetFormat.minutesText(m))
                .font(.title3.weight(.bold)).monospacedDigit()
                .foregroundStyle(WidgetFormat.isLiveMinutes(m) ? Brand.journeyColour(c) : .secondary)
            if WidgetFormat.isLiveMinutes(m) {
                Text("分").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct JourneyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "JourneyWidget", provider: JourneyProvider()) { entry in
            JourneyWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "hkcardash://tab/dashboard"))
        }
        .configurationDisplayName("過海隧道時間")
        .description("三條過海隧道雙向實時行車時間。")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}
