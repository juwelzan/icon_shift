# Known limitations

## Imposed by the operating systems (cannot be fixed by IconShift)

| Platform | Limitation |
| --- | --- |
| all | An installed app's application id / bundle id / package identity / signing identity cannot change. A build with new ids is a different app with separate data. |
| Android | Only icon+label pairs compiled into activity-aliases; icon and label always change together. Launchers cache icons (seconds, or until a launcher restart on some OEMs). Pinned home-screen shortcuts to the previous alias are removed by most launchers. Themed (monochrome) icons are shown only if the user enabled them. The recents title follows `MaterialApp.title`. |
| iOS | Display name cannot change at runtime. Every icon change shows a system alert. Icon changes need the app in the foreground. Dark/tinted appearances follow the system appearance only. |
| macOS | Only the running app's Dock icon and window title; Finder, Launchpad, Dock (when not running) and the menu-bar name come from the signed bundle. |
| Windows | Only the window's title-bar/Alt-Tab/unpinned-taskbar icon and the window title. Pinned taskbar entries, shortcuts, the `.exe` icon and MSIX identity are build- or install-time. |
| Linux | Window icon only on X11; Wayland uses the installed `.desktop` icon. `.desktop` files belong to the package manager / Flatpak / Snap. |
| Web | Only favicon, `document.title`, theme color. An installed PWA's name and icon come from `manifest.json`, refreshed by the browser on its own schedule. Safari updates dynamic favicons inconsistently. `MaterialApp.title` overwrites `document.title` on rebuild. |

## Of this implementation

| Area | Limitation | Workaround / plan |
| --- | --- | --- |
| Windows, Linux | **Not compiled or run** in this repository (no host available). The C++ and GTK code and their GTests are complete but unverified. | Build on Windows/Linux or CI before relying on them (IMPLEMENTATION_ROADMAP.md). |
| Web | No `flutter drive` integration run (no chromedriver); covered by Chrome DOM tests and a release build. | Run `flutter drive` with chromedriver. |
| Android | The "app closes when its launching alias is disabled" behaviour reported on some devices was checked only on an API 29 emulator. | Test on target OEM devices; if affected, switch while the app is backgrounded. |
| CLI | Edits template-shaped native files by exact patterns; customised files are refused, not merged. | Make the change by hand; the error names the file and pattern. |
| CLI | iOS/macOS localized display names (`InfoPlist.strings`) are not generated. | Add them in Xcode. |
| CLI | macOS `PRODUCT_NAME` (executable / `.app` name) is not changed. | Change it in `AppInfo.xcconfig` by hand. |
| CLI | SVG is accepted only as a Linux/web override; everything else needs PNG/JPEG. | Export PNG (1024 px). |
| CLI | Dart 3.13.4 crashes when pub precompiles `package:image` (`dart run icon_shift_cli`, `dart test`). | `dart run <path>/bin/icon_shift_cli.dart`; run test files directly. |
| Persistence | Selection storage has no schema version; unknown keys are dropped on load. | Sufficient for 0.x; add a version key before any incompatible change. |
| Publishing | License, repository URL and Android package (`com.example.icon_shift`) are not decided. | Owner decision (PRODUCTION_READINESS.md). |
