#include "gatt_server.h"

#include <Arduino.h>
#include <NimBLEDevice.h>

#include "../../include/app_config.h"
#include "../model/app_state.h"
#include "../model/hk_clock.h"
#include "protocol.h"

namespace ble {
namespace {

NimBLEServer* g_server = nullptr;
NimBLECharacteristic* g_chrCommand = nullptr;
NimBLECharacteristic* g_chrStatus = nullptr;
volatile bool g_connected = false;
volatile bool g_subscribed = false;
uint32_t g_lastJourneyTickMs = 0;

// Decoded payloads are staged here (BLE host task) then pushed into appstate.
proto::Journey g_stagedJourney;
proto::Meters g_stagedMeters;
proto::MeterMap g_stagedMeterMap;

void applyJourney(AppState& s) {
  s.journey = g_stagedJourney;
  s.journeyReceivedMs = millis();
  s.journeyDirty = true;
}

void applyMeters(AppState& s) {
  s.meters = g_stagedMeters;
  s.metersReceivedMs = millis();
  s.metersPending = false;
  s.metersDirty = true;
}

void applyMeterMap(AppState& s) {
  s.meterMap = g_stagedMeterMap;
  s.meterMapReceivedMs = millis();
  s.metersDirty = true;
}

void applyLink(AppState& s) {
  s.connected = g_connected;
  s.subscribed = g_subscribed;
  s.linkDirty = true;
}

class ServerCB : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*, NimBLEConnInfo&) override {
    g_connected = true;
    appstate::with(applyLink);
    log_i("BLE connected");
  }
  void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int reason) override {
    g_connected = false;
    g_subscribed = false;
    appstate::with(applyLink);
    log_i("BLE disconnected (reason %d), re-advertising", reason);
    NimBLEDevice::startAdvertising();
  }
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
      log_i("Meters write OK: status=%d groups=%d", g_stagedMeters.status,
            g_stagedMeters.count);
    } else {
      log_w("Bad meters payload (%d bytes)", v.length());
    }
  }
};

class MeterMapCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo&) override {
    NimBLEAttValue v = chr->getValue();
    if (proto::decodeMeterMap(v.data(), v.length(), g_stagedMeterMap)) {
      appstate::with(applyMeterMap);
      log_i("MeterMap write OK: %d points r=%dm", g_stagedMeterMap.count,
            g_stagedMeterMap.radius_m);
    } else {
      log_w("Bad metermap payload (%d bytes)", v.length());
    }
  }
};

class CommandCB : public NimBLECharacteristicCallbacks {
  void onSubscribe(NimBLECharacteristic*, NimBLEConnInfo&, uint16_t subValue) override {
    g_subscribed = subValue != 0;
    appstate::with(applyLink);
    if (g_subscribed) {
      log_i("Phone subscribed — requesting full resync");
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

  g_server = NimBLEDevice::createServer();
  static ServerCB serverCB;
  g_server->setCallbacks(&serverCB);

  NimBLEService* svc = g_server->createService(UUID_SERVICE);

  static JourneyCB journeyCB;
  svc->createCharacteristic(UUID_JOURNEY, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::READ)
      ->setCallbacks(&journeyCB);

  static TimeSyncCB timeSyncCB;
  svc->createCharacteristic(UUID_TIMESYNC, NIMBLE_PROPERTY::WRITE)->setCallbacks(&timeSyncCB);

  static MetersCB metersCB;
  svc->createCharacteristic(UUID_METERS, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::READ)
      ->setCallbacks(&metersCB);

  static MeterMapCB meterMapCB;
  svc->createCharacteristic(UUID_METERMAP, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::READ)
      ->setCallbacks(&meterMapCB);

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
}

bool isConnected() { return g_connected; }

}  // namespace ble
