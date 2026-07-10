// Local index of the ~20,700 metered parking spaces (parkingspaces.csv,
// ~4.8 MB). Downloaded to Application Support, refreshed daily via ETag.
// CSV quirks (verified): line 1 = BOM + date, line 2 = empty commas,
// header on line 3.
import CoreLocation
import Foundation

final class MeterStore {
    static let url = URL(
        string: "https://resource.data.one.gov.hk/td/psiparkingspaces/spaceinfo/parkingspaces.csv")!
    private static let etagKey = "parkingSpacesETag"
    private static let fetchedAtKey = "parkingSpacesFetchedAt"

    struct Space {
        let id: String
        let street: String    // Chinese (Street_tc) — shown on the device
        let lat: Double
        let lon: Double
    }

    private(set) var spaces: [Space] = []
    // 0.005° grid (~500 m) -> space indices, for radius lookups
    private var grid: [Int: [Int]] = [:]
    var logger: ((String) -> Void)?

    var count: Int { spaces.count }

    private static var cacheFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("parkingspaces.csv")
    }

    func loadOrRefresh() async {
        if spaces.isEmpty, let data = try? Data(contentsOf: Self.cacheFile) {
            ingest(data)
        }
        let fetchedAt = UserDefaults.standard.double(forKey: Self.fetchedAtKey)
        let dayAgo = Date().timeIntervalSince1970 - 86400
        guard spaces.isEmpty || fetchedAt < dayAgo else { return }

        var req = URLRequest(url: Self.url)
        req.timeoutInterval = 60
        if let etag = UserDefaults.standard.string(forKey: Self.etagKey), !spaces.isEmpty {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            logger?("咪錶庫: 下載中…")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            logger?("咪錶庫: HTTP \(http.statusCode), \(data.count / 1024) KB")
            if http.statusCode == 200 {
                try? data.write(to: Self.cacheFile)
                UserDefaults.standard.set(http.value(forHTTPHeaderField: "Etag"),
                                          forKey: Self.etagKey)
                ingest(data)
                logger?("咪錶庫: 解析到 \(spaces.count) 個車位")
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.fetchedAtKey)
        } catch {
            logger?("咪錶庫: 下載失敗 \(error.localizedDescription)")
        }
    }

    func spaces(within radiusM: Double, of coord: CLLocationCoordinate2D) -> [(Space, Double)] {
        let cellsSpan = Int(radiusM / 500) + 1
        let baseLat = Int(coord.latitude / 0.005)
        let baseLon = Int(coord.longitude / 0.005)
        let here = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

        var out: [(Space, Double)] = []
        for dLat in -cellsSpan...cellsSpan {
            for dLon in -cellsSpan...cellsSpan {
                let key = Self.gridKey(latCell: baseLat + dLat, lonCell: baseLon + dLon)
                for idx in grid[key] ?? [] {
                    let s = spaces[idx]
                    let d = here.distance(from: CLLocation(latitude: s.lat, longitude: s.lon))
                    if d <= radiusM { out.append((s, d)) }
                }
            }
        }
        return out
    }

    // MARK: parsing

    func ingest(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        // NOTE: the file is CRLF-terminated. In Swift, "\r\n" is ONE grapheme
        // cluster, so split(separator: "\n") would see a single giant line —
        // split on any newline Character instead.
        var lines = text.split(omittingEmptySubsequences: false,
                               whereSeparator: \.isNewline)
        // Drop the date line + junk line; header is line 3
        guard lines.count > 3 else { return }
        lines.removeFirst(2)
        let header = Self.splitCSV(String(lines.removeFirst()))
        guard let idCol = header.firstIndex(of: "ParkingSpaceId"),
              let streetCol = header.firstIndex(of: "Street_tc"),
              let latCol = header.firstIndex(of: "Latitude"),
              let lonCol = header.firstIndex(of: "Longitude") else { return }

        var parsed: [Space] = []
        parsed.reserveCapacity(21000)
        for line in lines where !line.isEmpty {
            let cols = Self.splitCSV(String(line))
            guard cols.count > max(idCol, streetCol, latCol, lonCol),
                  let lat = Double(cols[latCol]), let lon = Double(cols[lonCol]),
                  lat > 21, lat < 23, lon > 113, lon < 115 else { continue }
            parsed.append(Space(id: cols[idCol], street: cols[streetCol], lat: lat, lon: lon))
        }
        guard !parsed.isEmpty else { return }
        spaces = parsed
        grid = [:]
        for (i, s) in spaces.enumerated() {
            let key = Self.gridKey(latCell: Int(s.lat / 0.005), lonCell: Int(s.lon / 0.005))
            grid[key, default: []].append(i)
        }
    }

    private static func gridKey(latCell: Int, lonCell: Int) -> Int {
        latCell &* 100_000 &+ lonCell
    }

    /// Minimal CSV field splitter with quote support.
    static func splitCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var cur = ""
        var inQuotes = false
        for ch in line {
            switch ch {
            case "\"": inQuotes.toggle()
            case "," where !inQuotes:
                fields.append(cur)
                cur = ""
            case "\r": break
            default: cur.append(ch)
            }
        }
        fields.append(cur)
        return fields
    }
}
