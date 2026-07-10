import SwiftUI

@main
struct CYDDashApp: App {
    @StateObject private var coordinator = DashCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
        }
    }
}
