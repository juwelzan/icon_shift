# Contributing

## Layout

`lib/` runtime plugin · `android/ ios/ macos/ windows/ linux/` native code ·
`cli/` build-time tool · `example/` demo app · `docs/`. See
[docs/architecture.md](docs/architecture.md).

## Ground rules

* Never report success for something the OS did not do. Read native state
  back where possible; return `unsupported` with a reason otherwise.
* No runtime modification of signed bundles, executables, installer
  shortcuts or package-manager files.
* Keep runtime (plugin) and build-time (CLI) separate; the CLI must not
  depend on Flutter.
* Update `PLATFORM_CAPABILITIES.md`, both property tables
  (`cli/lib/src/property_table.dart`, `lib/src/models/identity_properties.dart`)
  and `PLATFORM_TEST_RESULTS.md` together.
* Only claim a platform verified after building and running it.

## Checks

```bash
# Plugin
dart format lib test && flutter analyze && flutter test
flutter test --platform chrome test/web

# CLI (run test files directly; see docs/cli.md for the Dart 3.13.4 issue)
cd cli && dart format . && dart analyze
dart run test/generator_test.dart && dart run test/identity_test.dart

# Android native unit tests (from example/android)
./gradlew :icon_shift:testDebugUnitTest

# On-device integration tests
cd example && flutter test integration_test -d <device>
```

Windows and Linux GTests build with the example
(`flutter build windows|linux`) and run from `build/…/plugins/icon_shift/`.

## Regenerating the plugin's property table

`lib/src/models/identity_properties.dart` is generated from
`cli/lib/src/property_table.dart`; `test/property_table_sync_test.dart` fails
if they differ.
