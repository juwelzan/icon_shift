# Platform support and setup

Capabilities are summarized in
[PLATFORM_CAPABILITIES.md](../PLATFORM_CAPABILITIES.md); verification status
in [PLATFORM_TEST_RESULTS.md](../PLATFORM_TEST_RESULTS.md).

| Platform | Minimum | Implementation | Native setup |
| --- | --- | --- | --- |
| Android | API 24 | Kotlin, activity-aliases | aliases + tooling intent-filter |
| iOS | 15.0 | Swift, alternate icons | icon sets + build setting |
| macOS | 12 (SPM) / 10.15 (CocoaPods) | Swift, Dock icon + window title | none |
| Windows | 10 | C++, Win32 + WIC | none |
| Linux | GTK 3 | C, GTK/GdkPixbuf | none |
| Web | evergreen browsers | Dart, `package:web` | none |

## Android

```xml
<activity android:name=".MainActivity" android:exported="true" …>
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
        <data android:scheme="icon-shift-tooling"/>
    </intent-filter>
</activity>
<!-- icon_shift:aliases:start -->
<!-- icon_shift:aliases:end -->
```

`icon_shift_cli generate` writes one alias per variant between the markers,
`android:enabled="true"` only on `default`. Hand-written aliases need
`<meta-data android:name="icon_shift.variant" android:value="<id>"/>`.

Behaviour notes:

* Switching enables the target alias first, then disables the others
  (Android 13+: one atomic call), and verifies the result.
* At startup the plugin re-enables a launcher entry if none is enabled or the
  enabled one was retired in an update.
* Launchers cache icons; pinned shortcuts to the old alias may disappear.
* Keep the tooling intent-filter: without a LAUNCHER filter on an
  `<activity>`, `flutter run` reports "launch activity not found".

## iOS

```
// ios/Flutter/Debug.xcconfig and Release.xcconfig
ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES
```

App icon sets must be named exactly like the variant (`dark.appiconset`).
`setAlternateIconName` shows a system alert and works only in the foreground.
Display name changes need a rebuild.

## macOS

Nothing to set up. The Dock icon and window title change while the app
runs and are re-applied at launch. The bundle (and its signature) is never
modified; Finder/Launchpad icons are build-time (`macos.app_icon`).

## Windows

Nothing to set up. Window, Alt-Tab and unpinned taskbar icon plus window
title change at runtime. Executable icon, version resources and window title
defaults are build-time (`windows.app_icon`, `application.windows`).
Shortcuts are left to your installer. MSIX package identity is reported by
`getApplicationInfo()`.

## Linux

Nothing to set up. Window icon (X11 only) and title change at runtime. Ship
the `.desktop` file and hicolor icons generated with `linux.icons` in your
package; the plugin never writes launcher entries. Flatpak/Snap/AppImage are
detected and reported.

## Web

Nothing to set up. Favicon, title and theme color change at runtime. The PWA
manifest (name, icons, maskable icons) is build-time (`application.web`,
`web.icons`).
