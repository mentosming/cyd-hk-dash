# Data sources (all data.gov.hk, verified 2026-07-10)

Attribution required: data from DATA.GOV.HK / Transport Department.

## 1. Journey Time Indicators v2

- URL: `https://resource.data.one.gov.hk/td/jss/Journeytimev2.xml`
- Updated every 2 minutes; ~tens of KB. Poll no faster than 120 s.
- Root `<jtis_journey_list>`, repeated `<jtis_journey_time>`:
  - `LOCATION_ID` — JTI sign location (H1–H9, H11, K01–K08, N01–N13, SJ1–SJ5)
  - `DESTINATION_ID` — `CH` 紅隧, `EH` 東隧, `WH` 西隧, `LRT` 獅隧, `TCT` 大老山, `TSCA` 青沙, `ABT` 香港仔隧道, `TKOLTT`/`TKOT` 將軍澳, …
  - `CAPTURE_DATE` — `YYYY-MM-DDTHH:MM:SS` HK local
  - `JOURNEY_TYPE` — `1` = journey time, `2` = special bitmap
  - `JOURNEY_DATA` — minutes when type 1; type 2: `1`=congestion, `3`=tunnel closed, `4`=blank; `-1`=N/A
  - `COLOUR_ID` — `1` red, `2` amber, `3` green, `-1` N/A
- Useful locations:
  - `H2` Canal Rd flyover (港島→九龍): CH, EH, WH
  - `K03` Waterloo Rd (九龍→港島): CH, EH, WH
  - `SJ1` Tai Po Rd nr racecourse: LRT; `SJ2` Tate's Cairn Hwy: TCT, TSCA; `SJ3` Tolo Hwy: spares

## 2. Metered parking spaces

### Locations (static-ish, refresh daily via ETag)
- URL: `https://resource.data.one.gov.hk/td/psiparkingspaces/spaceinfo/parkingspaces.csv`
- ~4.8 MB, ~20,690 rows. **Quirks: line 1 = BOM + date, line 2 = empty commas, header on line 3.**
- Columns: `PoleId,ParkingSpaceId,Region,Region_tc,Region_sc,District,District_tc,District_sc,SubDistrict,SubDistrict_tc,SubDistrict_sc,Street,Street_tc,Street_sc,SectionOfStreet,SectionOfStreet_tc,SectionOfStreet_sc,Latitude,Longitude,VehicleType,LPP,OperatingPeriod,TimeUnit,PaymentUnit`

### Occupancy (fetch on demand only)
- URL: `https://resource.data.one.gov.hk/td/psiparkingspaces/occupancystatus/occupancystatus.csv`
- ~715 KB, ~20k rows, refreshed ~every minute. Header on line 1.
- Columns: `ParkingSpaceId,ParkingMeterStatus,OccupancyStatus,OccupancyDateChanged`
- `ParkingMeterStatus`: `N` = normal (only count these). `OccupancyStatus`: `V` vacant, `O` occupied, anything else = unknown → treat as not vacant.
- Timestamp format: `MM/DD/YYYY hh:mm:ss AM/PM`.
- Join key: `ParkingSpaceId`.

## 3. HK public holidays

- 1823 iCal JSON: `https://www.1823.gov.hk/common/ical/en.json` — cache locally, refresh yearly.
