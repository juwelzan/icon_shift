# IconShift — project context

Living handoff document: what exists, why, and what is left. Read this
first when resuming work.

## Goal

A Flutter plugin to switch app icon and display name at runtime across
Android, iOS, macOS, Windows, Linux and web, reporting honestly what each OS
allows. Full brief: see the original task; key docs:

* `docs/ARCHITECTURE.md` — layering, API, resolution rules, channel protocol.
* `docs/PLATFORM_CAPABILITIES.md` — what each OS supports and why.

## Key decisions

| Decision | Rationale |
| -------- | --------- |
| Single plugin package, internal platform interface (not federated) | All implementations first-party; federation adds 7 pubspecs for no user benefit. Interface extends `PlatformInterface`, so it can be split later. |
| Generator is a separate package `generator/` (`icon_shift_generator`) | Keeps `image`/`yaml`/`args` out of every app's dependency graph. |
| Mutations return `IconShiftResult` (`@useResult`), exceptions only for programmer errors | Partial support is normal; one honest result per operation. |
| Platform overrides inside each `AppIdentity` as `IdentityOverride` | One shape for default and variants; type system prevents nested overrides. |
| Variant id == Android alias meta-data value == iOS alternate icon name | No mapping tables; ids restricted to `[a-z][a-z0-9_]*`. |
| Desktop/web icons sent as asset bytes / asset URL from Dart | Native code never needs to locate Flutter assets on disk. |
| Desktop name = window title, web = document.title | Bundle/exe/.desktop names cannot be changed safely; window title is the honest equivalent and is labelled `windowTitle` scope. |
| Persistence implemented natively (no shared_preferences) | Avoids a dependency chain; each OS has a trivial store. |
| Android package name still `com.example.icon_shift` | Publisher must choose their own namespace before publishing. |

## Phase status

| Phase | Status |
| ----- | ------ |
| 1 Audit | Done. Repo was an untouched `flutter create --template=plugin` scaffold. |
| 2 Platform research | Done → `docs/PLATFORM_CAPABILITIES.md`. |
| 3 API/architecture | Done → `docs/ARCHITECTURE.md`. |
| 4 Config & resolution | Done (`lib/src/config`, `lib/src/validation`). |
| 5 Dart core & platform interface | Done (`lib/src/engine.dart`, `lib/src/platform`). 59 Dart tests pass. |
| 6 Android | In progress. |
| 7 iOS | Not started. |
| 8 macOS | Not started. |
| 9 Windows / Linux | Not started. |
| 10 Web | Implemented (`lib/icon_shift_web.dart`), browser tests pending. |
| 11 Generator | Not started. |
| 12 Example | Not started. |
| 13 Docs / release | Not started. |

## Environment (development machine)

macOS host, Xcode 27.2, Flutter 3.49 / Dart 3.13, Android emulator API 29,
iOS 26.5/27 simulators, Chrome. **No Windows or Linux host**: those
implementations cannot be compiled or run here.
