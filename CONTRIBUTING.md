# Contributing

歡迎 PR / issue。

## Licensing（重要）

呢個 repo 有**兩個授權**：

- `firmware/`, `tools/`, `docs/` → **GPL-3.0**
- `ios-app/` → **MIT**（因為 GPL 同 Apple App Store 條款唔相容）

提交 PR 即表示你同意你嘅 contribution 用返該目錄嘅授權發佈。如果你嘅改動同時掂到兩邊，請喺 PR 講明。

## 開發環境

```bash
# Firmware
brew install platformio
cd firmware && pio run -e cyd && pio test -e native

# iOS（需要 Xcode + xcodegen）
brew install xcodegen
cd ios-app && xcodegen generate
xcodebuild -project CYDDash.xcodeproj -scheme CYDDash -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

CI 會自動跑 firmware build + native test；PR 要綠先 merge。

## 改協議之前

BLE 協議係 firmware 同 App 之間嘅合約。改任何 payload / characteristic **三處要一齊改**：

1. `docs/ble-protocol.md`（normative spec）
2. `firmware/src/ble/protocol.h`
3. `ios-app/CYDDash/BLE/DashProtocol.swift`

改完記得 bump `PROTOCOL_VERSION`（兩邊同時），並更新 `tools/ble_sim.py`。

## 加新 UI 中文字

字體係 subset（唔係全字庫），加新中文字串**一定要重新生成字體**，否則出空白格。做法見 [CLAUDE.md](CLAUDE.md) 「字體」一節。

## 支援新板

而家淨係支援 ESP32-2432S028R（ILI9341，單 micro-USB）。想加 v2/v3（ST7789）或者其他 CYD 變體：

- 加 board JSON 落 `firmware/boards/`
- 喺 `platformio.ini` 開新 env
- UI code 應該唔使改（LVGL 抽象咗）；主要係 display driver defines

## 踩過嘅坑

實現前請睇 [CLAUDE.md](CLAUDE.md) 嘅「踩過嘅坑」一節（LVGL tick、CRLF CSV、NimBLE advertising、BLE stale bond、serial DTR/RTS…）—— 慳返你好多時間。
