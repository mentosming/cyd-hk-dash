// Glue: BLE events -> data pipeline -> BLE writes. The ESP32 is the
// metronome — its 0x02 notifications wake this app in the background, so
// there are no background timers here.
import Foundation
import SwiftUI
import UIKit

@MainActor
final class DashCoordinator: NSObject, ObservableObject {
    @Published var connectionState = "未連接"
    @Published var deviceInfo = ""
    @Published var lastJourneyPush: Date?
    @Published var lastMetersPush: Date?
    @Published var logLines: [String] = []
    @Published var hasPairedDevice = false

    let central = DashCentral()
    let holidays = HolidayService()
    let journeyService = JourneyTimeService()
    let meterStore = MeterStore()
    lazy var meterQuery = MeterQueryService(store: meterStore)

    private var lastJourneyFetch: Date = .distantPast
    private var linkReady = false        // characteristics discovered
    private var metersRequestPending = false

    override init() {
        super.init()
        central.delegate = self
        hasPairedDevice = central.hasPairedDevice
        meterStore.logger = { [weak self] msg in
            Task { @MainActor in self?.log(msg) }
        }
        Task {
            await holidays.refreshIfStale()
            await meterStore.loadOrRefresh()
            log("咪錶資料庫: \(meterStore.count) 個車位")
        }
    }

    func pair() {
        central.startPairing()
        hasPairedDevice = central.hasPairedDevice
    }

    func unpair() {
        central.forgetDevice()
        hasPairedDevice = false
        connectionState = "未連接"
    }

    func log(_ s: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        logLines.append("\(df.string(from: Date())) \(s)")
        if logLines.count > 200 { logLines.removeFirst(logLines.count - 200) }
        print("[CYDDASH] \(s)")  // visible via `devicectl ... launch --console`
    }

    // MARK: pipeline

    private func pushTimeSyncAndJourney(force: Bool = false) {
        guard force || -lastJourneyFetch.timeIntervalSinceNow > 110 else { return }
        lastJourneyFetch = Date()

        // Write TimeSync FIRST, with no await before it. The holiday feed
        // (isSundayOrPH uses the cached set only) must never block this — a
        // hung network fetch here used to stall the whole push.
        let now = Date()
        let tomorrow = now.addingTimeInterval(86400)
        central.write(
            DashProtocol.encodeTimeSync(
                now: now,
                todaySunPH: holidays.isSundayOrPH(now),
                tomorrowSunPH: holidays.isSundayOrPH(tomorrow)),
            to: DashProtocol.UUIDs.timeSync)
        log("已推送時間同步")

        Task {
            do {
                let (capture, entries) = try await journeyService.fetch()
                central.write(DashProtocol.encodeJourney(captureEpoch: capture, entries: entries),
                              to: DashProtocol.UUIDs.journey)
                lastJourneyPush = Date()
                let live = entries.filter { $0.minutes < 0xFD }.count
                log("已推送行車時間（\(live)/\(entries.count) 個路段有數據）")
            } catch {
                log("行車時間讀取失敗: \(error.localizedDescription)")
            }
        }
        // Holiday refresh is best-effort and off the hot path.
        Task { await holidays.refreshIfStale() }
    }

    private func runMetersFlow() {
        // Buy background time: the whole flow (GPS + ~700 KB fetch) can
        // exceed the ~10 s BLE wake window.
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "meters")
        Task {
            log("掃描開始: 資料庫\(meterStore.count)個位, 定位權限[\(meterQuery.authDescription)]")
            let (status, groups) = await meterQuery.run()
            central.write(
                DashProtocol.encodeMeters(
                    fetchEpoch: UInt32(Date().timeIntervalSince1970),
                    status: status, groups: groups),
                to: DashProtocol.UUIDs.meters)
            lastMetersPush = Date()
            switch status {
            case 0, 4:
                log((status == 4 ? "咪錶(全滿): " : "咪錶: ")
                    + groups.map { "\($0.name) \($0.vacant)/\($0.total)" }.joined(separator: ", "))
            case 1: log("咪錶: 定位失敗")
            case 2: log("咪錶: 佔用數據讀取失敗")
            default: log("咪錶: 4公里內冇咪錶")
            }
            UIApplication.shared.endBackgroundTask(bgTask)
        }
    }
}

extension DashCoordinator: DashCentralDelegate {
    nonisolated func dashCentralReady(_ central: DashCentral, status: DashProtocol.DeviceStatus?) {
        Task { @MainActor in
            connectionState = "已連接"
            hasPairedDevice = true
            linkReady = true
            if let s = status {
                deviceInfo = "fw \(s.fwMajor).\(s.fwMinor) · 開機 \(s.uptimeS / 60) 分鐘"
            }
            pushTimeSyncAndJourney(force: true)
            if metersRequestPending {
                metersRequestPending = false
                log("執行排隊中嘅掃一掃請求")
                runMetersFlow()
            }
        }
    }

    nonisolated func dashCentral(_ central: DashCentral,
                                 didReceiveOpcode opcode: DashProtocol.Opcode) {
        Task { @MainActor in
            switch opcode {
            case .metersRefresh:
                log("裝置要求咪錶更新（掃一掃）")
                if linkReady {
                    runMetersFlow()
                } else {
                    metersRequestPending = true
                    log("連接未就緒，掃一掃請求已排隊")
                }
            case .journeyTick:
                pushTimeSyncAndJourney()
            case .fullResync:
                pushTimeSyncAndJourney(force: true)
            }
        }
    }

    nonisolated func dashCentralDisconnected(_ central: DashCentral) {
        Task { @MainActor in
            connectionState = "已斷線（等待重連）"
            linkReady = false
        }
    }

    nonisolated func dashCentral(_ central: DashCentral, log message: String) {
        Task { @MainActor in log(message) }
    }
}
