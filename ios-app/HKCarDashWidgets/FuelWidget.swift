// 油價 widget — cheapest pump price per fuel type (Consumer Council data).
import SwiftUI
import WidgetKit

struct FuelEntry: TimelineEntry {
    let date: Date
    /// (type name, cheapest price in cents, cheapest brand) — nil when unavailable
    let cheapest: [(type: String, cents: UInt16, brand: String)]
    let fetchedAt: Date?
}

struct FuelProvider: TimelineProvider {
    private let typeNames = ["無鉛", "特級", "柴油"]
    private let brandNames = ["中石化", "中國石油", "加德士", "埃索", "蜆殼"]

    private func makeEntry(from svc: FuelPriceService) -> FuelEntry {
        var out: [(String, UInt16, String)] = []
        for t in 0..<3 {
            var best: (UInt16, Int)?
            for b in 0..<5 {
                // Bounds-checked: a malformed App Group cache would otherwise
                // crash the widget rather than just showing 冇數據.
                guard b < svc.cents.count, t < svc.cents[b].count,
                      let c = svc.cents[b][t] else { continue }
                if best == nil || c < best!.0 { best = (c, b) }
            }
            if let b = best { out.append((typeNames[t], b.0, brandNames[b.1])) }
        }
        return FuelEntry(date: Date(), cheapest: out, fetchedAt: svc.fetchedAt)
    }

    func placeholder(in context: Context) -> FuelEntry {
        FuelEntry(date: Date(),
                  cheapest: [("無鉛", 3184, "蜆殼"), ("特級", 3364, "埃索"), ("柴油", 3372, "中石化")],
                  fetchedAt: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (FuelEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : makeEntry(from: FuelPriceService()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FuelEntry>) -> Void) {
        Task {
            let svc = FuelPriceService()
            _ = await svc.refreshIfStale()          // no-op if fresher than 6 h
            let next = Date().addingTimeInterval(6 * 3600)
            completion(Timeline(entries: [makeEntry(from: svc)], policy: .after(next)))
        }
    }
}

struct FuelWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: FuelEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("最平油價", systemImage: "fuelpump.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(Brand.teal)

            if entry.cheapest.isEmpty {
                Text("冇數據").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entry.cheapest, id: \.type) { c in
                    HStack(spacing: 4) {
                        Text(c.type).font(.caption).foregroundStyle(.secondary)
                            .frame(width: 30, alignment: .leading)
                        Text(priceText(c.cents))
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                        if family != .systemSmall {
                            Text(c.brand).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
            Text("消委會 · \(WidgetFormat.ageText(entry.fetchedAt))")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func priceText(_ cents: UInt16) -> String {
        String(format: "$%d.%02d", cents / 100, cents % 100)
    }
}

struct FuelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FuelWidget", provider: FuelProvider()) { entry in
            FuelWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "hkcardash://tab/dashboard"))
        }
        .configurationDisplayName("油價")
        .description("消委會五間油公司牌價，每種油最平嗰間。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
