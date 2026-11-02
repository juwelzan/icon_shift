# IconShift platform capabilities

This document states what each platform's operating system actually allows an
app to change about its own identity at runtime, and therefore what IconShift
does and does not do. It is the reference behind `IconShift.getCapabilities()`.

The column **Scope** tells you *where* the change is visible. This matters:
"changing the icon" means very different things on a phone launcher and in a
browser tab.

| Scope            | Meaning                                                                 |
| ---------------- | ----------------------------------------------------------------------- |
| `launcher`       | The icon/name the OS shows to launch the app (home screen, app drawer). Survives restarts. |
| `runningApp`     | The Dock / taskbar / title-bar icon of the *running* process. Lost when the app quits; IconShift re-applies the saved selection on the next `initialize()`. |
| `windowTitle`    | The title of the app's main window. Session-only; re-applied on `initialize()`. |
| `browserTab`     | The document title / favicon of the browser tab (or installed-PWA window title). Session-only; re-applied on `initialize()`. |
| `none`           | Not supported.                                                          |

## Support matrix

| Platform | Icon                                   | Display name                            | Icon & name linked | Needs prebuilt native resources | Verified in this repo |
| -------- | -------------------------------------- | --------------------------------------- | ------------------ | ------------------------------- | --------------------- |
| Android  | `launcher`, preconfigured variants only | `launcher`, preconfigured variants only (alias label) | **yes**            | yes (activity-aliases + mipmaps) | see README "Verification" |
| iOS      | `launcher`, preconfigured variants only (system shows a confirmation alert) | `none`                                  | no                 | yes (alternate app icon sets)   | see README "Verification" |
| macOS    | `runningApp` (Dock), any PNG asset     | `windowTitle`, any string               | no                 | no                              | see README "Verification" |
| Windows  | `runningApp` (title bar + taskbar button), any PNG asset | `windowTitle`, any string | no                 | no                              | **not compiled here** |
| Linux    | `runningApp` on X11 only; `none` on Wayland | `windowTitle` (+ GTK header bar), any string | no            | no                              | **not compiled here** |
| Web      | `browserTab` (favicon)                 | `browserTab` (`document.title`)         | no                 | no                              | see README "Verification" |

## Android

**Mechanism.** Each identity variant is an `<activity-alias>` in
`AndroidManifest.xml` targeting the real `MainActivity`, carrying its own
`android:icon` and `android:label`, a `MAIN`/`LAUNCHER` intent filter, and the
meta-data `icon_shift.variant=<variantId>`. Exactly one alias is enabled at a
time. Switching calls `PackageManager.setComponentEnabledSetting` with
`DONT_KILL_APP`, **enabling the new alias before disabling the old one**, so
there is never a moment with zero launcher entries.

What this means:

- Icons and labels must be compiled into the APK. Arbitrary runtime images or
  strings are impossible; `setDisplayName('any text')` is `unsupported`.
- Icon and label are a pair: an alias has exactly one of each. Switching the
  icon to `blue` also switches the launcher label to the `blue` alias's label.
  `IconShiftCapabilities.iconAndNameLinked` is `true` and results say so.
- `MainActivity` must **not** keep its own `LAUNCHER` intent filter, otherwise
  the launcher shows two entries. IconShift detects and reports this.
- Disabling the alias that launched the current task can make some launchers /
  OS versions close the task. IconShift's behaviour on the tested emulator is
  recorded in the README "Verification" section.
- Launchers cache icons; some OEM launchers refresh only after several seconds
  or a launcher restart. Pinned home-screen shortcuts pointing to a disabled
  alias are removed by most launchers. This is OS behaviour, not fixable by an
  app.
- The recents/task label comes from `MaterialApp.title`, not from the alias.
- Native state (`getComponentEnabledSetting`) is the source of truth for the
  current identity; the switch survives restarts and app updates (component
  state is kept until uninstall or "clear data" in some OEM builds).

## iOS

**Mechanism.** `UIApplication.setAlternateIconName(_:completionHandler:)`
(iOS 10.3+). Alternate icons must be shipped in the bundle, either as asset
catalog app-icon sets with the build setting
`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES` (or
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`), or via `CFBundleAlternateIcons`
in `Info.plist`. IconShift maps variant id `dark` to alternate icon name `dark`.

- `supportsAlternateIcons` must be `true`; IconShift reports it.
- The system shows a non-suppressible alert ("You have changed the icon for …").
  Public API offers no way to avoid it. IconShift returns `unchanged` instead of
  re-applying the current icon so the alert is not shown needlessly.
- The call must be made while the app is in the foreground (`.active`).
- **Display name cannot be changed at runtime.** `CFBundleDisplayName` is
  read-only in a signed bundle. IconShift reports `none` and never fakes it.
- Native state (`alternateIconName`) is the source of truth.

## macOS

- `NSApplication.applicationIconImage` changes the **Dock icon of the running
  app**. It is reset when the app quits; Finder, Launchpad and the Dock icon of
  a non-running app keep the bundle icon.
- Changing the bundle icon on disk (`NSWorkspace.setIcon(_:forFile:)`, editing
  `Info.plist` / `CFBundleIconFile`) writes into the signed `.app` bundle,
  invalidates the code signature / notarization seal, and fails in the App
  Sandbox. IconShift **does not do this**.
- `CFBundleDisplayName` / `CFBundleName` cannot be changed at runtime for the
  same reason; the menu-bar app name is fixed. IconShift changes the **main
  window title** (`windowTitle` scope) instead and says so.

## Windows

- IconShift sends `WM_SETICON` (big and small) to the Flutter top-level window,
  changing the **title-bar icon, Alt-Tab icon and the taskbar button of the
  running window**. A taskbar entry that is *pinned* uses the shortcut's icon,
  and Start-menu/desktop shortcuts and the `.exe` icon never change.
- Rewriting executable resources (`UpdateResource`) on a running exe is unsafe,
  breaks Authenticode signatures and is impossible for MSIX packages
  (read-only install directory). Not done.
- Shortcut `.lnk` files belong to the installer and live in locations IconShift
  cannot know without hardcoding paths. Not modified.
- MSIX identity (display name, logo) is fixed by `AppxManifest.xml`.
- Display name changes the window title (`SetWindowTextW`).
- PNG decoding uses the Windows Imaging Component (system component).

## Linux

- On **X11**, `gtk_window_set_icon` changes the window/taskbar icon of the
  running window.
- On **Wayland**, there is no window-icon protocol; compositors take the icon
  from the installed `.desktop` file matched by the application id.
  `gtk_window_set_icon` is silently ignored, so IconShift reports icon
  `none` with an explanation rather than claiming success.
- `.desktop` files are owned by the package manager (deb/rpm), Flatpak or Snap
  and are read-only (system dirs, sandbox). Writing a user-level copy in
  `~/.local/share/applications` would create a second launcher, and is
  impossible inside Flatpak/Snap. Not done.
- Display name changes the GTK window title and, when the Flutter runner uses a
  `GtkHeaderBar`, the header bar title.

## Web

- Favicon: IconShift replaces the `<link rel="icon">` elements with one pointing
  at the Flutter asset URL, remembering the originals for `restoreDefault()`.
  If the page has no favicon link one is created.
- Title: `document.title`. Note that Flutter's `Title` widget (used by
  `MaterialApp(title: …)`) also writes `document.title` when it rebuilds; bind
  `MaterialApp.title` to IconShift state (see example app) to avoid it
  overwriting your change.
- **Installed PWA launcher icon / name cannot be changed at runtime.** The
  browser reads `manifest.json` at install time and re-checks it on its own
  schedule; the manifest is the same for every user, so it cannot express a
  per-user selection. IconShift does not touch the manifest.
- Favicon caching: each variant uses a distinct URL, so cache staleness does not
  apply. Service workers may serve cached assets offline, which is fine since
  assets are immutable per build.
- Safari historically updates dynamically changed favicons inconsistently.

## Persistence of the selection

IconShift stores the last *requested* selection (identity variant, icon variant,
custom display name) in native storage: `SharedPreferences` (Android),
`UserDefaults` (iOS/macOS), the per-user registry `HKCU\Software\IconShift\<exe name>`
(Windows), `$XDG_CONFIG_HOME/icon_shift/<program name>.ini` (Linux),
`localStorage` (web).

- Android / iOS: the OS persists the change itself. The saved selection is only
  used to report *requested vs. native* state. Nothing is re-applied.
- macOS / Windows / Linux / Web: changes are session-only, so
  `IconShift.initialize()` re-applies the saved selection (disable with
  `restoreSelection: false`).
