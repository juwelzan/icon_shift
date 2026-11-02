# icon_shift example

Demonstrates IconShift on every platform:

* one shared icon and name, overridden for Android (icon + label) and web
  (favicon), with German translations;
* variants `dark` (icon + name + appearance + theme color), `blue` (icon
  only) and `pro` (name only);
* switching identities, icon only, arbitrary names, combined updates,
  restoring the default;
* live capabilities, the identity property table, application info from
  the OS, previews, validation and diagnostics;
* a build-time `staging` profile.

Everything native is generated from [`icon_shift.yaml`](icon_shift.yaml):

```bash
dart run ../cli/bin/icon_shift_cli.dart doctor
dart run ../cli/bin/icon_shift_cli.dart generate
flutter run
```

On-device tests:

```bash
flutter test integration_test -d <device-id>
```

Build-time profile (creates a separate "staging" app; undo with `--reset`):

```bash
dart run ../cli/bin/icon_shift_cli.dart identity --apply --profile staging --dry-run
```
