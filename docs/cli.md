# icon_shift_cli

Build-time tooling. Pure Dart; no Flutter SDK, Xcode, Android SDK or Visual
Studio is needed to run it — only to build the app afterwards.

```bash
dart run icon_shift_cli <command> [options]          # as a dev_dependency
dart pub global activate icon_shift_cli && icon_shift_cli <command>
```

Global options: `--project <dir>` (default `.`), `--config <file>` (default
`icon_shift.yaml`, else the `icon_shift:` section of `pubspec.yaml`).

| Command | What it does | Writes files? |
| --- | --- | --- |
| `doctor` | Flutter project? plugin dependency? platforms present, config valid, Android markers and tooling filter, iOS build setting, resources up to date, `.gitignore` | no |
| `validate [--profile p]` | Config, images, build identity rules | no |
| `generate [--platform …] [-n] [--no-diff]` | Native icon/label resources and the Dart config | yes (backed up) |
| `preview [--variant v] [--profile p]` | How every variant resolves per platform; dry-run diff of the build identity | no |
| `capabilities [--platform p]` | The identity property table | no |
| `identity --show` | Identity currently in the native project files | no |
| `identity --apply [--profile p] [-n]` | Apply `application:` (+ profile) | yes (backed up) |
| `identity --reset [--force]` | Undo the most recent `--apply` | yes |
| `assets --check` | Source image checks with sizes | no |
| `rollback [--list] [--id x] [--force]` | Restore a backup | yes |

`generate --platform` accepts `android ios macos windows linux web dart`
(repeatable).

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success (or nothing to do) |
| 1 | Validation errors — nothing was written |
| 2 | Rollback conflicts — files edited since the backup were left alone |
| 64 | Usage error |
| 66 | No configuration found |

## Safety

* Validates everything first; any error means no file is written.
* Paths in the config must stay inside the project (no absolute paths, no
  `..`).
* Edits to template files use exact patterns with expected match counts.
* Only deletes files carrying its ownership marker.
* Backs up every file before writing; rollback detects later manual edits.
* Runs no shell commands and reads no signing material.

## Known issue: Dart 3.13.4 precompile crash

With Dart 3.13.4, `dart run icon_shift_cli` can crash in the compiler while
pub precompiles `package:image` (an SDK bug, also seen with plain
`dart test` in this repository). Run the script directly instead:

```bash
dart run path/to/icon_shift_cli/bin/icon_shift_cli.dart <command>
```
