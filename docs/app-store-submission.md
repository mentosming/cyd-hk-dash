# HK CarDash — App Store 提交 checklist

Bundle ID `com.kmai.hkcardash` · Team `A7YC2GSU54` · Widgets `com.kmai.hkcardash.widgets` · App Group `group.com.kmai.hkcardash`

## 你要親自做（Claude 做唔到）

- [ ] **App Store Connect 建 app record**，確認名 **HK CarDash** 未被人用（如撞名，備選：`CarDash HK`、`揸Dash`）
- [ ] **Developer Portal 開 App Group** `group.com.kmai.hkcardash`，加落兩個 App ID（app + widgets）
- [ ] **拍 demo 影片**（Review Notes 用，~30 秒）：影住實體 CYD-DASH 屏 + iPhone，示範掃 QR 配對 → 屏幕出隧道時間/收費。用手機影實物，唔好淨係錄屏
- [ ] 上傳 screenshots（可用 `/sc` skill 出圖）

## App Review Information（Notes 欄，照抄）

```
HK CarDash is a Hong Kong driving-information app. It works fully standalone —
no hardware or account required:

• 隧道收費 / Tolls — computed locally from the Transport Department's published
  time-varying toll schedule. No network needed.
• 過海隧道行車時間 / Journey times — Transport Department open data (data.gov.hk).
• 咪錶地圖 / Parking-meter map — Transport Department open data, on the Lands
  Department basemap (CSDI). Location is used ON-DEVICE ONLY to centre the map
  and sort nearby meters; it is never transmitted anywhere.
• 油價 / Fuel prices — Consumer Council "Oil Price Watch" open data.

OPTIONAL ACCESSORY
The "顯示屏 / Display" tab pairs with an optional open-source ESP32 car display
(https://github.com/mentosming/cyd-hk-dash) over Bluetooth LE. This is a plain
BLE GATT peripheral — no MFi program involvement is required (per Apple's MFi FAQ,
BLE-only accessories are exempt). The app does not require the accessory: every
other tab is fully functional without it.

FOR THE REVIEWER — DEMO MODE
To exercise the accessory features without hardware:
  Settings tab → tap the "版本 / Version" row FIVE times → a "示範模式 / Demo mode"
  toggle appears → turn it on.
Demo mode simulates a connected display and a plausible meter-occupancy snapshot,
so every screen can be exercised. A video of the real hardware pairing is attached.

No accounts, no server, no tracking. Privacy policy:
https://mentosming.github.io/cyd-hk-dash/privacy.html
```

## App Privacy（nutrition label）

**Data Not Collected.** 理由：定位純 on-device（`MeterQueryService` / 地圖），從來冇傳去任何伺服器；藍牙 token 只喺手機同顯示屏；相機只用嚟解 QR。Apple 定義「collect」＝傳出裝置外，所以全部唔使申報。

- Privacy policy URL（必填，Guideline 5.1.1(i)）：`https://mentosming.github.io/cyd-hk-dash/privacy.html`

## Metadata

**Subtitle**：`隧道收費・咪錶・油價`
**Category**：Primary `Navigation`，Secondary `Utilities`
**Keywords**：`隧道,收費,易通行,咪錶,泊車,油價,過海,交通,香港,tunnel,toll,parking,meter,petrol`

**Description（繁中）**
```
香港駕駛者嘅日常工具。

▍隧道收費，實時計算
紅隧、東隧、西隧嘅時段收費，同下次幾時轉價，一眼睇晒。純本地計算，開飛航模式都準。

▍過海隧道行車時間
運輸署實時數據，雙向、紅黃綠一望而知。

▍咪錶地圖
全港私家車咪錶，綠色即係有空位。只計你真係泊得嘅位 —— 唔包貨車、旅遊巴，仲會按官方准泊時段過濾，唔會叫你泊落一個而家禁泊嘅位。

▍油價
消委會五間油公司牌價，每種油最平嗰間自動高亮。

▍主畫面 Widget
隧道收費 widget 零網絡，準時跳價。仲有過海時間、油價 widget。

▍（可選）車載顯示屏
一塊約 HK$80 嘅開源 ESP32 屏，插車 USB，資料自動經藍牙上屏。冇都照用得晒全部功能。
開源教學：github.com/mentosming/cyd-hk-dash

──
資料來源：運輸署（DATA.GOV.HK）、消費者委員會、1823、地政總署。
本 App 與上述機構無關，資料僅供參考，駕駛時請以路面實際情況同官方指示為準。
不收集任何個人資料 — 定位只喺你部手機處理，唔會上傳。
```

**Description（EN）**
```
Everyday tools for driving in Hong Kong.

▍Tunnel tolls, computed live
Current time-varying tolls for the Cross-Harbour, Eastern and Western tunnels, plus a countdown to the next price change. Computed on-device — works in airplane mode.

▍Journey times
Live Transport Department data for all three harbour crossings, both directions.

▍Parking-meter map
Every private-car meter in Hong Kong; green means free. Only spaces you can actually use — goods-vehicle and coach bays are excluded, and meters are filtered by the official operating-period rules so you are never sent to a bay where parking is currently prohibited.

▍Fuel prices
Consumer Council pump prices for all five brands, cheapest highlighted.

▍Widgets
The toll widget needs no network and flips exactly when the price changes. Journey-time and fuel widgets too.

▍Optional car display
Pair with an open-source ESP32 dashboard (about HK$80) that shows everything on your windscreen. Entirely optional — every feature works without it.

──
Data: Transport Department (DATA.GOV.HK), Consumer Council, 1823, Lands Department. Not affiliated with any of them. For reference only.
No data collected — location never leaves your phone.
```

## 條款合規

- **地圖 attribution**（CSDI 條款）：地圖面已顯示「© 地圖資料由地政總署提供」。⚠️ 條款仲要求 **地政總署 logo 喺地圖面** — 去 CSDI portal 攞正式 logo 資產，加落 `MeterMapScreen` 個 attribution capsule 側邊
- 開放數據 attribution：Settings tab + Dashboard footer 已有
- Licenses：iOS app **MIT**（GPL 同 App Store 條款唔相容）；firmware GPL-3.0

## 提交前最後 check

- [ ] TestFlight 內測至少幾日（睇 widget 有冇準時跳價、地圖 tile 載入、耗電）
- [ ] Archive 用 Release config，確認 widget extension 有 embed
- [ ] Screenshots 6.9" + 6.5"
- [ ] Demo 影片 attach 落 Review Notes
