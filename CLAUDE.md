# CYD-DASH — 開發指引（俾 Claude Code）

香港車載儀錶板：ESP32-2432S028R（「Cheap Yellow Display」CYD，2.8" 320×240 ILI9341 TFT + XPT2046 電阻觸控）長期接車電源，顯示過海隧道行車時間/時變收費、幹道時間、附近咪錶空位、五間油公司油價。用戶母語廣東話，係有經驗嘅 iOS 開發者，UI 用易通行 teal（`#18AD8E`）深色風格。

## 架構

ESP32 經典藍牙冇 PAN，唔可以直接上網。所以：**iPhone companion app 做 BLE bridge** —— ESP32 長開 BLE 廣播（`CYD-DASH`），iPhone app 連接後上網攞 data.gov.hk / 消委會數據、用手機 GPS，推壓縮 binary payload（≤180B）俾板顯示。板只做顯示 + 觸控，零上網。

```
ESP32 (LVGL9 + NimBLE)  ←BLE GATT ≤180B→  iPhone CYDDash (SwiftUI+CoreBluetooth)  ←HTTPS→  data.gov.hk / 消委會
```

協議 normative spec：`docs/ble-protocol.md`（PROTOCOL_VERSION 2）。Firmware `src/ble/protocol.h` 同 iOS `BLE/DashProtocol.swift` 係鏡像，**改協議三處要一齊改**（docs + 兩邊）。

## 主要指令

```bash
# Firmware（PlatformIO）— port 會 re-enumerate（11410/11420…），用 glob
export PATH="/opt/homebrew/bin:$PATH"
cd firmware
pio test -e native                                              # toll engine 單元測試，唔使插板
pio run -e cyd -t upload --upload-port $(ls /dev/cu.usbserial-* | head -1)

# iOS（xcodegen 生成 .xcodeproj；改 project.yml/加檔後要 regenerate）
cd ios-app && xcodegen generate
xcodebuild -project CYDDash.xcodeproj -scheme CYDDash -destination 'id=<sim-id>' test          # 12 tests
xcodebuild -project CYDDash.xcodeproj -scheme CYDDash -destination 'generic/platform=iOS' -allowProvisioningUpdates build
# 裝真機（signing team A7YC2GSU54，個人帳戶簽名 7 日過期）
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/CYDDash-*/Build/Products/Debug-iphoneos/CYDDash.app | head -1)
xcrun devicectl device install app --device <iphone-udid> "$APP"

# 端到端測試（Mac 藍牙模擬手機，唔使 iPhone）
uv run --with bleak --with requests python tools/ble_sim.py [--fake] [--token <hex>]
```

## 踩過嘅坑（重要，唔好再中）

- **esp32_smartdisplay 唔設 LVGL tick** → 必須 `lv_tick_set_cb([]{return millis();})`，否則畫面凍結 + 觸控死（LVGL timer 唔行）。
- 項目路徑有空格（`ESP 32`）→ `LV_CONF_PATH` 用唔到，改 `-I include` + `LV_CONF_INCLUDE_SIMPLE`。
- CYD board JSON 要用 sunton repo commit `7b53da7c`（新版同 esp32_smartdisplay 2.1.1 唔夾）。
- **政府 CSV 係 CRLF**：Swift `split(separator:"\n")` 當 `\r\n` 一個 Character → 成檔一行，要 `split(whereSeparator:\.isNewline)`。
- JTI XML 有 default namespace → parser 要 strip（Python ET；Swift XMLParser 冇事）。
- **BLE 廣播**：NimBLE 2.x 預設唔含名/service UUID → iOS 見 `name=?`。要明確 `setAdvertisementData`(名入主 packet)+`setScanResponseData`(128-bit UUID)+`enableScanResponse(true)`。App 要 `scanForPeripherals(nil)` + local-name filter（唔好用 128-bit UUID filter）。
- **BLE stale bond**：改過 security 設定會令 client 留 stale bond → `CBError 14 "Peer removed pairing information"`，連 discovery 都 block。解法：板用**穩定靜態隨機位址**（NVS，`setOwnAddrType(BLE_OWN_ADDR_RANDOM)`+`setOwnAddr`，MSB `|=0xC0`），client 當佢全新裝置。**唔好用 CBCentralManager state restoration**（恢復 stale peripheral 搞亂狀態機）。
- **Serial monitor 開 port 預設 assert DTR/RTS 會揦停個板**：要 `s.dtr=False; s.rts=False` 先 `s.open()`。debug 唔好用 `devicectl launch --console`（會焗用戶部機彈 app）。
- 加新 UI 中文字串 → regenerate 字體（見下）。

## 字體（`firmware/src/ui/fonts/`）

用 `lv_font_conv`（Noto Sans TC）生成 subset。字集**自動抽**：掃 `firmware/src/ui/*.cpp` 全部 CJK 字 + `SlotConfig.swift` 路線名 → union。route 名喺 20px、街名喺 16px 顯示，所以 **20px 要有 UI+路線字，16px 要有埋 678 街名字**。加新 UI 字後跑抽字 + `lv_font_conv -r 0x20-0x7E -r 0x00B7 -r 0x2190-0x2193 --symbols "$UI[+$STREET]" --size 16/20 --bpp 4 --format lvgl --no-compress`。

## 咪錶數據準確性（官方 TD spec）

只計 `VehicleType == "A"`（私家車；C=旅遊巴 G=貨車）、排除 `PoleId > 90000`（測試錶）、依 `OperatingPeriod` 26-code 准泊時段（`OperatingPeriod.swift`，P/S 有明示禁泊窗）、`LPP` = 最長可泊 30/60/120 分。

## 硬件旋轉 / 觸控

顯示 `LV_DISPLAY_ROTATION_270`。觸控 XPT2046 可長按標題入 3 點校準（`calibrate.cpp`），存 NVS。長按時鐘 = 清 BLE bond + 重生 token。撳 BT dot = 叫配對 QR。

## 驗證狀態

全部真機實測通過（git `f7811ea` v1 → `892a576`）。iPhone 0 斷線穩定連接，QR 配對（掃一次記 token，以後自動連）+ token 授權 + 全部數據流通。生成檔（`.xcodeproj`、字體 `.c`）已 commit。
