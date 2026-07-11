// Time-varying toll engine — mirror of firmware/src/model/toll_engine.cpp.
// Schedule source of truth: docs/toll-schedule.md. Parity is enforced by
// CYDDashTests.TollEngineTests against the shared test vectors.
import Foundation

enum TollEngine {
    enum Crossing: CaseIterable {
        case whc, cht, ehc
        var name: String {
            switch self {
            case .whc: return "西隧"
            case .cht: return "紅隧"
            case .ehc: return "東隧"
            }
        }
    }

    struct Result: Equatable {
        let dollars: Int
        let nextDollars: Int
        let nextChangeSec: Int  // 86400 = no further change today
    }

    // toll(t) = v0 + dir * 2 * floor((t - from) / 120); dir 0 = plateau
    private struct Seg {
        let from: Int
        let to: Int
        let v0: Int
        let dir: Int
    }

    private static func s(_ h: Int, _ m: Int) -> Int { h * 3600 + m * 60 }

    private static let profileW: [Seg] = [
        .init(from: 0, to: s(7, 30), v0: 20, dir: 0),
        .init(from: s(7, 30), to: s(8, 8), v0: 22, dir: 1),
        .init(from: s(8, 8), to: s(10, 15), v0: 60, dir: 0),
        .init(from: s(10, 15), to: s(10, 43), v0: 58, dir: -1),
        .init(from: s(10, 43), to: s(16, 30), v0: 30, dir: 0),
        .init(from: s(16, 30), to: s(16, 58), v0: 32, dir: 1),
        .init(from: s(16, 58), to: s(19, 0), v0: 60, dir: 0),
        .init(from: s(19, 0), to: s(19, 38), v0: 58, dir: -1),
        .init(from: s(19, 38), to: 86400, v0: 20, dir: 0),
    ]

    private static let profileC: [Seg] = [
        .init(from: 0, to: s(7, 30), v0: 20, dir: 0),
        .init(from: s(7, 30), to: s(7, 48), v0: 22, dir: 1),
        .init(from: s(7, 48), to: s(10, 15), v0: 40, dir: 0),
        .init(from: s(10, 15), to: s(10, 23), v0: 38, dir: -1),
        .init(from: s(10, 23), to: s(16, 30), v0: 30, dir: 0),
        .init(from: s(16, 30), to: s(16, 38), v0: 32, dir: 1),
        .init(from: s(16, 38), to: s(19, 0), v0: 40, dir: 0),
        .init(from: s(19, 0), to: s(19, 18), v0: 38, dir: -1),
        .init(from: s(19, 18), to: 86400, v0: 20, dir: 0),
    ]

    private static let profileS: [Seg] = [
        .init(from: 0, to: s(10, 11), v0: 20, dir: 0),
        .init(from: s(10, 11), to: s(10, 13), v0: 21, dir: 0),
        .init(from: s(10, 13), to: s(10, 15), v0: 23, dir: 0),
        .init(from: s(10, 15), to: s(19, 15), v0: 25, dir: 0),
        .init(from: s(19, 15), to: s(19, 17), v0: 23, dir: 0),
        .init(from: s(19, 17), to: s(19, 19), v0: 21, dir: 0),
        .init(from: s(19, 19), to: 86400, v0: 20, dir: 0),
    ]

    private static func profile(_ c: Crossing, sundayOrPH: Bool) -> [Seg] {
        if sundayOrPH { return profileS }
        return c == .whc ? profileW : profileC
    }

    private static func eval(_ seg: Seg, _ t: Int) -> Int {
        seg.dir == 0 ? seg.v0 : seg.v0 + seg.dir * 2 * ((t - seg.from) / 120)
    }

    private static func evalAt(_ segs: [Seg], _ t: Int) -> Int {
        segs.first { t >= $0.from && t < $0.to }.map { eval($0, t) } ?? 20
    }

    static func query(_ c: Crossing, secOfDay: Int, sundayOrPH: Bool) -> Result {
        let t = secOfDay % 86400
        let segs = profile(c, sundayOrPH: sundayOrPH)
        guard let seg = segs.first(where: { t >= $0.from && t < $0.to }) else {
            return Result(dollars: 20, nextDollars: 20, nextChangeSec: 86400)
        }
        let dollars = eval(seg, t)

        var next = seg.to
        if seg.dir != 0 {
            let step = seg.from + ((t - seg.from) / 120 + 1) * 120
            if step < seg.to { next = step }
        }
        if next >= 86400 {
            return Result(dollars: dollars, nextDollars: dollars, nextChangeSec: 86400)
        }
        var nextChange = next
        var nextDollars = evalAt(segs, next)
        // Skip value-neutral boundaries (plateau -> equal ramp start)
        while nextChange < 86400, nextDollars == dollars {
            let deeper = query(c, secOfDay: nextChange, sundayOrPH: sundayOrPH)
            nextChange = deeper.nextChangeSec
            nextDollars = deeper.nextDollars
        }
        return Result(dollars: dollars, nextDollars: nextDollars, nextChangeSec: nextChange)
    }
}
