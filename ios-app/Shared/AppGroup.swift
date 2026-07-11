// Storage shared between the app and the widget extension. Anything a widget
// needs to read (holiday dates, fuel prices, route config, cached journey
// times) must live here, not in UserDefaults.standard.
import Foundation

enum AppGroup {
    static let id = "group.com.kmai.hkcardash"

    /// Falls back to .standard in unit tests / previews where the group is absent.
    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard
}
