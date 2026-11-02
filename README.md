# IconShift

Switch your Flutter app's **icon and display name at runtime** on Android,
iOS, macOS, Windows, Linux and web, from one configuration with shared
defaults and per-platform overrides.

IconShift reports what each OS actually allows instead of pretending.
Changing "the app icon" means very different things on an Android launcher,
in the macOS Dock and in a browser tab, and some things (an iOS app name, an
installed PWA icon) cannot change at runtime at all. Every call returns a
result that says what happened to the icon and to the name.

| Platform | Icon                                        | Display name                        |
| -------- | ------------------------------------------- | ----------------------------------- |
| Android  | Launcher icon (preconfigured variants)      | Launcher label (linked to the icon) |
| iOS      | Home-screen icon (preconfigured alternates) | Not possible                        |
| macOS    | Dock icon while running (any PNG)           | Window title                        |
| Windows  | Title bar / taskbar button while running    | Window title                        |
| Linux    | Window icon on X11 (not Wayland)            | Window / header bar title           |
| Web      | Favicon                                     | `document.title`                    |

Details and the reasons behind each limitation are in
[docs/PLATFORM_CAPABILITIES.md](docs/PLATFORM_CAPABILITIES.md).

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Switching identities](#switching-identities)
- [Platform setup](#platform-setup)
- [Resource generator](#resource-generator)
- [Capabilities, state and validation](#capabilities-state-and-validation)
- [Error handling](#error-handling)
- [API reference](#api-reference)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)
- [Example app](#example-app)
- [Verification](#verification)
- [Publishing to pub.dev](#publishing-to-pubdev)

## Installation

```yaml
dependencies:
  icon_shift: ^0.1.0

dev_dependencies:
  icon_shift_generator: ^0.1.0   # optional, generates Android/iOS resources
```

Declare your icon images as Flutter assets:

```yaml
flutter:
  assets:
    - assets/icons/
```

## Quick start

```dart
import 'package:icon_shift/icon_shift.dart';

const config = IconShiftConfig(
  defaultIdentity: AppIdentity(
    name: 'My App',
    icon: AppIcon.asset('assets/icons/app.png'),
  ),
  variants: {
    'dark': AppIdentity(name: 'My App Dark', icon: AppIcon.asset('assets/icons/dark.png')),
    'blue': AppIdentity(icon: AppIcon.asset('assets/icons/blue.png')),
  },
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await IconShift.initialize(config);
  runApp(const MyApp());
}

// Later:
final result = await IconShift.setIdentity('dark');
if (!result.isComplete) debugPrint('$result');
```

On Android and iOS the variants must also exist as native resources. Run the
[generator](#resource-generator) or follow [Platform setup](#platform-setup).

## Configuration

### One icon and name for every platform

```dart
const config = IconShiftConfig(
  defaultIdentity: AppIdentity(
    name: 'My App',
    icon: AppIcon.asset('assets/icons/app.png'),
  ),
);
```

### Platform-specific overrides

Every identity, the default and each variant, can override its name and/or
icon per platform with `IdentityOverride`. Unset fields inherit.

```dart
const config = IconShiftConfig(
  defaultIdentity: AppIdentity(
    name: 'My App',
    icon: AppIcon.asset('assets/icons/common.png'),
    platforms: {
      // Android gets its own icon but keeps the shared name.
      IconShiftPlatform.android: IdentityOverride(icon: AppIcon.asset('assets/icons/android.png')),
      // The web gets its own name and a small favicon.
      IconShiftPlatform.web: IdentityOverride(
        name: 'My Web App',
        icon: AppIcon.asset('assets/icons/favicon.png'),
      ),
    },
  ),
);
```

### Variants

```dart
variants: {
  'dark': AppIdentity(
    name: 'My App Dark',
    icon: AppIcon.asset('assets/icons/dark.png'),
    platforms: {
      IconShiftPlatform.android: IdentityOverride(icon: AppIcon.asset('assets/icons/dark_android.png')),
    },
  ),
  'blue': AppIdentity(icon: AppIcon.asset('assets/icons/blue.png')), // icon only
  'pro': AppIdentity(name: 'My App Pro'),                            // name only
},
```

Variant ids match `[a-z][a-z0-9_]*`. They double as Android resource names and
iOS alternate icon names. `default` is reserved for `defaultIdentity`.

### Resolution rules

For variant *v* on platform *p*, `name` and `icon` are resolved
independently. The first value that is set wins:

1. `variants[v].platforms[p]`
2. `variants[v]`
3. `defaultIdentity.platforms[p]`
4. `defaultIdentity`

A variant without its own icon *uses the default icon*: switching to it
restores the app's shipped icon. The same goes for names.
`config.resolve('dark', IconShiftPlatform.android)` shows the result.

## Switching identities

```dart
await IconShift.setIdentity('dark');          // icon + name of a variant
await IconShift.setIcon('blue');              // icon only
await IconShift.setDisplayName('My App Pro'); // arbitrary name, where allowed
await IconShift.setCustomIdentity(iconVariant: 'blue', displayName: 'Blue Edition');
await IconShift.restoreDefault();
```

All of these return an `IconShiftResult`. Ignoring it triggers a lint warning
(`@useResult`).

- The arguments are validated before anything changes.
- The icon is applied first. If it **fails**, the name is `skipped`, so the
  app never shows an icon and a name from different variants.
- **On Android** an activity-alias carries one icon and one label, so
  `setIcon` also switches the label. The result's `displayName` says so.
- **Persistence:** the last selection is saved. On macOS, Windows, Linux and
  web, where changes end with the process, `initialize()` re-applies it
  (`restoreSelection: false` disables this). On Android and iOS the OS keeps
  the change itself, and nothing is re-applied.

## Platform setup

### Android

Each variant is an `<activity-alias>` of `MainActivity` with its own icon,
label and the meta-data `icon_shift.variant`. The generator writes the aliases
between two markers that you add once inside `<application>`:

```xml
<activity android:name=".MainActivity" android:exported="true" ...>
    <!-- Lets `flutter run` find this activity; the <data> element keeps it
         out of the launcher, which shows the aliases instead. -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
        <data android:scheme="icon-shift-tooling"/>
    </intent-filter>
</activity>
<!-- icon_shift:aliases:start -->
<!-- icon_shift:aliases:end -->
```

Replace the original MAIN/LAUNCHER filter with the one above. If you keep the
plain filter, the launcher shows a second entry, and IconShift reports
`duplicate_launcher`. If you remove it entirely, `flutter run` cannot find the
launch activity.

An alias written by hand looks like this:

```xml
<activity-alias
    android:name=".IconShiftAlias_dark"
    android:targetActivity=".MainActivity"
    android:enabled="false"
    android:exported="true"
    android:icon="@mipmap/ic_icon_shift_dark"
    android:label="@string/icon_shift_label_dark">
    <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
    </intent-filter>
    <meta-data android:name="icon_shift.variant" android:value="dark" />
</activity-alias>
```

You need one alias per variant, plus one for `default` with
`android:enabled="true"`. Only the default alias may be enabled in the manifest.

### iOS

Add one app icon set per variant that has its own icon, named exactly like
the variant (`dark.appiconset`), and make Xcode bundle them:

```
// ios/Flutter/Debug.xcconfig and ios/Flutter/Release.xcconfig
ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES
```

You can instead set *Include All App Icon Assets* in the Runner target's build
settings. iOS shows a system alert after each change, and that cannot be
suppressed.

### macOS, Windows, Linux, web

No setup. The configured PNG assets are applied at runtime.

## Resource generator

`icon_shift_generator` turns one YAML file into the native resources
described above, and optionally into the Dart config, so the two can never
drift apart.

```yaml
# icon_shift.yaml (or an `icon_shift:` section in pubspec.yaml)
default:
  name: My App
  icon: assets/icons/app.png
  platforms:
    android: { icon: assets/icons/android.png }
variants:
  dark: { name: My App Dark, icon: assets/icons/dark.png }
  pro:  { name: My App Pro }

android:                      # all optional
  res_dir: android/app/src/main/res
  manifest: android/app/src/main/AndroidManifest.xml
  target_activity: .MainActivity
  adaptive_background: "#FFFFFF"   # also generate adaptive icons
ios:
  asset_catalog: ios/Runner/Assets.xcassets
  background_color: "#FFFFFF"      # used to flatten transparency
dart:
  output: lib/icon_shift_config.g.dart
```

```bash
dart run icon_shift_generator --dry-run   # show what would change
dart run icon_shift_generator             # write
dart run icon_shift_generator --check     # validate only (CI)
```

What it does:

- **Android:** writes `mipmap-*/ic_icon_shift_<id>.png` for mdpi to xxxhdpi
  (plus adaptive icons if `adaptive_background` is set), label strings in
  `values/icon_shift.xml`, and the aliases between the manifest markers. If
  the markers are missing, it leaves the manifest untouched and writes the
  snippet to `build/icon_shift/`.
- **iOS:** writes `<id>.appiconset` (1024 px, single size) for each variant
  with its own icon. It flattens transparency, which App Store icons may not
  contain. It never touches the primary `AppIcon` set.
- **Dart:** writes `const iconShiftConfig`.

Safety rules:

- It validates everything first, and any error means **no file is written**.
- Sources must be square PNG/JPEG. It never upscales: Android needs at least
  192 px (512 px or more recommended) and iOS needs 1024 px. SVG is rejected
  with a message, because it cannot be rasterized reliably without heavy
  dependencies; export a PNG instead.
- It only writes files it owns (`ic_icon_shift_*`, `icon_shift.xml`,
  appiconsets marked `author: icon_shift_generator`, the generated Dart
  file, the region between the markers), refuses to overwrite anything else,
  and removes its own files for variants you deleted.
- Your activity, `ic_launcher` and `AppIcon` are never modified. It warns if
  `MainActivity` needs the tooling intent-filter change described above.

You can skip the generator entirely. Everything it produces can be written by
hand.

## Capabilities, state and validation

```dart
final caps = await IconShift.getCapabilities();
caps.canChangeIcon;                      // bool
caps.icon.scope;                         // launcher | runningApp | windowTitle | browserTab | none
caps.icon.persistsNatively;              // survives restart without IconShift
caps.icon.requiresPreconfiguredResources;
caps.displayName.acceptsArbitraryValues; // setDisplayName('anything') works
caps.iconAndNameLinked;                  // Android
caps.icon.limitation;                    // human-readable caveat

final state = await IconShift.getCurrentIdentity();
state.requestedIconVariant;  // what the app asked for (persisted)
state.nativeIconVariant;     // what the OS reports now
state.isIconInSync;

final variants = await IconShift.getVariants(); // for a picker UI
variants.first.previewIcon;  // asset for in-app previews
variants.first.isAvailable;  // native resource present?

final validation = await IconShift.validateConfiguration();
for (final issue in validation.issues) print(issue);

print((await IconShift.getDiagnostics()).toReport());
```

`validateConfiguration()` checks variant ids, names, icon formats, that every
icon asset is bundled, and the native side. On Android it reports missing,
duplicate or unconfigured aliases, label mismatches, duplicate launcher
entries and no enabled alias. On iOS it reports missing alternate icons and
`supportsAlternateIcons`. In debug builds, `initialize()` prints its warnings.

Previews are your own assets. On Android and iOS the launcher shows the native
resource, which only looks the same if both come from the same source (the
generator ensures this).

## Error handling

| Situation                                              | What you get |
| ------------------------------------------------------ | ------------ |
| Not initialized, unknown variant id, invalid name      | throws `NotInitializedException`, `VariantNotFoundException`, `InvalidArgumentException` |
| Config errors at `initialize()`                        | throws `InvalidConfigurationException` (with `.validation`) |
| OS cannot do it                                        | `OperationStatus.unsupported` + message |
| Native resource missing / OS error / app in background | `OperationStatus.failed` + `IconShiftErrorCode` (`missingNativeResource`, `nativeOperationFailed`, `permissionDenied`, `appNotActive`) |
| Name not applied because the icon failed               | `OperationStatus.skipped` |

```dart
final result = await IconShift.setIdentity('dark');
result.isComplete;   // everything requested is in effect
result.isPartial;    // something changed, but not everything
result.hasFailures;  // failed or skipped (unsupported is not a failure)
result.throwIfFailed(); // exception style: throws IdentityUpdateException
```

## API reference

| Member | Description |
| ------ | ----------- |
| `initialize(config, {restoreSelection})` | Validate, read capabilities, re-apply the saved selection where needed. |
| `setIdentity(id)` | Icon and name of a variant. |
| `setIcon(id)` | Icon only (Android: also the linked label). |
| `setDisplayName(name)` | Arbitrary name (desktop window title, web document title). |
| `setCustomIdentity({iconVariant, displayName})` | Both in one validated call. |
| `restoreDefault()` | Shipped icon and name; clears the saved selection. |
| `getCurrentIdentity()` | `IconShiftState`: requested and native values. |
| `getCapabilities()` | `IconShiftCapabilities` |
| `getVariants()` | `List<IdentityVariant>` resolved for this platform. |
| `validateConfiguration()` | `IconShiftValidationResult` |
| `getDiagnostics()` | `IconShiftDiagnostics` (`toReport()`) |
| `IconShiftConfig.resolve(id, platform)` | The effective name/icon (pure). |

Platform implementers and tests can use
`package:icon_shift/icon_shift_platform_interface.dart`
(`IconShiftPlatformInterface`, `IconShiftEngine`).

## Limitations

- **iOS:** the app name cannot change, and a system alert follows each icon change.
- **Android:** only preconfigured icon+label pairs. Launchers may cache icons
  for a few seconds. Pinned shortcuts to a disabled alias are removed by most
  launchers. The recents title comes from `MaterialApp.title`.
- **macOS / Windows / Linux:** only the running app's Dock/taskbar/window icon
  and window title change. Bundle, `.exe`, shortcut, Start-menu and
  `.desktop` launchers are never modified (that would break code signatures,
  MSIX packages or package-manager ownership).
- **Linux Wayland:** no window icon can be set by apps; reported as unsupported.
- **Web:** only the tab favicon and title. The installed PWA icon and name come
  from `manifest.json`. `MaterialApp.title` also writes `document.title`, so
  bind it to IconShift's state (see the example).

## Troubleshooting

| Problem | Fix |
| ------- | --- |
| `flutter run`: "package identifier or launch activity not found" | `MainActivity` lost its MAIN/LAUNCHER filter. Add the tooling filter shown in [Android setup](#android). |
| Two launcher icons on Android | `duplicate_launcher` or `multiple_aliases_enabled` in `validateConfiguration()`. Add `<data android:scheme="icon-shift-tooling"/>` to MainActivity's filter, and set `android:enabled="false"` on every alias except `default`. |
| Android: `missing_resource` for a variant | No alias with `icon_shift.variant="<id>"`. Re-run the generator. |
| iOS: `missing_alternate_icon` | The app icon set isn't bundled. Set `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES` and rebuild. |
| iOS: `appNotActive` | Call while the app is in the foreground. |
| Web title reverts | `MaterialApp(title:)` rebuilt. Set it from `getCurrentIdentity().nativeDisplayName`. |
| `MissingPluginException` / "native plugin is not registered" | Do a full rebuild after adding the plugin; hot restart isn't enough. |
| `dart run icon_shift_generator` crashes with "Crash when compiling" | A Dart SDK bug seen with Dart 3.13.4 when pub precompiles `package:image`. Run the script directly: `dart run <path-to-icon_shift_generator>/bin/icon_shift_generator.dart` (path deps), or upgrade the SDK. |

## Example app

[`example/`](example) shows one shared icon overridden for Android (icon and
label) and the web (favicon), plus a dark variant (icon + name), a blue
variant (icon only) and a pro variant (name only). It also demonstrates
capability display, state, validation, diagnostics, custom names and
"unsupported" results. Its native resources are generated from
[`example/icon_shift.yaml`](example/icon_shift.yaml).

```bash
cd example
dart run ../generator/bin/icon_shift_generator.dart   # regenerate resources
flutter run
flutter test integration_test -d <device>            # on-device tests
```

## Verification

What has been run, and where (see `PROJECT_CONTEXT.md` for the full log):

| Platform | Unit tests | Built | On-device integration test |
| -------- | ---------- | ----- | -------------------------- |
| Dart core | 59 tests pass (`flutter test`) | – | – |
| Generator | 12 tests pass | – | used to generate the example's resources |
| Android | 6 Kotlin tests pass | yes | 6/6 pass on emulator, API 29 |
| iOS | – | see PROJECT_CONTEXT.md | see PROJECT_CONTEXT.md |
| macOS | – | see PROJECT_CONTEXT.md | see PROJECT_CONTEXT.md |
| Web | Chrome DOM tests | see PROJECT_CONTEXT.md | – |
| Windows | GTest written, **not compiled** | **no** (no Windows host) | **no** |
| Linux | GTest written, **not compiled** | **no** (no Linux host) | **no** |

The Windows and Linux implementations are complete code but have **not been
compiled or run**. Treat them as unverified until they are built on those
hosts.

## Publishing to pub.dev

Before the first release:

1. Choose a license and replace `LICENSE` (currently a placeholder).
2. Replace the Android package `com.example.icon_shift` (`pubspec.yaml`
   `flutter.plugin.platforms.android.package`, `android/build.gradle.kts`
   `namespace`/`group`, and the Kotlin `package` lines) with your own.
3. Set `repository:`/`homepage:` in `pubspec.yaml` and
   `generator/pubspec.yaml`, and update the podspecs' `homepage`/`author`.
4. Build and run the example on Windows and Linux.

Then publish:

```bash
flutter pub publish --dry-run   # in the repo root (generator/ is excluded via .pubignore)
flutter pub publish
cd generator && dart pub publish --dry-run && dart pub publish
```

Once both are published, change the example's `icon_shift_generator`
dependency from a path to a version, if you like.
