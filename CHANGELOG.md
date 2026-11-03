## Unreleased

Runtime (`icon_shift`):

* Icon appearances for the iOS 26 / macOS 26 home-screen modes:
  `IconAppearances(dark:, tinted:, clear:)` on `AppIdentity` and
  `IdentityOverride`, resolved with the icon they belong to
  (`ResolvedIdentity.appearances`, `iconFor(IconAppearanceMode)`).
* macOS, Windows, Linux and web show the dark artwork while the system is in
  dark mode and follow changes (`initialize(followSystemAppearance:)`,
  `refreshAppearance()`).
* Remote icons: `RemoteIcon` (JSON with dark/tinted/clear URLs and a bundled
  fallback `variant`), `IconShift.fetchRemoteIcon()` and
  `IconShift.setRemoteIcon()`. Desktop downloads and applies the image, web
  uses the URL as favicon, iOS/Android switch to the bundled variant.
  New `IconShiftErrorCode.downloadFailed`, `IconShiftOperation.setRemoteIcon`.
* Android display name: `setDisplayName()` / `setCustomIdentity()` switch
  the launcher label when a variant's alias has that name and the same
  icon (name-only variants). Other names go to the recent-apps label
  (`IdentityScope.taskSwitcher`) with a message listing the launcher names,
  instead of returning `unsupported`. The recent-apps label also follows the
  active alias right after a switch.
* `IconShift.displayNameListenable` for binding `MaterialApp.title`, which
  otherwise overwrites the Android recent-apps label and web title.

Build time (`icon_shift_cli`):

* `appearances: {dark, tinted, clear}` on identities; `clear` on
  `platforms.ios` / `platforms.macos`; `dark` on desktop/web overrides.
  iOS icon sets get dark/tinted; the generated Dart config carries all of
  them.
* Images may be `https://` URLs, and `remote.manifest` merges variants
  published by a server. Downloads are validated, cached in
  `remote.assets_dir`, and refreshed with `generate --refresh-remote`.
* iOS home-screen name: `generate` now writes `default.name` to
  `CFBundleDisplayName` and the `names:` translations to
  `<lang>.lproj/InfoPlist.strings`, registered in the Xcode project
  (previously the iOS name never followed icon_shift.yaml and translations
  were Android-only). Opt out with `ios.set_display_name: false`.
* Fix: `identity --apply` with a `display_name` did not change the Android
  launcher name, because the launcher shows the IconShift alias labels; it
  now updates the aliases that show the default name. `generate` warns when
  `application.display_name` and the launcher label differ.

## 0.2.0

Runtime (`icon_shift`):

* Identity profiles: `localizedNames`, `appearance`, `themeColor` on
  `AppIdentity`; `IdentityOverride.localizedNames`; locale-aware resolution.
* `renamedVariants` with automatic migration of the saved selection; saved
  selection is validated and repaired on `initialize()`.
* `getPlatformCapabilities()` with a typed identity property table
  (runtime / build-time only / reinstall / signing / data kept).
* `getApplicationInfo()` on all platforms (display name, application/bundle
  id, version, build, executable, installation type).
* `previewIdentity()`, `clearSavedSelection()`, `IconShiftThemeSync`.
* Web: runtime theme color.
* Errors and results carry operation, platform and a suggestion; new codes
  `buildRequired`, `missingAsset`, `configurationNotFound`,
  `invalidApplicationIdentifier`, `signingRestriction`.
* Android: retired aliases and launcher-entry recovery at startup.

Build time (`icon_shift_cli`, formerly `icon_shift_generator`):

* Commands: `doctor`, `validate`, `generate`, `preview`, `capabilities`,
  `identity --show/--apply/--reset`, `assets --check`, `rollback`.
* Build identity: Android applicationId/namespace (with source move)/label,
  Apple bundle ids and names, Windows executable and version metadata, Linux
  application id and titles, web manifest metadata, version; profiles.
* Backups for every write and conflict-aware rollback; path-traversal
  protection; diffs in dry runs.
* Icons: Android monochrome and explicit adaptive layers, localized labels,
  retired aliases; iOS dark/tinted appearances and optional primary icon;
  macOS AppIcon; Windows `.ico`; Linux hicolor icons and `.desktop`; web
  favicon, PWA and maskable icons.

## 0.1.0

* Initial release.
* Shared and per-platform identity configuration with variants and
  documented override resolution.
* Android (activity-aliases), iOS (alternate icons), macOS (Dock icon,
  window title), Windows (window/taskbar icon, window title), Linux (X11
  window icon, window/header bar title) and web (favicon, document title)
  implementations.
* Capability discovery, per-operation results, requested-vs-native state,
  persistence and re-application on session-only platforms.
* Configuration, asset and native-resource validation; diagnostics.
