# Platform test results

Environment: macOS host (Apple silicon), Xcode 27.2, Flutter 3.49.0 /
Dart 3.13.4, Android emulator "Android SDK built for arm64" (Android 10,
API 29), iPhone 17 simulator (iOS 26.5), Chrome 156. Date: 2026-11-02.

Legend: **unit** = automated tests with fakes/fixtures · **integration** =
automated tests against the real platform implementation on a device or
simulator · **manual** = performed by hand and observed · **not verified**.

## Summary

| Platform | Unit | Built | Integration | Manual | Status |
| --- | --- | --- | --- | --- | --- |
| Dart core (all platforms) | 80 tests pass | – | – | – | verified (unit) |
| Android | 8 Kotlin tests pass | PENDING | PENDING | PENDING | PENDING |
| iOS | – | PENDING | PENDING | – | PENDING |
| macOS | – | PENDING | PENDING | – | PENDING |
| Web | 11 Chrome DOM tests pass | PENDING | not run (no chromedriver) | – | PENDING |
| Windows | GTests written | **not built** | **not run** | – | **not verified** |
| Linux | GTests written | **not built** | **not run** | – | **not verified** |
| CLI | 13 + 17 tests pass | – | PENDING (fresh app) | – | PENDING |

## Details

PENDING
