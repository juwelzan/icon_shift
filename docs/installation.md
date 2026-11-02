# Installation

## 1. Add the packages

```yaml
dependencies:
  icon_shift: ^0.2.0

dev_dependencies:
  icon_shift_cli: ^0.2.0   # optional: generates native resources, build identity
```

```bash
flutter pub get
```

Requirements: Flutter 3.32+ / Dart 3.8+. Android minSdk 24, iOS 15, macOS 12
(Swift Package Manager) / 10.15 (CocoaPods).

## 2. Declare icon images as assets

```yaml
flutter:
  assets:
    - assets/icons/
```

Use square PNGs: 1024 px covers every platform (iOS needs 1024, Android at
least 192). SVG works only as a Linux/web override.

## 3. Describe your identities

Either in Dart, or — recommended when you also want native resources — in
`icon_shift.yaml`, from which the CLI generates the Dart config:

```yaml
default:
  name: My App
  icon: assets/icons/app.png
variants:
  dark: { name: My App Dark, icon: assets/icons/dark.png, appearance: dark }
dart:
  output: lib/icon_shift_config.g.dart
```

```bash
dart run icon_shift_cli generate --dry-run   # look first
dart run icon_shift_cli generate
```

## 4. One-time native setup

Only Android and iOS need native setup; macOS, Windows, Linux and web apply
the assets at runtime.

**Android** — in `android/app/src/main/AndroidManifest.xml`:

1. In `MainActivity`'s MAIN/LAUNCHER intent-filter add
   `<data android:scheme="icon-shift-tooling"/>` (keeps `flutter run`
   working and the launcher showing only the aliases).
2. Inside `<application>` add the markers the CLI fills:
   ```xml
   <!-- icon_shift:aliases:start -->
   <!-- icon_shift:aliases:end -->
   ```

**iOS** — add to `ios/Flutter/Debug.xcconfig` and `Release.xcconfig`:

```
ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES
```

`dart run icon_shift_cli doctor` checks all of this.

## 5. Initialize

```dart
import 'package:icon_shift/icon_shift.dart';
import 'icon_shift_config.g.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await IconShift.initialize(iconShiftConfig);
  runApp(const MyApp());
}
```

Rebuild the app fully after adding the plugin (hot restart does not register
native plugins).
