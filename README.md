# CYD-DASH — 香港車載儀錶板

ESP32-2432S028R（"Cheap Yellow Display"，2.8" 320×240 觸控 TFT）車載顯示屏：

- **過海隧道**：紅隧/東隧/西隧 雙向實時行車時間 + 現時時段收費（易通行風格 teal pill，連下次轉價倒數）
- **主要幹道**：獅隧/大老山/青沙 實時行車時間
- **附近咪錶**：撳「掃一掃」，用手機 GPS 喺 4 公里內搜尋**有空位**嘅街道，列最近 4 條（中文街名；全滿就列最近嘅街並標明「冇空位」）

ESP32 冇辦法經藍牙上網（無 PAN profile），所以架構係 **iPhone companion app 做 BLE bridge**：
ESP32 長開 BLE 廣播（`CYD-DASH`）→ 上車後 iPhone 喺背景自動重連 →
手機上網攞 data.gov.hk 數據 → 推壓縮 payload（≤180 bytes）俾 ESP32 顯示。

```
┌─────────────┐  BLE GATT   ┌──────────────┐  HTTPS   ┌──────────────────┐
│  ESP32 CYD   │◄──────────►│ iPhone        │◄────────►│ data.gov.hk      │
│  LVGL 9 UI   │  ≤180 B    │ CYDDash app   │          │ 運輸署 JTI XML    │
│  NimBLE      │  payloads  │ (背景 BLE)     │          │ 咪錶 CSV / 1823 PH│
└─────────────┘             └──────────────┘          └──────────────────┘
```

## 結構

| 路徑 | 內容 |
|------|------|
| `docs/ble-protocol.md` | **協議規範**（UUID、payload byte layout、slot registry）— 兩邊實現以此為準 |
| `docs/data-sources.md` | 數據源 URL、欄位、quirks（CSV header 喺第 3 行等） |
| `docs/toll-schedule.md` | 官方時變收費表 + 共用測試向量 |
| `firmware/` | PlatformIO + Arduino + LVGL 9（esp32_smartdisplay）+ NimBLE |
| `ios-app/` | SwiftUI companion app（xcodegen 生成 project） |
| `tools/ble_sim.py` | 用 Mac 藍牙模擬手機，推實時/假數據入板測試 |
| `tools/fetch_check.sh` | 檢查三個 data.gov.hk endpoint |

## Firmware：build + 燒錄

```bash
brew install platformio
cd firmware
pio test -e native            # toll engine 單元測試（唔使插板）
pio run -e cyd -t upload      # build + 燒錄（port 已設做 /dev/cu.usbserial-11420）
```

螢幕操作：左右掃 / 撳標題換頁；咪錶頁撳「掃一掃」。
夜間（19:30–07:00）背光自動調暗至 25%，觸摸恢復 30 秒。

## 端到端測試（未有 iPhone app 都得）

```bash
uv run --with bleak --with requests python tools/ble_sim.py         # 實時政府數據
uv run --with bleak --with requests python tools/ble_sim.py --fake  # 離線假數據
```

## iOS app

```bash
cd ios-app
xcodegen generate
open CYDDash.xcodeproj   # 揀你嘅 signing team，裝落真機（Simulator 冇藍牙）
```

首次用：開 app → 「配對 CYD-DASH」→ 俾藍牙 + 定位（Always）權限。
之後每次上車 iOS 會自動背景重連（force-quit 或重啟手機後要手動開返 app 一次）。

跑測試：`xcodebuild -project CYDDash.xcodeproj -scheme CYDDash -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`

## 已知限制

- iOS 背景 BLE 係 best-effort：force-quit / 重啟後要開返 app；咪錶 700KB fetch 喺弱網背景下可能超時（會喺下一個 tick 重試）
- SJ2（大老山公路）路牌間中離線（feed 俾 `-1`），螢幕顯示 `--`；可以喺 `DashProtocol.slots` 改用 SJ3
- 收費表跟法例，如有修訂改 `docs/toll-schedule.md` + 兩邊 engine 嘅 breakpoints
- 數據版權：DATA.GOV.HK / 運輸署

## 驗證狀態（2026-07-10）

- ✅ Firmware build + 燒錄，BLE 廣播中，free heap ~104KB
- ✅ Toll engine：firmware 3/3 native tests，iOS 6/6 tests（共用向量 parity）
- ✅ 端到端：Mac (`ble_sim.py`) → 板，實時運輸署數據成功顯示
- ✅ iPhone 真機配對 + 自動重連（斷電重上電 0.7 秒重連、3 秒內推齊數據）
- ✅ 掃一掃全鏈路：GPS → 20,682 車位資料庫 → 實時佔用 → 中文街名空位清單上板

## 開發途中踩過嘅坑（都修咗）

- esp32_smartdisplay 唔會設 LVGL tick source — 冇 `lv_tick_set_cb(millis)` 畫面凍結兼觸控死
- 政府 CSV 係 CRLF：Swift `split(separator: "\n")` 當 `\r\n` 係一個 Character，成個檔變一行 — 要用 `\.isNewline`
- JTI XML 有 default namespace，`ElementTree.iter("tag")` 搵唔到
- iOS 連接未 discover 完 characteristics 就 write 會被靜默丟棄 — 要排隊等 ready
- 政府咪錶數據有 9 個車位座標喺巴黎/印度（座標範圍 guard 排除）
- 街名中文字體：由 CSV 抽全港 931 條街 678 個唯一漢字生成 subset（~600KB flash）
