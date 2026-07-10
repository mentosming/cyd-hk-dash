#pragma once
// 3-point resistive touch calibration. Entry: long-press the header title.
// Runs with display rotation temporarily reset to 0 so captured points are
// in the driver's native (portrait) space — the same space the library's
// calibration transform operates in.
namespace calibrate {

void loadFromNVS();  // apply saved calibration at boot
void start();        // open the calibration overlay
bool isActive();

}  // namespace calibrate
