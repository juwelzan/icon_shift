# Production readiness

## Summary

| Area | State |
| --- | --- |
| Runtime API | Complete, documented, unit-tested; integration-tested on Android, iOS, macOS (see PLATFORM_TEST_RESULTS.md). |
| Build-time CLI | Complete, unit- and fixture-tested; end-to-end checked by building a freshly created app after applying an identity. |
| Windows, Linux | Implemented, **not compiled or run** — not production-ready until verified on those hosts. |
| Web | DOM-tested in Chrome and release-built; no `flutter drive` run. |
| Docs | Complete set (README, docs/, capability, status, roadmap, limitations, test results). |
| Publishing | Blocked only by owner decisions below. |

## Owner decisions before publishing

These are not made on your behalf:

1. **License.** `LICENSE` is the template placeholder. Pick a license (and
   copy it to `cli/LICENSE`).
2. **Android package / namespace.** `com.example.icon_shift` must become your
   own reverse-DNS name: `pubspec.yaml`
   (`flutter.plugin.platforms.android.package`), `android/build.gradle.kts`
   (`group`, `namespace`), the `package` line of every Kotlin file, and move
   `android/src/{main,test}/kotlin/com/example/icon_shift/`.
3. **Repository / homepage** in `pubspec.yaml`, `cli/pubspec.yaml`, and
   `homepage`/`author` in `ios/icon_shift.podspec`, `macos/icon_shift.podspec`.
4. **Verify Windows and Linux** (`cd example && flutter build windows`,
   `flutter build linux`, run the GTests and the integration test).

## Checklist

| Check | Command | Result |
| --- | --- | --- |
| Formatting | `dart format --set-exit-if-changed lib test cli example/lib` | see PLATFORM_TEST_RESULTS.md |
| Static analysis (plugin + example) | `flutter analyze` | no issues |
| Static analysis (CLI) | `cd cli && dart analyze` | no issues |
| Dart unit tests | `flutter test` | all pass |
| Web DOM tests | `flutter test --platform chrome test/web` | all pass |
| CLI tests | `cd cli && dart run test/generator_test.dart && dart run test/identity_test.dart` | all pass |
| Kotlin unit tests | `cd example/android && ./gradlew :icon_shift:testDebugUnitTest` | all pass |
| Integration tests | `cd example && flutter test integration_test -d <device>` | per platform in PLATFORM_TEST_RESULTS.md |
| Plugin registration | `pubspec.yaml` `flutter.plugin.platforms` (6 platforms) | checked |
| Publish dry run | `flutter pub publish --dry-run` / `cd cli && dart pub publish --dry-run` | see PLATFORM_TEST_RESULTS.md |

## Publishing

```bash
# 1. Plugin (generator/ test sync file excluded via .pubignore)
flutter pub publish --dry-run
flutter pub publish

# 2. CLI
cd cli
dart pub publish --dry-run
dart pub publish

# 3. Optionally switch the example's icon_shift_cli dependency to a version.
```

## Security review notes

* No runtime permissions requested; no network access at runtime (web only
  fetches its own `version.json` from the same origin).
* Diagnostics contain platform facts and configured ids/names only.
* The CLI rejects absolute and `..` paths from configuration, runs no shell
  commands, never reads or writes signing material, and only deletes files
  it marked as generated. Backups stay inside the project
  (`.icon_shift/`), which should be git-ignored.
* Native code validates arguments (keys, bytes) and never writes outside its
  own preferences/registry key/config file.
