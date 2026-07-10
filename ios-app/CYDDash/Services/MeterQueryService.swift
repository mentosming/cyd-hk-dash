// 掃一掃 flow: one-shot GPS fix -> spaces within radius (MeterStore) ->
// live occupancy join -> top-3 street groups by distance.
import CoreLocation
import Foundation

final class MeterQueryService: NSObject {
    static let occupancyURL = URL(
        string: "https://resource.data.one.gov.hk/td/psiparkingspaces/occupancystatus/occupancystatus.csv")!

    private let store: MeterStore
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    init(store: MeterStore) {
        self.store = store
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }

    var authDescription: String {
        switch locationManager.authorizationStatus {
        case .notDetermined: return "未詢問"
        case .restricted: return "受限"
        case .denied: return "已拒絕"
        case .authorizedAlways: return "永遠"
        case .authorizedWhenInUse: return "使用期間"
        @unknown default: return "?"
        }
    }

    static let maxSearchM = 4000.0

    /// Full flow per docs/ble-protocol.md: search up to 4 km for the nearest
    /// streets that HAVE vacant meters (status 0). If everything in range is
    /// full, return the nearest streets anyway with status 4.
    func run() async -> (status: UInt8, groups: [DashProtocol.MeterGroup]) {
        await store.loadOrRefresh()
        guard let coord = await currentLocation() else { return (1, []) }

        let nearby = store.spaces(within: Self.maxSearchM, of: coord)
        if nearby.isEmpty { return (3, []) }

        guard let occupancy = await fetchOccupancy() else { return (2, []) }

        struct Group {
            var minDist = Double.greatestFiniteMagnitude
            var vacant = 0
            var total = 0
        }
        var groups: [String: Group] = [:]
        for (space, dist) in nearby {
            guard let occ = occupancy[space.id], occ.working else { continue }
            var g = groups[space.street] ?? Group()
            g.minDist = min(g.minDist, dist)
            g.total += 1
            if occ.vacant { g.vacant += 1 }
            groups[space.street] = g
        }
        if groups.isEmpty { return (3, []) }

        // Prefer streets with vacancies; fall back to nearest-full (status 4).
        let vacantStreets = groups.filter { $0.value.vacant > 0 }
        let chosen = (vacantStreets.isEmpty ? groups : vacantStreets)
            .sorted { $0.value.minDist < $1.value.minDist }
            .prefix(4)
        let status: UInt8 = vacantStreets.isEmpty ? 4 : 0
        return (status, chosen.map { name, g in
            DashProtocol.MeterGroup(
                name: name,
                distM: UInt16(clamping: Int(g.minDist)),
                vacant: UInt8(clamping: g.vacant),
                total: UInt8(clamping: g.total))
        })
    }

    // MARK: occupancy

    /// ParkingSpaceId -> (working: meter status N, vacant: occupancy V)
    func fetchOccupancy() async -> [String: (working: Bool, vacant: Bool)]? {
        var req = URLRequest(url: Self.occupancyURL)
        req.timeoutInterval = 20
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let text = String(data: data, encoding: .utf8) else { return nil }
        var out: [String: (working: Bool, vacant: Bool)] = [:]
        out.reserveCapacity(21000)
        // CRLF file — "\r\n" is one Character in Swift, split on isNewline
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {  // header on line 1
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 3 else { continue }
            let id = String(cols[0]).trimmingCharacters(in: .whitespaces)
            let working = cols[1].trimmingCharacters(in: .whitespaces) == "N"
            let vacant = cols[2].trimmingCharacters(in: .whitespaces) == "V"
            out[id] = (working, working && vacant)
        }
        return out.isEmpty ? nil : out
    }

    // MARK: location

    private func currentLocation() async -> CLLocationCoordinate2D? {
        let auth = locationManager.authorizationStatus
        guard auth == .authorizedAlways || auth == .authorizedWhenInUse else {
            // fall back to a recent cached fix if we have one
            return locationManager.location?.coordinate
        }
        if let loc = locationManager.location, -loc.timestamp.timeIntervalSinceNow < 60 {
            return loc.coordinate
        }
        return await withCheckedContinuation { cont in
            locationContinuation = cont
            locationManager.requestLocation()
        }
    }
}

extension MeterQueryService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        locationContinuation?.resume(returning: locations.first?.coordinate)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(returning: manager.location?.coordinate)
        locationContinuation = nil
    }
}
