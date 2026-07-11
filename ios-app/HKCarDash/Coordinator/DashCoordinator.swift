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
    @Published var needsPairing = false        // device asked us to present a token we lack
    @Published var hasToken = PairingToken.isSet

    let central = DashCentral()
    let live = LiveDataStore()            // journey + fuel, works with no display
    let meterStore = MeterStore()
    lazy var meterQuery = MeterQueryService(store: meterStore)

    var holidays: HolidayService { live.holidays }

    private var linkReady = false        // characteristics discovered
    private var lastJourneyPayload: Data?
    private var metersRunning = false
    private var metersRequestPending = false
    private var lastFuelPush: Date = .distantPast
    // Auto-refresh window: after a successful scan, keep meters fresh for 10 min
    private var metersAutoUntil: Date = .distantPast
    private var lastMetersRun: Date = .distantPast

    override init() {
        super.init()
        central.delegate = self
        hasPairedDevice = central.hasPairedDevice
        applyDemoState()
        meterStore.logger = { [weak self] msg in
            Task { @MainActor in self?.log(msg) }
        }
        Task {
            await live.refreshAll()
            await meterStore.loadOrRefresh()
            log("咪錶資料庫: \(meterStore.count) 個車位")
        }
    }

    func pair() {
        central.startPairing()
        hasPairedDevice = central.hasPairedDevice
    }

    /// Demo mode must take effect immediately — an App Review reviewer flips the
    /// toggle and looks at the 顯示屏 tab straight away; requiring a relaunch
    /// would read as "the feature is broken".
    func setDemoMode(_ on: Bool) {
        DemoMode.isEnabled = on
        applyDemoState()
    }

    private func applyDemoState() {
        if DemoMode.isEnabled {
            connectionState = DemoMode.connectionState
            deviceInfo = DemoMode.deviceInfo
            hasPairedDevice = true
            hasToken = true
            needsPairing = false
        } else {
            // Back to the real link state (also fixes the reverse path: turning
            // demo off used to leave the device looking paired forever).
            connectionState = central.isConnected ? "已連接" : "未連接"
            deviceInfo = ""
            hasPairedDevice = central.hasPairedDevice
            hasToken = PairingToken.isSet
        }
    }

    /// Handle a scanned QR deep link (cyddash://pair?t=…). Stores the token,
    /// then connects (or re-authorises an existing connection).
    func handlePairingURL(_ url: URL) {
        guard let token = PairingToken.parse(url: url) else {
            log("配對連結無效")
            return
        }
        PairingToken.hex = token
        hasToken = true
        needsPairing = false
        log("已由 QR 取得配對 token")
        // Ensure a connection (uses retrieve-not-scan so it works even when the
        // device is already bonded/connected); token is written on discovery,
        // and immediately if the link is already up.
        central.ensureConnected()
        central.writeAuthToken()
        hasPairedDevice = central.hasPairedDevice
    }

    func unpair() {
        central.forgetDevice()
        PairingToken.hex = nil
        hasToken = false
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
        // Write TimeSync FIRST, with no await before it. The holiday feed
        // (sunPHFlags uses the cached set only) must never block this — a
        // hung network fetch here used to stall the whole push.
        central.write(
            DashProtocol.encodeTimeSync(sunPHFlags: holidays.sunPHFlags),
            to: DashProtocol.UUIDs.timeSync)
        log("已推送時間同步")
        if force { pushSlotNames() }

        Task {
            // LiveDataStore owns the throttle (the TD feed only moves every 2 min)
            await live.refreshJourney(force: force)
            let entries = live.journeyPayloadEntries
            guard !entries.isEmpty else {
                log("行車時間讀取失敗: \(live.journeyError ?? "冇數據")")
                return
            }
            let payload = DashProtocol.encodeJourney(
                captureEpoch: live.captureEpoch, entries: entries)
            // Don't re-send an identical payload: the display already has it, and
            // a BLE write every tick for nothing costs power on both ends.
            guard force || payload != lastJourneyPayload else { return }
            lastJourneyPayload = payload
            central.write(payload, to: DashProtocol.UUIDs.journey)
            lastJourneyPush = Date()
            let liveCount = entries.filter { $0.minutes < DashProtocol.minutesClosed }.count
            log("已推送行車時間（\(liveCount)/\(entries.count) 個路段）")
        }
        pushFuelIfStale(force: force)
    }

    func pushSlotNames() {
        central.write(DashProtocol.encodeSlotNames(SlotConfig.slotNamesPayloadEntries()),
                      to: DashProtocol.UUIDs.slotNames)
        log("已推送路線名稱")
    }

    /// Called by the settings UI when the user changes a slot route.
    func routeConfigChanged() {
        // Drop the old route's minutes first: the Dashboard reads the route NAME
        // from SlotConfig (already changed) but the MINUTES from LiveDataStore —
        // leaving the old value would show the new route's name against the old
        // route's travel time. Refetch even when no display is connected.
        live.invalidateConfigurableSlots()
        Task { await live.refreshJourney(force: true) }

        guard linkReady else { return }
        pushSlotNames()
        pushTimeSyncAndJourney(force: true)
    }

    private func pushFuelIfStale(force: Bool) {
        guard force || -lastFuelPush.timeIntervalSinceNow > 6 * 3600 else { return }
        Task {
            guard await live.refreshFuel() else {
                log("油價讀取失敗（無 cache）")
                return
            }
            central.write(live.fuelPayload, to: DashProtocol.UUIDs.fuelPrices)
            lastFuelPush = Date()
            log("已推送油價（消委會）")
        }
    }

    private func runMetersFlow() {
        // Re-entrancy guard: two 掃一掃 presses used to run two concurrent
        // meterQuery.run()s on the same service, which overwrote (and leaked)
        // the location CheckedContinuation — that Task then never finished and
        // its background-task assertion was never ended, so iOS would kill us.
        guard !metersRunning else {
            log("咪錶掃描進行中，忽略重複請求")
            return
        }
        metersRunning = true
        lastMetersRun = Date()

        // Buy background time: the whole flow (GPS + ~700 KB fetch) can
        // exceed the ~10 s BLE wake window.
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "meters") {
            // Expiration handler — without it an unended task is a hard kill.
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
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
                // keep the list fresh for the next 10 minutes (journey ticks drive it)
                metersAutoUntil = Date().addingTimeInterval(600)
                log((status == 4 ? "咪錶(全滿): " : "咪錶: ")
                    + groups.map { "\($0.name) \($0.vacant)/\($0.total)" }.joined(separator: ", "))
            case 1: log("咪錶: 定位失敗")
            case 2: log("咪錶: 佔用數據讀取失敗")
            default: log("咪錶: 4公里內冇咪錶")
            }
            metersRunning = false
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
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
                // meters auto-refresh window (10 min after a manual scan)
                if Date() < metersAutoUntil, -lastMetersRun.timeIntervalSinceNow > 110 {
                    log("咪錶自動刷新")
                    runMetersFlow()
                }
            case .fullResync:
                pushTimeSyncAndJourney(force: true)
            case .needPair:
                // Device rejected our writes — we lack a valid token
                if PairingToken.isSet {
                    log("裝置要求重新授權")
                    central.writeAuthToken()
                } else {
                    needsPairing = true
                    log("未配對 — 請用相機掃描顯示屏 QR")
                }
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
