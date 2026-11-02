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
