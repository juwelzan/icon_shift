# IconShift platform capabilities

What each operating system lets an app change about its own identity, and
therefore what IconShift does. The same data is available in code
(`IconShift.getPlatformCapabilities()`) and from the CLI
(`icon_shift_cli capabilities`); `test/property_table_sync_test.dart` keeps
all three in sync.

## 1. Identity properties at a glance

**R** = runtime (any value) · **R·pre** = runtime, preconfigured values only ·
**R·session** = runtime while the app runs (IconShift re-applies on launch) ·
**B** = build time only · **—** = not applicable / not possible.

| Property | Android | iOS | macOS | Windows | Linux | Web |
| --- | --- | --- | --- | --- | --- | --- |
| Display name (launcher) | R·pre (alias label) | B | B | B | B | B (manifest) |
| Window / document title | R·session (recent-apps label) | — | R·session | R·session | R·session | R·session |
| Launcher icon | R·pre (alias) | R·pre (alternate icon) | B | B | B | B (manifest) |
| Running-app icon | — | — | R·session (Dock) | R·session (title bar/taskbar) | R·session (X11 only) | R·session (favicon) |
| Adaptive / maskable icon | R·pre (part of alias) + B | — | — | — | — | B |
| Themed icon (monochrome, dark, tinted, clear) | B (user enables) | B (system applies dark/tinted; derives clear) | R·session (dark Dock icon) + B | R·session (dark icon) | R·session (dark icon) | R·session (dark favicon) + B |
| Downloaded (server) icon | — (build it in: `remote:`) | — (build it in: `remote:`) | R·session | R·session | R·session | R·session |
| Theme color | — | — | — | — | — | R·session + B |
| Application id (package / bundle / app id) | B, **new app** | B, **new app** | B, **new app** | B (MSIX), **new app** | B, **new app** | B (manifest id), new PWA |
| Gradle namespace | B | — | — | — | — | — |
| Executable name | — | B | B | B (data path changes) | B (data path changes) | — |
| Version / build number | B | B | B | B | B | B |
| Signing identity | B, update rejected if changed | B | B | B (MSIX publisher) | B (packages) | — |

**No platform lets an installed app change its own application id, bundle
id, package identity or signing identity.** IconShift's build-time tooling
changes them *before building*; the result is a different app for the OS.

## 2. Runtime scopes

`IconShift.getCapabilities()` reports, per operation, a scope:

| Scope | Meaning |
| --- | --- |
| `launcher` | What the OS shows to launch the app. Survives restarts. |
| `runningApp` | Dock / taskbar / title-bar icon of the running process. Lost on quit; IconShift re-applies the saved selection on `initialize()`. |
| `windowTitle` | Title of the main window. Session-only; re-applied on `initialize()`. |
| `browserTab` | Favicon / `document.title`. Session-only; re-applied on `initialize()`. |
| `none` | Not supported. |

## 3. Per platform

### Android

**Runtime.** Each variant is an `<activity-alias>` of `MainActivity` with its
own `android:icon`, `android:label` and meta-data `icon_shift.variant`.
Exactly one alias is enabled. Switching calls
`PackageManager.setComponentEnabledSetting(…, DONT_KILL_APP)` — on Android 13+
all changes in one `setComponentEnabledSettings` call — **enabling the new
alias before disabling the old one**, then reads the state back.

* Icons and labels must be compiled in; arbitrary strings/images are
  impossible. Icon and label are linked (`iconAndNameLinked: true`).
* Adaptive and monochrome layers are part of each alias's mipmap resource
  (`icon_shift_cli generate`). Whether themed icons are *shown* is a user
  setting (Android 13+); apps cannot switch it.
* `MainActivity` keeps a MAIN/LAUNCHER intent-filter **with**
  `<data android:scheme="icon-shift-tooling"/>`: `flutter run` needs a
  LAUNCHER `<activity>` (it ignores aliases), and the `<data>` element keeps
  launchers — which query without data — from showing a second icon.
* **Update safety.** If an update removes the alias a device currently uses,
  that device loses its launcher entry. `icon_shift_cli` therefore keeps a
  disabled *retired* alias for removed/renamed variants
  (`icon_shift.retired_to`), and the plugin moves devices off retired or
  missing aliases when the app starts.
* Launchers cache icons (seconds to a launcher restart on some OEMs).
  Pinned shortcuts to a disabled alias are removed by most launchers.
* The recent-apps label follows the active alias after a switch, and
  `setDisplayName` sets it to any string (`Activity.setTaskDescription`).
  `MaterialApp.title` sets it too on every rebuild — bind it to
  `IconShift.displayNameListenable`.
* Downloaded images can never become the launcher icon; server icons are
  added at build time (`remote:` in icon_shift.yaml).

**Build time.** `applicationId` (new app, separate data), `namespace` (moves
Kotlin/Java sources), `<application android:label>` **and the IconShift
alias labels that show the default name** (the launcher shows alias labels,
not the application label), version (pubspec).
Signing is never touched; a different key cannot update an installed app.

### iOS

**Runtime.** `UIApplication.setAlternateIconName` with icon sets compiled into
the app (`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`, or
`CFBundleAlternateIcons`). The system always shows a confirmation alert; the
call must happen in the foreground. IconShift skips re-applying the active
icon so no needless alert appears. Dark and tinted appearances (iOS 18+) are
selected by the system appearance, not by the app.

**Display name: build time only** (`CFBundleDisplayName`). Runtime calls
return `unsupported` with code `buildRequired`.

**Build time.** Bundle id (needs a matching App ID and provisioning profile;
separate app and data container — data can only be shared through an App
Group the old app already declared), display name, version.

### macOS

**Runtime.** Dock icon of the running app (`applicationIconImage`) and the
main window title. Both reset on quit; IconShift re-applies them.

Not done, by design: changing the bundle icon or `Info.plist` on disk —
it would invalidate the code signature and notarization and is impossible in
the sandbox. Finder/Launchpad icons and the menu-bar name are build-time.

**Build time.** Bundle id (new defaults domain, sandbox container and privacy
permissions), `CFBundleName`/`CFBundleDisplayName`, AppIcon set, version.

### Windows

**Runtime.** `WM_SETICON` on the Flutter window (title bar, Alt-Tab, the
unpinned taskbar button) and `SetWindowTextW`.

Distinct identities: the **executable icon** (resource, build time), the
**shortcut** icon/name (owned by the installer; not modified), the **window**
icon/title (runtime), the **package** identity (MSIX `Name`+`Publisher`,
build time). Executable resources are never rewritten at runtime.

**Build time.** `BINARY_NAME`, version-resource strings, window title,
`app_icon.ico`. `path_provider` derives `%APPDATA%` folders from
CompanyName/ProductName, so changing them hides old data.

### Linux

**Runtime.** GTK window icon (X11 only — Wayland has no window-icon protocol;
reported as unsupported) and window/header-bar title.

Installed `.desktop` files belong to the package manager, Flatpak or Snap and
are not modified. `getApplicationInfo()` reports the installation type
(Flatpak, Snap, AppImage, system, unpackaged).

**Build time.** `APPLICATION_ID`, `BINARY_NAME`, window titles; hicolor icons
and a `.desktop` entry for packaging (`linux.icons`).

### Web

**Runtime.** Favicon (`<link rel="icon">`), `document.title`,
`<meta name="theme-color">`. The originals are remembered for
`restoreDefault()`. `MaterialApp.title` also writes `document.title` on
rebuild — bind it to IconShift state.

**Installed PWA name/icon cannot change at runtime**: browsers read
`manifest.json` at install and refresh it on their own schedule (some ask the
user; iOS home-screen apps generally need re-adding).

**Build time.** Manifest name, short name, description, colors, icons
including maskable ones; `<title>`.

## 4. Persistence

The last requested selection (identity, icon, custom name) is stored in
`SharedPreferences` (Android), `UserDefaults` (iOS/macOS), the per-user
registry `HKCU\Software\IconShift\<exe name>` (Windows),
`$XDG_CONFIG_HOME/icon_shift/<program>.ini` (Linux) or `localStorage` (web).
On initialize it is repaired: unknown keys dropped, renamed variants migrated
(`renamedVariants`), removed variants forgotten. Android/iOS keep the native
change themselves, so nothing is re-applied there.

## 5. Permissions

IconShift requests no runtime permissions on any platform.
