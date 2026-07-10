// App-layer pairing token obtained by scanning the device's QR deep link
// (cyddash://pair?t=<hex>&n=CYD-DASH). Persisted and written to the Auth
// characteristic on every connect to authorise data writes.
import Foundation

enum PairingToken {
    private static let key = "pairingTokenHex"

    static var hex: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var data: Data? { hex.flatMap(hexToData) }
    static var isSet: Bool { data?.count == 8 }

    /// Parse cyddash://pair?t=<hex>&n=<name>. Returns the token hex if valid.
    static func parse(url: URL) -> String? {
        guard url.scheme?.lowercased() == "cyddash",
              url.host?.lowercased() == "pair",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let t = comps.queryItems?.first(where: { $0.name == "t" })?.value,
              hexToData(t)?.count == 8 else { return nil }
        return t.lowercased()
    }

    static func hexToData(_ s: String) -> Data? {
        let chars = Array(s)
        guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            out.append(b)
            i += 2
        }
        return out
    }
}
