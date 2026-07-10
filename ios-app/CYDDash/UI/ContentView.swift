import SwiftUI

private let etollTeal = Color(red: 0x18 / 255, green: 0xAD / 255, blue: 0x8E / 255)

struct ContentView: View {
    @EnvironmentObject var coordinator: DashCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section("裝置") {
                    HStack {
                        Circle()
                            .fill(coordinator.connectionState == "已連接" ? etollTeal : .gray)
                            .frame(width: 10, height: 10)
                        Text(coordinator.connectionState)
                        Spacer()
                        Text(coordinator.deviceInfo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if coordinator.hasPairedDevice {
                        Button("取消配對", role: .destructive) { coordinator.unpair() }
                    } else {
                        Button("配對 CYD-DASH") { coordinator.pair() }
                            .tint(etollTeal)
                    }
                }

                Section("收費預覽（依官方時變收費表）") {
                    TollPreview()
                }

                Section("咪錶") {
                    LabeledContent("資料庫", value: "\(coordinator.meterStore.count) 個車位")
                    Text("掃一掃會喺 4 公里內搵最近有空位嘅街道")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("記錄") {
                    ForEach(coordinator.logLines.suffix(30).reversed(), id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("CYD-DASH")
            .onAppear {
                coordinator.meterQuery.requestPermissions()
            }
        }
    }
}

struct TollPreview: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second], from: now)
        let sec = (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
        let holidays = HolidayService()
        let sunPH = holidays.isSundayOrPH(now)

        VStack(spacing: 8) {
            ForEach(TollEngine.Crossing.allCases, id: \.name) { crossing in
                let r = TollEngine.query(crossing, secOfDay: sec, sundayOrPH: sunPH)
                HStack {
                    Text(crossing.name)
                    Spacer()
                    if r.nextChangeSec < 86400 {
                        Text("\((r.nextChangeSec - sec + 59) / 60)分後 $\(r.nextDollars)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("$\(r.dollars)")
                        .bold()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(etollTeal, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .onReceive(timer) { now = $0 }
    }
}
