<div align="center">

# CYD-DASH · 香港車載儀錶板

**A Hong Kong car dashboard on a $10 ESP32 display — tunnel journey times, live time-varying tolls, nearby parking-meter vacancies and pump prices.**

[**⚡ Flash it from your browser**](https://mentosming.github.io/cyd-hk-dash/) · [Protocol](docs/ble-protocol.md) · [Data sources](docs/data-sources.md)

</div>

---

香港駕駛者嘅車載顯示屏。一塊 ~HK$80 嘅 ESP32 屏,插車 USB,就有:

| | |
|---|---|
| **過海隧道** | 紅隧 / 東隧 / 西隧 雙向實時行車時間（連 ↑↓ 升跌）+ **現時時段收費**同下次轉價倒數 |
| **主要幹道** | 三條自選路線（獅隧 / 大老山 / 青沙 / 屯赤 / 將隧…）實時行車時間 |
| **附近咪錶** | 撳「掃一掃」→ 手機 GPS 喺 4 公里內搵**有空位、而家准泊**嘅街道（只計私家車位、依官方准泊時段）|
| **油價** | 消委會五間油公司（中石化 / 中國石油 / 加德士 / 埃索 / 蜆殼）× 無鉛 / 特級 / 柴油，最平自動高亮 |

## 點解要部手機？

ESP32 嘅藍牙冇 PAN profile，上唔到網。所以架構係 **iPhone 做橋**：

```
ESP32 (LVGL + NimBLE)  ←── BLE GATT (≤180 B) ──→  iPhone App  ←── HTTPS ──→  data.gov.hk / 消委會
   顯示 + 觸控                                     上網 + GPS + 解析
```

顯示屏零上網、零帳戶；手機負責攞數據（運輸署行車時間、咪錶佔用、消委會油價）同定位，然後推壓縮好嘅細 payload 上屏。上車自動連，落車自動斷。

## 你需要咩

1. **一塊 ESP32-2432S028R**（俗稱「Cheap Yellow Display」/ CYD，2.8" 320×240 觸控屏）— 淘寶 / AliExpress 搜 `ESP32-2432S028R`，約 HK$60–90
2. **一條 USB-A → micro-USB 線**（燒錄用）+ 車上 5V USB 供電
3. **一部 iPhone**（iOS 17+）

> 注意：市面有 v2/v3 雙 USB 版本（ST7789 屏），本 firmware 針對單 micro-USB 嘅 **ILI9341** 版本。

## 安裝（3 步）

### 1️⃣ 燒錄 firmware — 唔使裝任何嘢

用 **Chrome / Edge / Firefox 151+**（Safari 唔支援 Web Serial）開：

### 👉 **https://mentosming.github.io/cyd-hk-dash/**

插 USB → 撳「Install」→ 揀個 serial port → 等 30 秒。搞掂。

### 2️⃣ 裝手機 App

App Store 搜 **HK CarDash**（上架中）。或者自己 build：

```bash
cd ios-app && xcodegen generate && open CYDDash.xcodeproj
```

### 3️⃣ 掃 QR 配對

屏幕會顯示一個 QR → App 撳「掃描配對 QR」→ 掃 → 完。

之後每次上車自動連接，唔使再掃。

## 自己 build firmware

```bash
brew install platformio
cd firmware
pio run -e cyd -t upload            # build + 燒錄
pio test -e native                  # 收費引擎單元測試
pio device monitor -b 115200
```

隱藏操作：長按標題 = 3 點觸控校準 · 長按時鐘 = 清除配對兼重生 token · 撳右上藍牙點 = 叫出配對 QR

## 開發

架構、build 指令、同踩過嘅坑（LVGL tick、CRLF CSV、BLE stale bond…）全部喺 [CLAUDE.md](CLAUDE.md)。BLE 協議規範喺 [docs/ble-protocol.md](docs/ble-protocol.md)。

歡迎 PR — 見 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 數據來源與鳴謝

- 行車時間、咪錶分佈與佔用：**運輸署** via [DATA.GOV.HK](https://data.gov.hk)
- 車用燃油牌價：**消費者委員會**「油價資訊通」
- 公眾假期：**1823**
- 時變收費表：**運輸署**（本地計算，唔使 API）

## 授權

| 部分 | 授權 |
|---|---|
| `firmware/`, `tools/`, `docs/` | **GPL-3.0** — 改咗要開返源，防止有人攞去閉源賣硬件 |
| `ios-app/` | **MIT** — GPL 同 App Store 條款唔相容（[FSF 立場](https://www.fsf.org/blogs/licensing/more-about-the-app-store-gpl-enforcement)、VLC 曾被落架），所以 App 部分用寬鬆授權 |

⚠️ 本項目與運輸署、消委會或任何政府機構**無關**。數據僅供參考，駕駛時請以路面實際情況同官方指示為準。
