import SwiftUI

struct OnboardingView: View {
    let done: () -> Void
    @State private var page = 0

    private let pages: [(icon: String, title: String, body: String)] = [
        ("dollarsign.circle.fill", "隧道收費、實時計算",
         "三條過海隧道嘅時段收費，同下次幾時轉價，一眼睇晒。純本地計算，開飛航模式都準。"),
        ("map.fill", "咪錶地圖",
         "全港私家車咪錶，綠色即係有空位。只計你泊得嘅位 —— 唔包貨車、旅遊巴，仲會按官方准泊時段過濾。"),
        ("display", "（可選）車載顯示屏",
         "一塊約 HK$80 嘅開源 ESP32 屏，插車 USB，資料自動經藍牙上屏。冇都照用得全部功能。"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, p in
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: p.icon)
                            .font(.system(size: 68))
                            .foregroundStyle(Brand.teal)
                        Text(p.title)
                            .font(.title2.weight(.bold))
                        Text(p.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 34)
                        Spacer()
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page == pages.count - 1 ? "開始用" : "繼續") {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    done()
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Brand.teal, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Button("略過", action: done)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }
}
