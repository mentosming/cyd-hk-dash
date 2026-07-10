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

    private static let restoreID = "CYDDashCentral"
    private static let savedPeripheralKey = "savedPeripheralUUID"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var chrJourney: CBCharacteristic?
    private var chrTimeSync: CBCharacteristic?
    private var chrMeters: CBCharacteristic?
    private var chrSlotNames: CBCharacteristic?
    private var chrFuelPrices: CBCharacteristic?
    private var chrCommand: CBCharacteristic?
    private var chrStatus: CBCharacteristic?
    private var lastStatus: DashProtocol.DeviceStatus?

    private(set) var isConnected = false
    var hasPairedDevice: Bool {
        UserDefaults.standard.string(forKey: Self.savedPeripheralKey) != nil
    }

    override init() {
        super.init()
        central = CBCentralManager(
            delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreID])
    }

    /// First-time pairing: scan for the CYD-DASH service.
    func startPairing() {
        guard central.state == .poweredOn else { return }
        log("掃描 CYD-DASH…")
        central.scanForPeripherals(withServices: [CBUUID(string: DashProtocol.UUIDs.service)])
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
        default: return nil
        }
    }

    private func reconnectSavedPeripheral() {
        guard let idString = UserDefaults.standard.string(forKey: Self.savedPeripheralKey),
              let id = UUID(uuidString: idString) else { return }
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(p)
        }
    }

    private func connect(_ p: CBPeripheral) {
        peripheral = p
        p.delegate = self
        log("connect() 已排隊（iOS 會喺裝置出現時完成）")
        central.connect(p)  // pending connect never times out
    }

    private func log(_ s: String) { delegate?.dashCentral(self, log: s) }
}

extension DashCentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            log("藍牙就緒")
            if peripheral == nil { reconnectSavedPeripheral() }
        case .unauthorized: log("藍牙權限被拒")
        case .poweredOff: log("藍牙已關閉")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        willRestoreState dict: [String: Any]) {
        // Relaunched in the background by a BLE event: re-adopt the peripheral.
        if let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = restored.first {
            peripheral = p
            p.delegate = self
            log("背景喚醒，恢復連接 \(p.identifier.uuidString.prefix(8))")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.savedPeripheralKey)
        log("搵到 CYD-DASH，配對中…")
        connect(p)
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        isConnected = true
        log("已連接，發現服務中…")
        p.discoverServices([CBUUID(string: DashProtocol.UUIDs.service)])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral,
                        error: Error?) {
        isConnected = false
        chrJourney = nil; chrTimeSync = nil; chrMeters = nil
        chrSlotNames = nil; chrFuelPrices = nil
        chrCommand = nil; chrStatus = nil
        delegate?.dashCentralDisconnected(self)
        log("已斷線，重新排隊連接")
        connect(p)  // immediately re-queue; completes on next power-up
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
            case DashProtocol.UUIDs.command:
                chrCommand = chr
                p.setNotifyValue(true, for: chr)
            case DashProtocol.UUIDs.status:
                chrStatus = chr
                p.readValue(for: chr)
            default: break
            }
        }
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
