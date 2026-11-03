# Runtime identity

Everything on this page happens inside the installed app, through APIs the
OS provides. What each platform allows is in
[PLATFORM_CAPABILITIES.md](../PLATFORM_CAPABILITIES.md).

## Configuration

```dart
const config = IconShiftConfig(
  defaultIdentity: AppIdentity(
    name: 'Notes',
    localizedNames: {'de': 'Notizen'},
    icon: AppIcon.asset('assets/icons/app.png'),
    platforms: {
      IconShiftPlatform.android: IdentityOverride(icon: AppIcon.asset('assets/icons/android.png')),
      IconShiftPlatform.web: IdentityOverride(icon: AppIcon.asset('assets/icons/favicon.png')),
    },
  ),
  variants: {
    'dark': AppIdentity(
      name: 'Notes Dark',
      icon: AppIcon.asset('assets/icons/dark.png'),
      appearance: IdentityAppearance.dark,
      themeColor: 0xFF121212,
    ),
    'business': AppIdentity(name: 'Notes for Work'),          // name only
    'blue': AppIdentity(icon: AppIcon.asset('assets/icons/blue.png')), // icon only
  },
  renamedVariants: {'night': 'dark'},   // ids used by older app versions
);
```

* **Variants are profiles.** Each bundles a name, localized names, an icon,
  appearance/theme metadata and platform overrides; `setIdentity` switches
  all of it in one call.
* **Inheritance.** Unset fields inherit (see the resolution rules in
  [architecture.md](architecture.md#resolution)).
* **Ids** match `[a-z][a-z0-9_]*`; `default` is reserved.

## Operations

```dart
await IconShift.initialize(config);              // validates, restores session-only state
final r = await IconShift.setIdentity('dark');   // icon + name (+ web theme color)
await IconShift.setIcon('blue');                 // icon only (Android: alias label too)
await IconShift.setDisplayName('Anything');      // desktop window title / web title
await IconShift.setCustomIdentity(iconVariant: 'blue', displayName: 'Blue Notes');
await IconShift.restoreDefault();                // shipped identity, clears saved selection
await IconShift.clearSavedSelection();           // forget, but leave the OS as it is
```

Every mutation returns an `IconShiftResult`:

```dart
if (r.isComplete) { /* everything requested is in effect */ }
if (r.isPartial)  { /* some changed, some unsupported/failed */ }
for (final o in [r.icon, r.displayName]) {
  print('${o.status} ${o.errorCode} ${o.message} ${o.suggestion}');
}
r.throwIfFailed(); // exception style
```

Ordering: arguments are validated first; the icon is applied first; if it
**fails**, the name is `skipped` so icon and name never come from different
variants.

## Queries

| Call | Returns |
| --- | --- |
| `getCapabilities()` | Live runtime capabilities per operation (scope, persistence, preconfigured, arbitrary values, limitation). |
| `getPlatformCapabilities()` | The above plus every `IdentityProperty` (runtime / build-time only / unsupported, reinstall, signing, data kept), required configuration and permissions. |
| `getCurrentIdentity()` | Requested vs. OS-reported icon and name, pending state, in-sync flags. |
| `getVariants()` | All variants resolved for this platform, preview asset, availability, current. |
| `previewIdentity(id)` | What `setIdentity(id)` would do here and on every platform, with warnings — nothing is applied. |
| `getApplicationInfo()` | Display name, application/bundle id, version, build, executable, installation type, current icon. Fields the OS does not expose are `null`. |
| `validateConfiguration()` | Config checks, bundled assets, native resources. |
| `getDiagnostics()` | Everything above as one report; contains no user data. |

## Changing the launcher name after installation

```dart
final r = await IconShift.changeLauncherName('ABC School');
r.status;        // success · requiresPreconfiguredLauncher · requiresNewBuild
                 // · unsupported · permissionOrPlatformError · failed
r.changed;       // false when the launcher already showed it
r.appEntryName;  // read back from the OS after the call

await IconShift.getLauncherName();     // what the launcher shows + available names
await IconShift.refreshLauncherName(); // re-apply the last request
await IconShift.syncBranding();        // refresh branding, apply its name
```

This targets the installed app's **own launcher entry** — the name under its
icon on the home screen and in the app drawer — on the same install: no
rebuild, no reinstall, no store update. IconShift never creates a widget, a
shortcut or a second icon to stand in for it. `success` is only returned when
the OS reports the new name.

### Android — yes, among the names compiled into the app

The launcher reads the label of the app's enabled launcher activity — with
IconShift, one `activity-alias` per name. `changeLauncherName` finds the
variant whose name matches, enables its alias with
`PackageManager.setComponentEnabledSetting` (the new one first, so the app
never has zero launcher entries), disables the previous one, and reads the
label back. The same icon on the home screen and the same entry in the app
drawer show the new name; data, the application id and the install are kept.

* The names have to be in the APK. Add each as a name-only variant in
  `icon_shift.yaml` and run `icon_shift_cli generate` once:

  ```yaml
  variants:
    abc: { name: ABC School }
    xyz: { name: XYZ College }
  ```

  A server can then switch between them at any time;
  `getLauncherName().availableNames` lists them. A name-only variant keeps
  the current icon.
* A name that is **not** in the APK returns `requiresPreconfiguredLauncher`
  and changes nothing: Android has no API to give a component a label that
  is not compiled into the app. Ship a build containing the new name once;
  from then on it switches at runtime like the others.
* Launchers may take a moment to redraw; a few third-party launchers only
  refresh after a restart.

### iOS — no

There is no public API to change an installed app's Home Screen name. It is
`CFBundleDisplayName` in the signed bundle; `setAlternateIconName` changes
only the icon, and alternate icons carry no name. The bundle is read-only and
signed, so `Info.plist` cannot be written at runtime. `changeLauncherName`
returns `requiresNewBuild` and changes nothing; a different name needs a new
build (`icon_shift_cli brand`).

### Desktop and web

There is no launcher name an app can change: `unsupported`.
`setDisplayName` changes the window / tab title instead.

### Verified on installed apps

One install of "Schoolmate", renamed at runtime. Android 10 was read with
`uiautomator` and screenshots (home screen, app drawer, shortcut records);
iOS 26 with a Home Screen screenshot.

| Call | Android home screen | Android app drawer | iOS Home Screen |
| --- | --- | --- | --- |
| (installed) | Schoolmate | Schoolmate | Schoolmate |
| `changeLauncherName('ABC School')` | ABC School (same icon, same place) | ABC School | Schoolmate — `requiresNewBuild` |
| `changeLauncherName('XYZ College')` | XYZ College | XYZ College | — |
| `changeLauncherName('Sunrise Academy')`, not compiled in | XYZ College — `requiresPreconfiguredLauncher` | XYZ College | — |
| `changeLauncherName('Schoolmate')` | Schoolmate | Schoolmate | — |

Every step: one launcher entry, no shortcut records, the same package UID and
install time, and the app's stored data intact; tapping the renamed icon
opens the app.

## Display name vs. other names

IconShift keeps these apart:

| Property | Example | Runtime? |
| --- | --- | --- |
| Display name (launcher) | "Notes" under the icon | Android (preconfigured) only |
| Recent-apps label | Android task switcher | Android (any string) |
| Window / document title | macOS window title, browser tab | desktop, web |
| Executable file name | `notes.exe` | never (build time) |
| Application id / package / bundle id | `com.acme.notes` | never (build time; new app) |
| Shortcut name | Start-menu entry | never (installer-owned) |

### Android names

The launcher label comes from the active activity-alias, so it changes only
with `setIdentity()` (to that variant's compiled label). Two things change
at runtime:

* the **recent-apps label** follows the active alias right after a switch
  (before, the running task kept the label of the alias it was launched
  from), and
* `setDisplayName(name)` changes the **launcher** label when a variant's
  alias shows `name` with the current icon (e.g. a name-only variant such as
  `pro: { name: Notes Pro }`): IconShift switches to that alias. Any other
  string is shown in the recent-apps screen only (scope
  `IdentityScope.taskSwitcher`), and the outcome message lists the launcher
  names that exist. `setCustomIdentity(iconVariant:, displayName:)` does the
  same with the given icon. `setIdentity()` resets the recent-apps label to
  the alias label.

Flutter's `MaterialApp.title` writes the same recent-apps label (and the web
document title) on every rebuild. Bind it to IconShift so a rebuild does not
undo a change:

```dart
ValueListenableBuilder<String?>(
  valueListenable: IconShift.displayNameListenable,
  builder: (context, name, _) => MaterialApp(title: name ?? 'Notes', home: …),
)
```

### iOS names

The home-screen name comes from the build: `icon_shift_cli generate` writes
`default.name` into `CFBundleDisplayName` (see
[icon configuration](icon_configuration.md#the-display-name)).

iOS has **no API to rename an installed app**: the home-screen name is
`CFBundleDisplayName` in the signed bundle, and alternate icons carry no
name. `setDisplayName` and variant names therefore return `unsupported`
(`buildRequired`) on iOS. Set the name at build time instead:
`icon_shift_cli generate` writes `default.name` from icon_shift.yaml into
Info.plist and each `names:` translation into `<lang>.lproj/InfoPlist.strings`
(registered in the Xcode project). Rebuild and reinstall to see it.

## Any name and icon on desktop and web

macOS, Windows, Linux and web accept values chosen at runtime for the app
itself; one call applies a name and an image there:

```dart
final r = await IconShift.setArbitraryIdentity(
  name: 'Work Notes',
  remoteIcon: icon,            // or variant: 'dark'
);
```

| Platform | What changes |
| --- | --- |
| macOS, Windows, Linux | Dock/taskbar icon and window title |
| Web | favicon and document title |
| Android | the launcher entry, when a variant has this name (see above) |
| iOS | the icon of `variant`; the name cannot change at runtime |

## Remote icons

```dart
final icon = await IconShift.fetchRemoteIcon(
  Uri.parse('https://example.com/app-icon.json'),
);
final result = await IconShift.setRemoteIcon(icon);
// or: RemoteIcon(url: Uri.parse('https://…/icon.png'), dark: …, variant: 'halloween')
```

```json
{
  "id": "halloween_2026",
  "variant": "halloween",
  "name": "Spooky Notes",
  "icon": "https://cdn.example.com/icons/halloween.png",
  "appearances": { "dark": "halloween_dark.png", "tinted": "…", "clear": "…" }
}
```

| Platform | What `setRemoteIcon` does |
| --- | --- |
| macOS, Windows, Linux | Downloads (https, ≤ 5 MB, must be an image) and applies it; `dark` while the system is dark. Re-downloaded and re-applied on the next launch. |
| Web | Uses the URL as favicon (the server must allow the page to load it). |
| iOS, Android | Cannot show downloaded images. Switches to `variant` when it is part of this build (the OS then applies its dark/tinted/clear artwork); otherwise returns `unsupported` with `buildRequired`. Ship server icons in the build with `remote:` in icon_shift.yaml ([icon configuration](icon_configuration.md#server-provided-icons)). |

Download problems are `failed` outcomes with `IconShiftErrorCode.downloadFailed`;
nothing is saved then.

## Persistence and recovery

The selection is persisted natively. On `initialize()`:

* unknown keys and invalid names are dropped,
* ids in `renamedVariants` are migrated, removed ids forgotten,
* on macOS, Windows, Linux and web the selection is re-applied (these
  changes end with the process); pass `restoreSelection: false` to skip,
* on Android the plugin also repairs the launcher entry at startup if the
  enabled alias was retired or none is enabled.

## Theme-aware identities

Icons with `appearances.dark` need no code: with
`initialize(followSystemAppearance: true)` (the default) macOS, Windows,
Linux and web show the dark artwork while the system is dark; iOS applies
its icon-set appearances itself. To switch whole *variants* (name included)
by brightness:

```dart
final sync = IconShiftThemeSync()..start(); // dark ↔ default by system brightness
```

Opt-in, because operating systems do not switch launcher icons with the
Flutter theme. iOS is excluded by default (each change shows an alert — use
dark/tinted asset appearances there, which iOS applies itself); Android is
debounced.

## Web notes

`MaterialApp(title:)` writes `document.title` whenever it rebuilds. Set it
from `getCurrentIdentity().nativeDisplayName` (see the example app) so it does
not undo `setDisplayName`.
