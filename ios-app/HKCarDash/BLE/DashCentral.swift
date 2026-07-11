// CoreBluetooth central: pairing, background auto-reconnect via state
// restoration, characteristic IO. The whole car UX depends on this file:
// a pending connect() never times out, so iOS completes it whenever the
// ESP32 powers up — even with the app suspended.
import CoreBluetooth
import Foundation

protocol DashCentralDelegate: AnyObject {
    func dashCentralReady(_ central: DashCentral, status: DashProtocol.DeviceStatus?)
    func dashCentral(_ central: DashCentral, didReceiveOpcode opcode: DashProtocol.Opcode)
    func dashCentralDisconnected(_ central: DashCentral)
    func dashCentral(_ central: DashCentral, log message: String)
}

final class DashCentral: NSObject {
    weak var delegate: DashCentralDelegate?

    private static let savedPeripheralKey = "savedPeripheralUUID"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var chrJourney: CBCharacteristic?
    private var chrTimeSync: CBCharacteristic?
    private var chrMeters: CBCharacteristic?
    private var chrSlotNames: CBCharacteristic?
    private var chrFuelPrices: CBCharacteristic?
    private var chrAuth: CBCharacteristic?
    private var chrCommand: CBCharacteristic?
    private var chrStatus: CBCharacteristic?
    private var lastStatus: DashProtocol.DeviceStatus?

    private(set) var isConnected = false
    var hasPairedDevice: Bool {
        UserDefaults.standard.string(forKey: Self.savedPeripheralKey) != nil
    }

    override init() {
        super.init()
        // No state restoration for now — a restored, stale peripheral (to a
        // board that has since reset) confused the connection state machine.
        // Foreground scan-by-name is reliable; background reconnect can be
        // layered back on once this is solid.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Scan for the device by name. Scanning with nil services (then filtering
    /// on the local name) is more reliable than a 128-bit service-UUID filter,
    /// which iOS may miss when the UUID sits in the scan response.
    func startPairing() {
        guard central.state == .poweredOn, !central.isScanning else { return }
        log("掃描 CYD-DASH…")
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func forgetDevice() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        UserDefaults.standard.removeObject(forKey: Self.savedPeripheralKey)
        peripheral = nil
    }

    func write(_ data: Data, to uuid: String) {
        guard let p = peripheral, let chr = characteristic(for: uuid) else {
            log("⚠️ write 丟棄（characteristic 未就緒）: …\(uuid.suffix(4)) \(data.count)B")
            return
        }
        p.writeValue(data, for: chr, type: .withResponse)
    }

    // MARK: private

    private func characteristic(for uuid: String) -> CBCharacteristic? {
        switch uuid {
        case DashProtocol.UUIDs.journey: return chrJourney
        case DashProtocol.UUIDs.timeSync: return chrTimeSync
        case DashProtocol.UUIDs.meters: return chrMeters
        case DashProtocol.UUIDs.slotNames: return chrSlotNames
        case DashProtocol.UUIDs.fuelPrices: return chrFuelPrices
        case DashProtocol.UUIDs.auth: return chrAuth
        default: return nil
        }
    }

    /// Ensure we're connected + discovered. Uses a background pending-connect
    /// to the known peripheral (for auto-reconnect when the car powers up) AND
    /// a name-filtered scan in parallel — the scan catches the case where the
    /// peripheral identifier changed (e.g. after bonds were cleared).
    func ensureConnected() {
        guard central.state == .poweredOn else { return }
        if let p = peripheral, p.state == .connected, chrAuth != nil {
            return  // genuinely connected + discovered
        }
        // Adopt a live OS-level connection to our service if one exists…
        let svc = CBUUID(string: DashProtocol.UUIDs.service)
        if let p = central.retrieveConnectedPeripherals(withServices: [svc]).first {
            log("採用已連接嘅 CYD-DASH")
            adoptAndConnect(p)
            return
        }
        // …otherwise scan by name.
        startPairing()
    }

    /// Adopt a peripheral and make sure it's connected & (re)discovered.
    private func adoptAndConnect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        switch p.state {
        case .connected:
            isConnected = true
            log("已連接，發現服務中…")
            p.discoverServices([CBUUID(string: DashProtocol.UUIDs.service)])
        case .connecting:
            break  // already in progress — don't stack connect() calls
        default:
            log("connect() 已排隊（iOS 會喺裝置出現時完成）")
            central.connect(p)
        }
    }

    private func connect(_ p: CBPeripheral) { adoptAndConnect(p) }

    private func log(_ s: String) { delegate?.dashCentral(self, log: s) }
}

extension DashCentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("藍牙就緒")
            ensureConnected()
        case .unauthorized: log("藍牙權限被拒")
        case .poweredOff: log("藍牙已關閉")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name
        let svcs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        log("見到裝置 name=\(advName ?? "?") rssi=\(RSSI) svcs=\(svcs.count)")
        let byName = advName?.contains("CYD-DASH") ?? false
        let byUUID = svcs.contains(CBUUID(string: DashProtocol.UUIDs.service))
        guard byName || byUUID else { return }
        central.stopScan()
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.savedPeripheralKey)
        log("搵到 CYD-DASH，連接中…")
        adoptAndConnect(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        isConnected = true
        peripheral = p
        p.delegate = self
        if central.isScanning { central.stopScan() }
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.savedPeripheralKey)
        log("已連接，發現服務中…")
        p.discoverServices([CBUUID(string: DashProtocol.UUIDs.service)])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral,
                        error: Error?) {
        isConnected = false
        chrJourney = nil; chrTimeSync = nil; chrMeters = nil
        chrSlotNames = nil; chrFuelPrices = nil; chrAuth = nil
        chrCommand = nil; chrStatus = nil
        delegate?.dashCentralDisconnected(self)
        log("已斷線，重新掃描連接")
        startPairing()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral,
                        error: Error?) {
        log("連接失敗：\(error?.localizedDescription ?? "?")，重試")
        connect(p)
    }
}

extension DashCentral: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: {
            $0.uuid == CBUUID(string: DashProtocol.UUIDs.service)
        }) else { return }
        p.discoverCharacteristics(nil, for: svc)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        for chr in service.characteristics ?? [] {
            switch chr.uuid.uuidString {
            case DashProtocol.UUIDs.journey: chrJourney = chr
            case DashProtocol.UUIDs.timeSync: chrTimeSync = chr
            case DashProtocol.UUIDs.meters: chrMeters = chr
            case DashProtocol.UUIDs.slotNames: chrSlotNames = chr
            case DashProtocol.UUIDs.fuelPrices: chrFuelPrices = chr
            case DashProtocol.UUIDs.auth: chrAuth = chr
            case DashProtocol.UUIDs.command:
                chrCommand = chr
                p.setNotifyValue(true, for: chr)
            case DashProtocol.UUIDs.status:
                chrStatus = chr
            default: break
            }
        }
        // Authorise FIRST (writes are FIFO, so this lands before any data
        // write), then read Status to trigger the ready → push sequence.
        writeAuthToken()
        if let st = chrStatus { p.readValue(for: st) }
    }

    /// Write the stored pairing token to the Auth characteristic. No-op (but
    /// logged) if the app hasn't been enrolled via the QR deep link yet.
    func writeAuthToken() {
        guard let token = PairingToken.data else {
            log("未有配對 token — 請掃描顯示屏 QR")
            return
        }
        guard let p = peripheral, let chr = chrAuth else { return }
        p.writeValue(token, for: chr, type: .withResponse)
        log("已提交配對 token")
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor chr: CBCharacteristic, error: Error?) {
        guard error == nil, let data = chr.value else { return }
        switch chr.uuid.uuidString {
        case DashProtocol.UUIDs.status:
            lastStatus = DashProtocol.decodeStatus(data)
            if let s = lastStatus {
                log("裝置 fw \(s.fwMajor).\(s.fwMinor) proto \(s.protocolVersion)")
                if s.protocolVersion != DashProtocol.protocolVersion {
                    log("⚠️ 協議版本唔匹配，請更新 firmware")
                }
            }
            delegate?.dashCentralReady(self, status: lastStatus)
        case DashProtocol.UUIDs.command:
            if let op = data.first.flatMap(DashProtocol.Opcode.init(rawValue:)) {
                delegate?.dashCentral(self, didReceiveOpcode: op)
            }
        default: break
        }
    }
}
