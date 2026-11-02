# Examples

The [example app](../example) runs on every platform and demonstrates each
item below with real platform behaviour (unsupported operations show their
`unsupported` result instead of pretending).

## 1. Change the app icon

```dart
final result = await IconShift.setIcon('blue');
if (result.icon.status == OperationStatus.applied) { … }
```

## 2. Change the display name where supported

```dart
final caps = await IconShift.getCapabilities();
if (caps.displayName.acceptsArbitraryValues) {
  await IconShift.setDisplayName('Project X');   // window/document title
} else if (caps.displayName.isSupported) {
  await IconShift.setIdentity('business');       // Android: preconfigured label
}
```

## 3. Switch identity profiles

```dart
await IconShift.setIdentity('dark');      // icon + name + theme color
final preview = await IconShift.previewIdentity('business');
print(preview.current);                    // what would change here
```

## 4. Restore the default identity

```dart
await IconShift.restoreDefault();
```

## 5. Inspect platform capabilities

```dart
final caps = await IconShift.getPlatformCapabilities();
print(caps.runtimeChangeable);   // e.g. [displayName, launcherIcon, adaptiveIcon]
print(caps.buildTimeOnly);       // e.g. [themedIcon, applicationId, …]
print(caps.properties[IdentityProperty.applicationId]); // reinstall, data not kept
final info = await IconShift.getApplicationInfo();
print('${info.applicationId} ${info.version}+${info.buildNumber}');
```

## 6. Validate the configuration

```dart
final validation = await IconShift.validateConfiguration();
for (final issue in validation.issues) print(issue);
```

```bash
dart run icon_shift_cli validate
dart run icon_shift_cli assets --check
```

## 7. Generate build-time identity variants

The example's [`icon_shift.yaml`](../example/icon_shift.yaml) defines a
`staging` build profile:

```bash
cd example
dart run ../cli/bin/icon_shift_cli.dart preview --profile staging
dart run ../cli/bin/icon_shift_cli.dart identity --apply --profile staging --dry-run
dart run ../cli/bin/icon_shift_cli.dart identity --apply --profile staging
flutter build apk          # a separate "staging" app next to the normal one
dart run ../cli/bin/icon_shift_cli.dart identity --reset
```

## Theme-aware identity

```dart
final sync = IconShiftThemeSync(onResult: (r) => debugPrint('$r'))..start();
```
