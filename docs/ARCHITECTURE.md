# IconShift architecture

## Package layout

```text
icon_shift/                    Flutter plugin (runtime) — published to pub.dev
├── lib/
│   ├── icon_shift.dart        public library (exports only)
│   ├── icon_shift_web.dart    web implementation (registered via pubspec)
│   └── src/
│       ├── icon_shift.dart    IconShift static facade
│       ├── engine.dart        IconShiftEngine: all orchestration logic
│       ├── config/            IconShiftConfig, AppIdentity, resolution
│       ├── models/            capabilities, results, state, variants, diagnostics
│       ├── validation/        configuration validator
│       ├── platform/          platform interface + method-channel impl
│       └── exceptions.dart
├── android/  ios/  macos/  windows/  linux/   one native impl per platform
├── generator/                 icon_shift_generator — separate dev-time CLI package
├── example/
├── test/
└── docs/
```

### Why not a federated (multi-package) plugin?

A federated split (`icon_shift`, `icon_shift_platform_interface`,
`icon_shift_android`, …) pays off when third parties implement platforms or
platforms version independently. Here all six implementations are first-party
and released together, so the split would add seven pubspecs and version
lock-step for no user benefit. The code is still structured the federated way
internally: `IconShiftPlatformInterface` extends `PlatformInterface` and every
platform sits behind it, so it can be split later without API changes.

### Why the generator is a separate package

Resizing images needs `package:image` (+ `yaml`, `args`). Putting those in the
runtime plugin would push them into every app's dependency graph. Like
`flutter_launcher_icons`, the generator is a `dev_dependency`
(`dart run icon_shift_generator`). Using it is optional: everything it produces
can be written by hand.

## Layering

```text
 app code ──► IconShift (static facade, thin)
                 │
                 ▼
            IconShiftEngine ── IconShiftConfig.resolve() (pure)
                 │          └─ ConfigValidator (pure + async asset/native checks)
                 ▼
     IconShiftPlatformInterface      (native keys only; knows nothing about config)
        │                      │
 MethodChannelIconShift    IconShiftWeb (Dart, package:web)
        │
 Kotlin / Swift(iOS) / Swift(macOS) / C++(Win32) / C(GTK)
```

* **Config** is pure, immutable, `const`-constructible data. Resolution is a
  pure function → trivially unit-testable.
* **Engine** owns policy: validation before applying, capability checks,
  operation ordering, partial failure, persistence. It is constructed with a
  platform instance, so tests use a fake.
* **Platform interface** is deliberately low-level: "set icon key `dark` (with
  these PNG bytes)", "set name", "report state/capabilities/issues". Native code
  never parses the Dart config.

## Configuration model and override resolution

```dart
IconShiftConfig(
  defaultIdentity: AppIdentity(
    name: 'My App',
    icon: AppIcon.asset('assets/icons/app.png'),
    platforms: {
      IconShiftPlatform.android: IdentityOverride(icon: AppIcon.asset('assets/icons/android.png')),
    },
  ),
  variants: {
    'dark': AppIdentity(
      name: 'My App Dark',
      icon: AppIcon.asset('assets/icons/dark.png'),
      platforms: {IconShiftPlatform.web: IdentityOverride(name: 'Dark (web)')},
    ),
  },
)
```

Design choices vs. the brief's sketch:

* Platform overrides live *inside* each identity (`AppIdentity.platforms`)
  instead of a top-level `platforms` map. Default and variants use the same
  shape, so there is one rule to learn.
* Overrides are `IdentityOverride` (name/icon only), not `AppIdentity`, so the
  type system forbids meaningless nesting (`platforms` inside `platforms`).
* Variants are a `Map<String, AppIdentity>`; the id `default` is reserved for
  `defaultIdentity`.

Resolution of a field (`name` or `icon`) for variant *v* on platform *p* — the
first non-null wins:

1. `variants[v].platforms[p]`
2. `variants[v]`
3. `defaultIdentity.platforms[p]`
4. `defaultIdentity`

Name and icon resolve independently. A variant that does not define its own
icon (steps 1–2) is said to *use the default icon*: switching to it restores
the shipped icon instead of applying an asset copy of it. Same for names.

## Public API

```dart
abstract final class IconShift {
  static Future<void> initialize(IconShiftConfig config, {bool restoreSelection = true});
  static bool get isInitialized;
  static IconShiftConfig get config;

  static Future<IconShiftResult> setIdentity(String variantId);   // icon + name of a variant
  static Future<IconShiftResult> setIcon(String variantId);       // icon only*
  static Future<IconShiftResult> setDisplayName(String name);     // arbitrary text, where allowed
  static Future<IconShiftResult> setCustomIdentity({String? iconVariant, String? displayName});
  static Future<IconShiftResult> restoreDefault();

  static Future<IconShiftState> getCurrentIdentity();
  static Future<IconShiftCapabilities> getCapabilities();
  static Future<List<IdentityVariant>> getVariants();
  static Future<IconShiftValidationResult> validateConfiguration();
  static Future<IconShiftDiagnostics> getDiagnostics();
}
```

\* On Android icon and label are linked; the result reports the label change.

Changes from the brief's sketch, and why:

| Brief                                      | Final                                      | Reason |
| ------------------------------------------ | ------------------------------------------ | ------ |
| `Future<void>` for mutations               | `Future<IconShiftResult>` (`@useResult`)   | Partial success is normal across platforms; a result per operation is the only honest return. `@useResult` makes ignoring it a lint warning. `result.throwIfFailed()` for exception style. |
| `setCustomIdentity({AppIcon? icon, …})`    | `{String? iconVariant, String? displayName}` | No platform with launcher icons accepts arbitrary images; icons are always preconfigured variants. |
| `IconShift.configure` + `initialize`       | `initialize(config)` only                  | One entry point; config is immutable. |
| `getVariants()` returning config           | returns `IdentityVariant` with resolved name, preview asset, `isAvailable`, `isCurrent` | Ready for building a picker UI; availability comes from native inspection. |
| —                                          | `getDiagnostics()`                         | Required by brief §7.I. |

### Errors vs. results

* **Exceptions** (`IconShiftException` subclasses) for programmer errors that
  should be fixed in code: not initialized, unknown variant id, invalid
  display-name argument, invalid configuration at `initialize`.
* **Results** for everything decided by the OS: unsupported, failed, pending.
  Each `OperationOutcome` has a status, an `IconShiftErrorCode` and a message.

### Safe switching (batch)

1. Validate everything (variant exists, name is valid) before touching native.
2. Icon first, then name.
3. If the icon operation **fails** (not merely unsupported), the name is
   `skipped` so the app is not left half-switched.
4. Persist the selection only for operations that were applied.

### State

`IconShiftState` distinguishes:

* `requested*` — last selection the app asked for (persisted).
* `native*` — what the OS reports now (Android enabled alias, iOS
  `alternateIconName`, desktop/web: what native applied in this process).
* `isIconInSync` / `isDisplayNameInSync` and `pendingIconVariant`.

## Native channel protocol (`icon_shift` MethodChannel)

| Method            | Arguments                                      | Returns |
| ----------------- | ---------------------------------------------- | ------- |
| `getCapabilities` | –                                              | `{icon:{…}, displayName:{…}, iconAndNameLinked, notes:[…]}` |
| `getNativeState`  | –                                              | `{iconKey?, displayName?, pendingIconKey?}` |
| `setIcon`         | `{key?: String, bytes?: Uint8List}` (`key` null = default) | `{status, message?, displayName?}` |
| `setDisplayName`  | `{name?: String}` (null = restore original)    | `{status, message?}` |
| `inspect`         | `{variants:[{id, hasOwnIcon, name?}]}`         | `{issues:[{severity, code, message, variantId?}], info:{…}}` |
| `loadSelection`   | –                                              | `Map<String,String>?` |
| `saveSelection`   | `{selection: Map<String,String?>}`             | – |

Errors are `PlatformException` with codes `unsupported`, `missing_resource`,
`permission_denied`, `invalid_argument`, `not_active`, `native_failure`.
