// 今日 — the standalone heart of the app. Everything here works with no
// display connected: tolls are computed locally, journey times and fuel prices
// come straight from the public feeds.
import SwiftUI
import WidgetKit

struct DashboardView: View {
    @EnvironmentObject var coordinator: DashCoordinator
    @State private var now = Date()

    private let clock = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var live: LiveDataStore { coordinator.live }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TollCard(now: now, holidays: live.holidays)
                    HarbourCard(live: live)
                    RoutesCard(live: live)
                    FuelCard(live: live)
                    AttributionFooter()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今日")
            .refreshable { await live.refreshAll(force: true) }
            .task { await live.refreshAll() }
            .onReceive(clock) { t in
                now = t
                Task { await live.refreshJourney() }   // throttled to 110 s inside
            }
        }
    }
}

// MARK: - 隧道收費

private struct TollCard: View {
    let now: Date
    let holidays: HolidayService

    var body: some View {
        let sec = Self.secondsOfDay(now)
        let sunPH = holidays.isSundayOrPH(now)

        Card(title: "隧道收費", icon: "dollarsign.circle.fill",
             trailing: sunPH ? "假日收費" : nil) {
            HStack(spacing: 10) {
                ForEach(TollEngine.Crossing.allCases, id: \.name) { c in
                    let r = TollEngine.query(c, secOfDay: sec, sundayOrPH: sunPH)
                    VStack(spacing: 6) {
                        Text(c.name)
                            .font(.caption).foregroundStyle(.secondary)
                        Text("$\(r.dollars)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Brand.teal, in: RoundedRectangle(cornerRadius: 12))
                        if r.nextChangeSec < 86400 {
                            let mins = (r.nextChangeSec - sec + 59) / 60
                            Text("\(mins)分後 $\(r.nextDollars)")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        } else {
                            Text("今日冇再轉").font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    static func secondsOfDay(_ date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = WidgetFormat.hkTimeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0)
    }
}

// MARK: - 過海隧道行車時間

private struct HarbourCard: View {
    @ObservedObject var live: LiveDataStore

    private let tunnels: [(name: String, toKln: UInt8, toHK: UInt8)] = [
        ("紅隧", 1, 4), ("東隧", 2, 5), ("西隧", 3, 6),
    ]

    var body: some View {
        Card(title: "過海隧道", icon: "car.fill",
             trailing: WidgetFormat.ageText(live.journeyFetchedAt)) {
            VStack(spacing: 0) {
                HStack {
                    Spacer().frame(width: 52)
                    Text("港 → 九").font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Text("九 → 港").font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 6)

                ForEach(Array(tunnels.enumerated()), id: \.element.name) { i, t in
                    if i > 0 { Divider().padding(.vertical, 2) }
                    HStack {
                        Text(t.name).font(.body.weight(.medium))
                            .frame(width: 52, alignment: .leading)
                        MinutesCell(entry: live.journey[t.toKln])
                        MinutesCell(entry: live.journey[t.toHK])
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }
}

private struct MinutesCell: View {
    let entry: DashProtocol.JourneyEntry?

    var body: some View {
        let m = entry?.minutes ?? DashProtocol.minutesNA
        let colour = entry?.colour ?? 0
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(WidgetFormat.minutesText(m))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(WidgetFormat.isLiveMinutes(m)
                                 ? Brand.journeyColour(colour) : Color.secondary)
            if WidgetFormat.isLiveMinutes(m) {
                Text("分").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 主要幹道

private struct RoutesCard: View {
    @ObservedObject var live: LiveDataStore

    var body: some View {
        Card(title: "主要幹道", icon: "arrow.triangle.branch") {
            VStack(spacing: 0) {
                ForEach(Array(SlotConfig.configurableSlots.enumerated()), id: \.element) { i, slot in
                    if i > 0 { Divider().padding(.vertical, 2) }
                    let opt = SlotConfig.selected(slot: slot)
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(opt.name).font(.body.weight(.medium))
                            Text("\(opt.location) → \(opt.destination)")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        MinutesCell(entry: live.journey[slot])
                            .frame(width: 90)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - 油價

private struct FuelCard: View {
    @ObservedObject var live: LiveDataStore

    private let typeNames = ["無鉛汽油", "特級無鉛", "柴油"]
    private let brandNames = ["中石化", "中國石油", "加德士", "埃索", "蜆殼"]

    var body: some View {
        Card(title: "最平油價", icon: "fuelpump.fill",
             trailing: live.hasFuel ? "消委會" : nil) {
            if !live.hasFuel {
                Text("暫時攞唔到油價").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    ForEach(live.cheapestFuel(), id: \.type) { c in
                        VStack(spacing: 3) {
                            Text(typeNames[c.type]).font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.75)
                            Text(String(format: "$%d.%02d", c.cents / 100, c.cents % 100))
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .monospacedDigit().foregroundStyle(Brand.teal)
                            Text(brandNames[c.brand]).font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - 共用卡片

struct Card<Content: View>: View {
    let title: String
    let icon: String
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.teal)
                Spacer()
                if let t = trailing {
                    Text(t).font(.caption2).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16))
    }
}

struct AttributionFooter: View {
    var body: some View {
        Text("行車時間、咪錶：運輸署（DATA.GOV.HK）· 油價：消費者委員會 · 假期：1823\n本 App 與政府機構無關，資料僅供參考。")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }
}
