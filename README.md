# IconShift

Application identity management for Flutter:

* **Runtime** (`icon_shift` plugin): switch the app icon and display name
  between preconfigured identity profiles on Android, iOS, macOS, Windows,
  Linux and web — within exactly what each OS allows, reported per
  operation.
* **Build time** (`icon_shift_cli`): generate native icon resources and set
  application ids, bundle ids, names, executable metadata and PWA metadata
  in the native project, with preview, backups and rollback.

IconShift never claims an operation worked when the OS cannot do it, and it
never modifies signed bundles, executables, installer shortcuts or an
installed app's package identity.

| Platform | Runtime icon | Runtime name | Build time |
| --- | --- | --- | --- |
| Android | launcher icon (preconfigured) | launcher label (linked to icon) | applicationId, namespace, label, icons (adaptive, monochrome) |
| iOS | home-screen icon (preconfigured, system alert) | — | bundle id, display name, alternate/primary icons (dark, tinted) |
| macOS | Dock icon while running | window title | bundle id, bundle name, AppIcon |
| Windows | title bar / taskbar icon while running | window title | executable name, version resource, window title, `.ico` |
| Linux | window icon (X11) while running | window / header bar title | application id, binary name, titles, hicolor icons, `.desktop` |
| Web | favicon, theme color | `document.title` | manifest name/short name/colors/icons, `<title>` |

Details: [PLATFORM_CAPABILITIES.md](PLATFORM_CAPABILITIES.md) ·
verification: [PLATFORM_TEST_RESULTS.md](PLATFORM_TEST_RESULTS.md) ·
limits: [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

## Quick start

```yaml
dependencies:
  icon_shift: ^0.2.0
dev_dependencies:
  icon_shift_cli: ^0.2.0
flutter:
  assets:
    - assets/icons/
```

```yaml
# icon_shift.yaml
default:
  name: Notes
  icon: assets/icons/app.png          # one icon for every platform …
  platforms:
    android: { icon: assets/icons/android.png }   # … with optional overrides
variants:
  dark:  { name: Notes Dark, icon: assets/icons/dark.png, appearance: dark }
  blue:  { icon: assets/icons/blue.png }
  work:  { name: Notes for Work }
dart:
  output: lib/icon_shift_config.g.dart
```

```bash
dart run icon_shift_cli doctor      # what the project still needs
dart run icon_shift_cli generate    # Android aliases/mipmaps, iOS icon sets, Dart config
```

```dart
import 'package:icon_shift/icon_shift.dart';
import 'icon_shift_config.g.dart';

await IconShift.initialize(iconShiftConfig);

final result = await IconShift.setIdentity('dark');
if (!result.isComplete) debugPrint('$result'); // e.g. iOS: name buildRequired
await IconShift.restoreDefault();
```

Android needs a one-time manifest tweak and iOS one build setting — see
[docs/installation.md](docs/installation.md).

## Runtime API

```dart
await IconShift.initialize(config, {restoreSelection, locale});
await IconShift.setIdentity(id);                 // profile: icon + name (+ web theme color)
await IconShift.setIcon(id);                     // icon only
await IconShift.setDisplayName(name);            // arbitrary title where allowed
await IconShift.setCustomIdentity(iconVariant: id, displayName: name);
await IconShift.restoreDefault();
await IconShift.clearSavedSelection();

await IconShift.getCurrentIdentity();      // requested vs. OS-reported
await IconShift.getVariants();             // resolved, with availability
await IconShift.previewIdentity(id);       // what would happen, without applying
await IconShift.getCapabilities();         // live runtime capabilities
await IconShift.getPlatformCapabilities(); // + every identity property: runtime/build-time/reinstall
await IconShift.getApplicationInfo();      // display name, app/bundle id, version, install type
await IconShift.validateConfiguration();
await IconShift.getDiagnostics();
IconShiftThemeSync()..start();             // opt-in: follow system brightness
```

Mutations return `IconShiftResult` with an outcome per operation (`applied`,
`unchanged`, `pending`, `notRequested`, `unsupported`, `failed`, `skipped`),
an error code, a message and a suggestion. Exceptions are reserved for
programming errors. Full guide: [docs/runtime_identity.md](docs/runtime_identity.md).

## Build-time identity

```yaml
application:
  display_name: Acme Notes
  version: 2.1.0+7
  android: { application_id: com.acme.notes }
  ios:     { bundle_id: com.acme.notes }
build_profiles:
  staging:
    android: { application_id: com.acme.notes.staging }
```

```bash
dart run icon_shift_cli identity --apply --profile staging --dry-run
dart run icon_shift_cli identity --apply --profile staging
dart run icon_shift_cli identity --reset
```

A new application/bundle id is a **new app** for the OS; signing and
provisioning stay yours. Guide: [docs/build_time_identity.md](docs/build_time_identity.md).

## Documentation

| | |
| --- | --- |
| [installation](docs/installation.md) | setup per platform |
| [runtime_identity](docs/runtime_identity.md) | configuration, API, persistence, theme sync |
| [build_time_identity](docs/build_time_identity.md) | ids, names, profiles, backups, migration |
| [icon_configuration](docs/icon_configuration.md) | sizes, adaptive/monochrome, dark/tinted, outputs |
| [platform_support](docs/platform_support.md) | per-platform behaviour |
| [cli](docs/cli.md) | commands and exit codes |
| [troubleshooting](docs/troubleshooting.md) | symptoms → fixes |
| [examples](docs/examples.md) | the example app's scenarios |
| [architecture](docs/architecture.md) | design and channel protocol |

## Example app

[`example/`](example) demonstrates shared and per-platform icons and names,
localized names, profiles, icon-only and name-only variants, restore,
capabilities, application info, previews, validation, diagnostics and a
build profile. Its native resources come from
[`example/icon_shift.yaml`](example/icon_shift.yaml).

## Publishing

See [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) for the remaining
publisher decisions (license, Android package name, repository URL) and the
exact commands.
