import SwiftUI
import WidgetKit

@main
struct HKCarDashWidgets: WidgetBundle {
    var body: some Widget {
        TollWidget()
        JourneyWidget()
        FuelWidget()
    }
}
