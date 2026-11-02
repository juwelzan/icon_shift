# Implementation roadmap

Status legend: ✅ done · 🟡 done, not verified on that platform · ⏭ deferred
(reason given) · ⛔ not possible (OS restriction).

## 0.1 → 0.2 (this release)

| Area | Item | Status |
| --- | --- | --- |
| Audit | Placeholders, hardcoded successes, TODOs, dependency check | ✅ none found besides publisher TODOs |
| Runtime | Profiles with localized names, appearance, theme color | ✅ |
| Runtime | Renamed/removed variant migration, selection repair | ✅ |
| Runtime | `getPlatformCapabilities()` + typed property table | ✅ |
| Runtime | `getApplicationInfo()` | ✅ Android, iOS, macOS, web · 🟡 Windows, Linux |
| Runtime | `previewIdentity()`, `clearSavedSelection()` | ✅ |
| Runtime | Structured errors (operation, platform, suggestion, new codes) | ✅ |
| Runtime | Web theme color | ✅ |
| Runtime | `IconShiftThemeSync` (opt-in) | ✅ |
| Android | Retired aliases, launcher recovery at startup | ✅ |
| CLI | Rename to `icon_shift_cli`, subcommands, exit codes | ✅ |
| CLI | Build identity for all platforms + profiles | ✅ (files edited; app builds verified per PLATFORM_TEST_RESULTS.md) |
| CLI | Backups, conflict-aware rollback, path checks | ✅ |
| CLI | Monochrome/adaptive layers, localized labels, iOS appearances, macOS/Windows/Linux/web icons | ✅ |
| Docs | Full documentation set | ✅ |

## Next

| Item | Why it is not in 0.2 |
| --- | --- |
| Compile and run Windows and Linux on real hosts / CI (`windows-latest`, `ubuntu-latest`) | No Windows or Linux machine was available; code is complete but unverified. Highest priority. |
| GitHub Actions workflow running all test suites on all hosts | Needs the repository's CI decision. |
| iOS/macOS display-name localization at build time (`InfoPlist.strings`) | Requires adding variant groups to the Xcode project; editing `project.pbxproj` structure safely needs a real pbxproj parser. |
| Runtime update of user-owned Linux `.desktop` overrides (`~/.local/share/applications`) | Feasible on native installs (XDG lets a user file shadow the system one), impossible in Flatpak/Snap. Opt-in design decided; not built because it cannot be verified here. |
| Windows: update the current user's own Start-menu/desktop shortcuts | Feasible for unpackaged apps via `IShellLinkW`; not for MSIX; risk of fighting the installer. Deferred until verifiable. |
| Android productFlavors / Xcode schemes generation | Build profiles cover switching identities; flavors are invasive to generate safely. |
| macOS `PRODUCT_NAME` (executable/.app rename) | Affects build paths and plugins' expectations; left as a manual change. |

## Will not do (OS restrictions)

| Request | Why |
| --- | --- |
| Change an installed app's Android package / iOS bundle id / MSIX identity at runtime | ⛔ No OS API; identity is fixed by installation and signing. |
| Change the iOS display name at runtime | ⛔ `CFBundleDisplayName` is part of the signed bundle. |
| Rewrite a signed macOS bundle or a Windows executable's resources at runtime | ⛔ Breaks code signatures/notarization; impossible for MSIX and in sandboxes. |
| Change an installed PWA's icon/name per user at runtime | ⛔ Browsers read the manifest themselves; it is not per user. |
| Suppress the iOS alternate-icon alert | ⛔ No public API. |
| Switch launcher icons automatically with the Flutter theme | ⛔ Not an OS feature; `IconShiftThemeSync` does it explicitly where allowed. |
