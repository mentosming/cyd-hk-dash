import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var coordinator: DashCoordinator
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage(DemoMode.key) private var demoEnabled = false
    @State private var versionTaps = 0
    @State private var showDemoToggle = DemoMode.isEnabled

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("咪錶") {
                    LabeledContent("車位資料庫",
                                   value: "\(coordinator.meterStore.count) 個私家車位")
                    Text("只計私家車可泊嘅咪錶（唔包旅遊巴同貨車位），並按運輸署官方准泊時段過濾。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("資料來源") {
                    Link(destination: URL(string: "https://data.gov.hk")!) {
                        LabeledContent("行車時間、咪錶", value: "運輸署")
                    }
                    Link(destination: URL(string: "https://oil-price.consumer.org.hk")!) {
                        LabeledContent("油價", value: "消費者委員會")
                    }
                    Link(destination: URL(string: "https://www.1823.gov.hk")!) {
                        LabeledContent("公眾假期", value: "1823")
                    }
                    Link(destination: URL(string: "https://portal.csdi.gov.hk")!) {
                        LabeledContent("地圖", value: "地政總署")
                    }
                }

                Section("關於") {
                    Link(destination: URL(string: "https://mentosming.github.io/cyd-hk-dash/privacy.html")!) {
                        Label("私隱政策", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://github.com/mentosming/cyd-hk-dash")!) {
                        Label("開源專案（GitHub）", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Button {
                        didOnboard = false
                    } label: {
                        Label("重看介紹", systemImage: "sparkles")
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(version).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTaps += 1
                        if versionTaps >= 5 { showDemoToggle = true }
                    }
                }

                if showDemoToggle {
                    Section {
                        Toggle("示範模式", isOn: Binding(
                            get: { demoEnabled },
                            set: { coordinator.setDemoMode($0) }))
                    } footer: {
                        Text("模擬一部已連接嘅顯示屏同咪錶佔用資料，唔使真硬件都睇到全部功能，即時生效。App Review 用。")
                    }
                }

                Section {
                    Text("本 App 與運輸署、消費者委員會或任何政府機構無關。所有資料僅供參考，駕駛時請以路面實際情況同官方指示為準。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
    }
}
