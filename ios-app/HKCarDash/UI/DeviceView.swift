// 顯示屏 — pairing and status for the optional CYD-DASH car display.
// The app is fully useful without one; this tab sells it and manages it.
import SwiftUI

struct DeviceView: View {
    @EnvironmentObject var coordinator: DashCoordinator
    @State private var showScanner = false
    @State private var showLog = false

    var body: some View {
        NavigationStack {
            List {
                if coordinator.hasPairedDevice || coordinator.hasToken {
                    statusSection
                    routesSection
                    manageSection
                } else {
                    promoSection
                }
                logSection
            }
            .navigationTitle("顯示屏")
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRScannerView { scanned in
                        showScanner = false
                        if let url = URL(string: scanned) { coordinator.handlePairingURL(url) }
                    }
                    .ignoresSafeArea()
                    .navigationTitle("掃描配對 QR")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showScanner = false }
                        }
                    }
                }
            }
        }
    }

    // MARK: sections

    private var statusSection: some View {
        Section("狀態") {
            HStack {
                Circle()
                    .fill(coordinator.connectionState == "已連接" ? Brand.green : Color.gray)
                    .frame(width: 9, height: 9)
                Text(coordinator.connectionState)
                Spacer()
                Text(coordinator.deviceInfo).font(.caption).foregroundStyle(.secondary)
            }
            if let d = coordinator.lastJourneyPush {
                LabeledContent("上次推送", value: WidgetFormat.ageText(d))
            }
            if coordinator.needsPairing {
                Label("顯示屏要求配對 — 掃描屏幕上嘅 QR", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Brand.amber)
            }
        }
    }

    private var routesSection: some View {
        Section {
            ForEach(SlotConfig.configurableSlots, id: \.self) { slot in
                Picker("路線 \(slot - 6)", selection: slotBinding(slot)) {
                    ForEach(SlotConfig.options) { opt in
                        Text("\(opt.name)（\(opt.location)→\(opt.destination)）").tag(opt.id)
                    }
                }
            }
        } header: {
            Text("幹道頁路線")
        } footer: {
            Text("揀邊三條路線喺顯示屏「主要幹道」頁同「今日」出現。改完即刻推送去顯示屏。")
        }
    }

    private var manageSection: some View {
        Section {
            Button {
                showScanner = true
            } label: {
                Label("重新掃描配對 QR", systemImage: "qrcode.viewfinder")
            }
            Button(role: .destructive) {
                coordinator.unpair()
            } label: {
                Label("取消配對", systemImage: "xmark.circle")
            }
        } footer: {
            Text("顯示屏隱藏操作：長按標題 = 觸控校準 · 長按時鐘 = 清除配對 · 撳右上藍牙點 = 叫出配對 QR")
        }
    }

    private var promoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "display")
                    .font(.system(size: 34)).foregroundStyle(Brand.teal)
                Text("加一部車載顯示屏")
                    .font(.headline)
                Text("一塊約 HK$80 嘅 ESP32 屏，插車 USB，隧道時間、收費、咪錶同油價一眼睇晒 —— 唔使掂手機。開源，用瀏覽器一鍵燒錄。")
                    .font(.callout).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://mentosming.github.io/cyd-hk-dash/")!) {
                    Label("點整？（開源教學）", systemImage: "arrow.up.right.square")
                }
                .font(.callout.weight(.medium))
            }
            .padding(.vertical, 6)

            Button {
                showScanner = true
            } label: {
                Label("已經有？掃描配對 QR", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.teal)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
    }

    private var logSection: some View {
        Section {
            DisclosureGroup("連接記錄", isExpanded: $showLog) {
                ForEach(coordinator.logLines.suffix(40).reversed(), id: \.self) { l in
                    Text(l).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func slotBinding(_ slot: UInt8) -> Binding<String> {
        Binding(
            get: { SlotConfig.selected(slot: slot).id },
            set: { newID in
                guard let opt = SlotConfig.options.first(where: { $0.id == newID }) else { return }
                SlotConfig.setSelected(slot: slot, option: opt)
                coordinator.routeConfigChanged()
            })
    }
}
