// Consumer Council "Oil Price Watch" open data — list pump prices of the
// five HK fuel brands. ~1.3 KB JSON, cached for offline pushes.
import Foundation

final class FuelPriceService {
    static let url = URL(
        string: "https://www.consumer.org.hk/pricewatch/oilwatch/opendata/oilprice.json")!
    private static let cacheKey = "fuelPricesCents"   // [[Int]] with -1 = N/A
    private static let fetchedAtKey = "fuelFetchedAt"

    // Wire order per docs/ble-protocol.md
    static let brands = ["Sinopec", "PetroChina", "Caltex", "Esso", "Shell"]
    static let types = ["Standard Petrol", "Premium Petrol", "Diesel"]

    /// cents[brand][type]; nil = unavailable.
    private(set) var cents: [[UInt16?]] =
        Array(repeating: Array(repeating: nil, count: 3), count: 5)
    private(set) var fetchedAt: Date?

    init() {
        if let cached = AppGroup.defaults.array(forKey: Self.cacheKey) as? [[Int]],
           cached.count == 5 {
            cents = cached.map { $0.map { $0 >= 0 ? UInt16($0) : nil } }
        }
        let t = AppGroup.defaults.double(forKey: Self.fetchedAtKey)
        if t > 0 { fetchedAt = Date(timeIntervalSince1970: t) }
    }

    var hasData: Bool { cents.flatMap { $0 }.contains { $0 != nil } }
    var ageHours: Double { fetchedAt.map { -$0.timeIntervalSinceNow / 3600 } ?? .infinity }

    /// Fetch if stale (>6 h). Returns true if data (fresh or cached) is available.
    @discardableResult
    func refreshIfStale() async -> Bool {
        guard ageHours > 6 || !hasData else { return true }
        do {
            var req = URLRequest(url: Self.url)
            req.timeoutInterval = 15
            let (data, _) = try await URLSession.shared.data(for: req)
            if let parsed = Self.parse(data) {
                cents = parsed
                fetchedAt = Date()
                AppGroup.defaults.set(
                    cents.map { $0.map { $0.map(Int.init) ?? -1 } }, forKey: Self.cacheKey)
                AppGroup.defaults.set(fetchedAt!.timeIntervalSince1970,
                                          forKey: Self.fetchedAtKey)
            }
        } catch {
            // keep cache
        }
        return hasData
    }

    /// JSON: [{type: {en,tc,sc}, prices: [{vendor: {en,...}, price: "31.84"}]}]
    static func parse(_ data: Data) -> [[UInt16?]]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        var out: [[UInt16?]] = Array(repeating: Array(repeating: nil, count: 3), count: 5)
        var any = false
        for entry in root {
            guard let typeEn = (entry["type"] as? [String: Any])?["en"] as? String,
                  let t = types.firstIndex(of: typeEn),
                  let prices = entry["prices"] as? [[String: Any]] else { continue }
            for p in prices {
                guard let vendorEn = (p["vendor"] as? [String: Any])?["en"] as? String,
                      let b = brands.firstIndex(of: vendorEn),
                      let priceStr = p["price"] as? String,
                      let price = Double(priceStr), price > 0, price < 600 else { continue }
                out[b][t] = UInt16((price * 100).rounded())
                any = true
            }
        }
        return any ? out : nil
    }
}
