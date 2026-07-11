import SwiftUI

@main
struct HKCarDashApp: App {
    @StateObject private var coordinator = DashCoordinator()
    @StateObject private var router = Router()
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .fullScreenCover(isPresented: .constant(!didOnboard)) {
                    OnboardingView { didOnboard = true }
                }
                .onOpenURL { url in
                    switch url.scheme?.lowercased() {
                    case "cyddash":                       // QR pairing deep link
                        coordinator.handlePairingURL(url)
                        router.tab = .device
                    case "hkcardash":                     // widget tap
                        router.open(url)
                    default: break
                    }
                }
        }
    }
}

/// Which tab is showing, and deep-link routing into it.
final class Router: ObservableObject {
    enum Tab: String { case dashboard, map, device, settings }
    @Published var tab: Tab = .dashboard

    /// hkcardash://tab/<name>
    func open(_ url: URL) {
        guard url.host == "tab", let name = url.pathComponents.last,
              let t = Tab(rawValue: name) else { return }
        tab = t
    }
}

struct RootView: View {
    @EnvironmentObject var router: Router

    var body: some View {
        TabView(selection: $router.tab) {
            DashboardView()
                .tabItem { Label("今日", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(Router.Tab.dashboard)

            MeterMapScreen()
                .tabItem { Label("咪錶", systemImage: "map.fill") }
                .tag(Router.Tab.map)

            DeviceView()
                .tabItem { Label("顯示屏", systemImage: "display") }
                .tag(Router.Tab.device)

            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(Router.Tab.settings)
        }
        .tint(Brand.teal)
    }
}
