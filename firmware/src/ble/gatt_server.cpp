#include "gatt_server.h"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include "../../include/app_config.h"
#include "../model/app_state.h"
#include "../model/data_cache.h"
#include "../model/hk_clock.h"
#include "protocol.h"

namespace ble {
namespace {

NimBLEServer* g_server = nullptr;
NimBLECharacteristic* g_chrCommand = nullptr;
NimBLECharacteristic* g_chrStatus = nullptr;
volatile bool g_connected = false;
volatile bool g_subscribed = false;
volatile uint16_t g_connHandle = 0;
volatile bool g_kickedThisConn = false;
volatile uint32_t g_subscribedAtMs = 0;
uint32_t g_lastJourneyTickMs = 0;

// Decoded payloads are staged here (BLE host task) then pushed into appstate.
proto::Journey g_stagedJourney;
proto::Meters g_stagedMeters;
proto::SlotNames g_stagedSlotNames;
proto::FuelPrices g_stagedFuel;

void applyJourney(AppState& s) {
  // Remember the previous capture's minutes per slot for the trend arrows
  if (s.journeyReceivedMs != 0 && s.journey.capture_epoch != g_stagedJourney.capture_epoch) {
    for (uint8_t i = 0; i < s.journey.count; i++) {
      s.prevMinutes[s.journey.entries[i].slot] = s.journey.entries[i].minutes;
    }
  }
  s.journey = g_stagedJourney;
  s.journeyReceivedMs = millis() | 1;
  s.journeyDirty = true;
}

void applyMeters(AppState& s) {
  s.meters = g_stagedMeters;
  s.metersReceivedMs = millis() | 1;
  s.metersPending = false;
  s.metersDirty = true;
}

void applyFuel(AppState& s) {
  s.fuel = g_stagedFuel;
  s.fuelReceivedMs = millis() | 1;
  s.fuelDirty = true;
}

void applySlotNames(AppState& s) {
  for (uint8_t i = 0; i < g_stagedSlotNames.count; i++) {
    const proto::SlotName& n = g_stagedSlotNames.names[i];
    strncpy(s.slotNames[n.slot], n.name, proto::kSlotNameMax);
    s.slotNames[n.slot][proto::kSlotNameMax] = '\0';
  }
  s.slotNamesDirty = true;
}

void applyLink(AppState& s) {
  s.connected = g_connected;
  s.subscribed = g_subscribed;
  s.linkDirty = true;
}

void setPasskeyShown(AppState& s) { s.showPasskey = BLE_PASSKEY; }
void clearPasskeyShown(AppState& s) { s.showPasskey = 0; }

class ServerCB : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo& info) override {
    g_connected = true;
    g_connHandle = info.getConnHandle();
    g_kickedThisConn = false;
    appstate::with(applyLink);
    log_i("BLE connected");
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int reason) override {
    g_connected = false;
    g_subscribed = false;
    appstate::with(applyLink);
    appstate::with(clearPasskeyShown);
    log_i("BLE disconnected (reason %d), re-advertising", reason);
    NimBLEDevice::startAdvertising();
  }
#if BLE_REQUIRE_BONDING
  uint32_t onPassKeyDisplay() override {
    appstate::with(setPasskeyShown);
    log_i("Pairing: displaying passkey");
    return BLE_PASSKEY;
  }
  void onAuthenticationComplete(NimBLEConnInfo& info) override {
    appstate::with(clearPasskeyShown);
    log_i("Pairing complete: encrypted=%d bonded=%d", info.isEncrypted(), info.isBonded());
  }
#endif
};

class JourneyCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo&) override {
    NimBLEAttValue v = chr->getValue();
    if (proto::decodeJourney(v.data(), v.length(), g_stagedJourney)) {
      appstate::with(applyJourney);
      log_i("Journey write OK: %d slots", g_stagedJourney.count);
    } else {
      log_w("Bad journey payload (%d bytes)", v.length());
    }
  }
};

class TimeSyncCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo&) override {
    NimBLEAttValue v = chr->getValue();
    proto::TimeSync ts;
    if (proto::decodeTimeSync(v.data(), v.length(), ts)) {
      hkclock::onTimeSync(ts.epoch_utc, ts.tz_min, ts.flags);
      log_i("TimeSync write OK: epoch %u flags %u", (unsigned)ts.epoch_utc, ts.flags);
    } else {
      log_w("Bad timesync payload (%d bytes)", v.length());
    }
  }
};

class MetersCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo&) override {
    NimBLEAttValue v = chr->getValue();
    if (proto::decodeMeters(v.data(), v.length(), g_stagedMeters)) {
      appstate::with(applyMeters);
      datacache::saveMetersNow();
      log_i("Meters write OK: status=%d groups=%d", g_stagedMeters.status,
            g_stagedMeters.count);
    } else {
      log_w("Bad meters payload (%d bytes)", v.length());
    }
  }
};

class SlotNamesCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo&) override {
    NimBLEAttValue v = chr->getValue();
    if (proto::decodeSlotNames(v.data(), v.length(), g_stagedSlotNames)) {
      appstate::with(applySlotNames);
      datacache::saveSlotNames();
      log_i("SlotNames write OK: %d names", g_stagedSlotNames.count);
    } else {
      log_w("Bad slotnames payload (%d bytes)", v.length());
    }
  }
};

class FuelPricesCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo&) override {
    NimBLEAttValue v = chr->getValue();
    if (proto::decodeFuelPrices(v.data(), v.length(), g_stagedFuel)) {
      appstate::with(applyFuel);
      datacache::saveFuelNow();
      log_i("FuelPrices write OK");
    } else {
      log_w("Bad fuelprices payload (%d bytes)", v.length());
    }
  }
};

class CommandCB : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic*, NimBLEConnInfo&, uint16_t subValue) override {
    g_subscribed = subValue != 0;
    appstate::with(applyLink);
    if (g_subscribed) {
      log_i("Phone subscribed — requesting full resync");
      g_subscribedAtMs = millis();
      notifyCommand(CMD_FULL_RESYNC);
      g_lastJourneyTickMs = millis();
    }
  }
};

class StatusCB : public NimBLECharacteristicCallbacks {
  void onRead(NimBLECharacteristic* chr, NimBLEConnInfo&) override {
    AppState s = appstate::snapshot();
    uint32_t nowMs = millis();
    auto age = [nowMs](uint32_t recvMs) -> uint16_t {
      if (recvMs == 0) return 0xFFFF;
      uint32_t a = (nowMs - recvMs) / 1000;
      return a > 0xFFFE ? 0xFFFE : (uint16_t)a;
    };
    uint8_t buf[12];
    proto::encodeStatus(buf, PROTOCOL_VERSION, FW_MAJOR, FW_MINOR, nowMs / 1000,
                        age(s.journeyReceivedMs), age(s.metersReceivedMs));
    chr->setValue(buf, sizeof(buf));
  }
};

}  // namespace

void begin() {
  NimBLEDevice::init(BLE_DEVICE_NAME);
  NimBLEDevice::setMTU(512);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

#if BLE_REQUIRE_BONDING
  // "Just Works" bonding: iOS shows a simple Pair? dialog (no PIN). Passkey
  // (DISPLAY_ONLY) pairing was tried first but iOS never surfaced the PIN
  // dialog and SMP aborted with encrypted=0 — Just Works is the reliable path.
  NimBLEDevice::setSecurityAuth(true, false, true);  // bond, no MITM, secure connections
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);
  constexpr uint32_t kWriteProps = NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC;
#else
  constexpr uint32_t kWriteProps = NIMBLE_PROPERTY::WRITE;
#endif

  g_server = NimBLEDevice::createServer();
  static ServerCB serverCB;
  g_server->setCallbacks(&serverCB);

  NimBLEService* svc = g_server->createService(UUID_SERVICE);

  static JourneyCB journeyCB;
  svc->createCharacteristic(UUID_JOURNEY, kWriteProps | NIMBLE_PROPERTY::READ)
      ->setCallbacks(&journeyCB);

  static TimeSyncCB timeSyncCB;
  svc->createCharacteristic(UUID_TIMESYNC, kWriteProps)->setCallbacks(&timeSyncCB);

  static MetersCB metersCB;
  svc->createCharacteristic(UUID_METERS, kWriteProps | NIMBLE_PROPERTY::READ)
      ->setCallbacks(&metersCB);

  static SlotNamesCB slotNamesCB;
  svc->createCharacteristic(UUID_SLOTNAMES, kWriteProps)->setCallbacks(&slotNamesCB);

  static FuelPricesCB fuelCB;
  svc->createCharacteristic(UUID_FUELPRICES, kWriteProps | NIMBLE_PROPERTY::READ)
      ->setCallbacks(&fuelCB);

  static CommandCB commandCB;
  g_chrCommand = svc->createCharacteristic(UUID_COMMAND,
                                           NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ);
  g_chrCommand->setCallbacks(&commandCB);

  static StatusCB statusCB;
  g_chrStatus = svc->createCharacteristic(UUID_STATUS, NIMBLE_PROPERTY::READ);
  g_chrStatus->setCallbacks(&statusCB);

  svc->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(UUID_SERVICE);
  adv->setName(BLE_DEVICE_NAME);
  adv->start();
  log_i("BLE advertising as %s", BLE_DEVICE_NAME);
}

void notifyCommand(uint8_t opcode) {
  if (!g_chrCommand || !g_subscribed) return;
  g_chrCommand->setValue(&opcode, 1);
  g_chrCommand->notify();
}

void tick() {
  if (!g_subscribed) return;
  if (millis() - g_lastJourneyTickMs >= JOURNEY_TICK_MS) {
    g_lastJourneyTickMs = millis();
    notifyCommand(CMD_JOURNEY_TICK);
  }

  // Self-heal watchdog: connected+subscribed but no fresh journey for a full
  // stale window means the phone app is wedged — force a disconnect so iOS
  // re-runs the reconnect + resync path. Once per connection.
  if (!g_kickedThisConn && g_server &&
      millis() - g_subscribedAtMs > JOURNEY_STALE_S * 1000UL) {
    AppState s = appstate::snapshot();
    // journeyReceivedMs also survives from the NVS cache at boot, so compare
    // against the subscribe time: fresh data must have arrived SINCE then.
    bool freshSinceSubscribe =
        s.journeyReceivedMs != 0 && (int32_t)(s.journeyReceivedMs - g_subscribedAtMs) >= 0 &&
        (millis() - s.journeyReceivedMs) / 1000 <= JOURNEY_STALE_S;
    if (!freshSinceSubscribe) {
      g_kickedThisConn = true;
      log_w("Watchdog: no fresh journey for >%ds while connected — kicking phone",
            JOURNEY_STALE_S);
      g_server->disconnect(g_connHandle);
    }
  }
}

bool isConnected() { return g_connected; }

void clearBonds() {
  log_w("Clearing all BLE bonds (user request)");
  NimBLEDevice::deleteAllBonds();
  if (g_connected && g_server) g_server->disconnect(g_connHandle);
}

}  // namespace ble
