// The app's single source of live public data (journey times + fuel prices).
// Deliberately independent of the BLE link: the Dashboard tab is fully useful
// with no display connected. The coordinator pushes THIS store's data over BLE,
// so there is exactly one fetch path — and every refresh also updates the
// App Group cache the widgets read.
import Foundation
import WidgetKit

@MainActor
final class LiveDataStore: ObservableObject {
    @Published private(set) var journey: [UInt8: DashProtocol.JourneyEntry] = [:]   // slot -> entry
    @Published private(set) var journeyFetchedAt: Date?
    @Published private(set) var journeyError: String?

    @Published private(set) var fuelCents: [[UInt16?]] = []
    @Published private(set) var fuelFetchedAt: Date?

    @Published private(set) var isRefreshing = false

    let holidays = HolidayService()
    private let journeyService = JourneyTimeService()
    private let fuelService = FuelPriceService()
    private var lastJourneyFetch: Date = .distantPast

    var captureEpoch: UInt32 = 0

    init() {
        fuelCents = fuelService.cents
        fuelFetchedAt = fuelService.fetchedAt
    }

    /// Ordered entries for a BLE Journey payload (slots in registry order).
    var journeyPayloadEntries: [DashProtocol.JourneyEntry] {
        SlotConfig.journeySlots().compactMap { journey[$0.slot] }
    }

    /// The user re-pointed a configurable slot at a different road: the cached
    /// minutes for those slots now belong to the OLD route and must not be shown
    /// (or pushed to the display) under the new name.
    func invalidateConfigurableSlots() {
        for s in SlotConfig.configurableSlots { journey[s] = nil }
        lastJourneyFetch = .distantPast
    }

    /// Fetch journey times. `force` bypasses the 110 s throttle (the TD feed
    /// only updates every 2 min, so hammering it is pointless).
    @discardableResult
    func refreshJourney(force: Bool = false) async -> Bool {
        guard force || -lastJourneyFetch.timeIntervalSinceNow > 110 else { return false }
        lastJourneyFetch = Date()
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (capture, entries) = try await journeyService.fetch()
            captureEpoch = capture
            journey = Dictionary(uniqueKeysWithValues: entries.map { ($0.slot, $0) })
            journeyFetchedAt = Date()
            journeyError = nil
            writeWidgetJourneyCache(entries)
            WidgetCenter.shared.reloadTimelines(ofKind: "JourneyWidget")
            return true
        } catch {
            journeyError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func refreshFuel() async -> Bool {
        let ok = await fuelService.refreshIfStale()
        fuelCents = fuelService.cents
        fuelFetchedAt = fuelService.fetchedAt
        if ok { WidgetCenter.shared.reloadTimelines(ofKind: "FuelWidget") }
        return ok
    }

    func refreshAll(force: Bool = false) async {
        async let j: Bool = refreshJourney(force: force)
        async let f: Bool = refreshFuel()
        _ = await (j, f)
        await holidays.refreshIfStale()
    }

    /// Payload bytes for the BLE FuelPrices characteristic.
    var fuelPayload: Data {
        DashProtocol.encodeFuelPrices(
            fetchEpoch: UInt32((fuelFetchedAt ?? Date()).timeIntervalSince1970),
            cents: fuelCents)
    }

    var hasFuel: Bool { fuelCents.flatMap { $0 }.contains { $0 != nil } }

    /// Cheapest (cents, brandIndex) per fuel type; nil when a type has no price.
    func cheapestFuel() -> [(type: Int, cents: UInt16, brand: Int)] {
        (0..<3).compactMap { t in
            var best: (UInt16, Int)?
            for b in 0..<fuelCents.count {
                guard t < fuelCents[b].count, let c = fuelCents[b][t] else { continue }
                if best == nil || c < best!.0 { best = (c, b) }
            }
            return best.map { (t, $0.0, $0.1) }
        }
    }

    // Keep the widget's cache in sync so a widget refresh has data even when it
    // cannot reach the network within its budget.
    private func writeWidgetJourneyCache(_ entries: [DashProtocol.JourneyEntry]) {
        AppGroup.defaults.set(
            Dictionary(uniqueKeysWithValues: entries.map { ("\($0.slot)", Int($0.minutes)) }),
            forKey: "widgetJourneyCache")
        AppGroup.defaults.set(
            Dictionary(uniqueKeysWithValues: entries.map { ("\($0.slot)", Int($0.colour)) }),
            forKey: "widgetJourneyColour")
        AppGroup.defaults.set(Date().timeIntervalSince1970, forKey: "widgetJourneyAt")
    }
}
