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
r.isAppEntryChanged;   // home screen and app drawer show it
r.appEntryName;        // read back from the OS after the call
r.scope;               // appEntry · shortcut · windowTitle · unsupported

await IconShift.getLauncherName();     // app entry, shortcut, available names
await IconShift.refreshLauncherName(); // re-apply the last request
await IconShift.syncBranding();        // refresh branding, apply its name
```

No rebuild, no reinstall, no store update: the change happens on the
installed app. What each OS allows:

### Android — yes, among the names compiled into the app

The launcher reads the label of the enabled activity-alias.
`changeLauncherName` finds the variant whose name matches, enables its alias
with `PackageManager.setComponentEnabledSetting` (the new one first, so the
app never has zero launcher entries), and reads the label back. The home
screen **and** the app drawer change; data and the application id are kept.

* The names have to be in the APK: add each as a variant in
  `icon_shift.yaml` (`abc: { name: ABC School }`) and run
  `icon_shift_cli generate` once. A server can then switch between them at
  any time. `getLauncherName().availableNames` lists them.
* A name that is **not** in the APK cannot become the app entry's label —
  Android has no API to set an arbitrary label on a component. IconShift
  places it on a home-screen shortcut instead (`scope: shortcut`; the user
  accepts once, later renames are silent); the app drawer keeps the app
  entry's name. `allowShortcut: false` turns that off.
* The app must be in the foreground to request the shortcut.
* Launchers may take a few seconds to redraw. A name-only variant keeps the
  current icon; a variant with its own icon changes it too (the result says
  so).

### iOS — no

There is no public API to change an installed app's Home Screen name. It is
`CFBundleDisplayName` in the signed bundle; `setAlternateIconName` changes
only the icon, and alternate icons carry no name. Writing to `Info.plist` at
runtime is impossible (the bundle is read-only and signed). `changeLauncherName`
returns `scope: unsupported`, `errorCode: buildRequired`, and changes
nothing. A different name needs a new build (`icon_shift_cli brand`).

### Verified on installed apps

One install of an app named "Schoolmate", renamed at runtime; the launcher was
read with `uiautomator` on Android and a Home Screen screenshot on iOS:

| Call | Android 10 home screen | Android 10 app drawer | iOS 26 Home Screen |
| --- | --- | --- | --- |
| (installed) | Schoolmate | Schoolmate | Schoolmate |
| `changeLauncherName('ABC School')` | ABC School | ABC School | Schoolmate (`unsupported`) |
| `changeLauncherName('XYZ College')` | XYZ College | XYZ College | — |
| `changeLauncherName('Sunrise Academy')`, not compiled in | + shortcut "Sunrise Academy" | XYZ College | — |

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

## Any name and icon at runtime

`setDisplayName` and `setIdentity` are bound by what each OS allows for the
**app's own** entry. For a name and image chosen while the app runs — typed
by the user, or sent by a server — use one call that picks the strongest
mechanism the platform has:

```dart
final r = await IconShift.setArbitraryIdentity(
  name: 'Work Notes',
  icon: AppIcon.asset('assets/icons/work.png'),   // or remoteIcon: …
);
```

| Platform | What changes |
| --- | --- |
| macOS, Windows, Linux | Dock/taskbar icon and window title of the app itself |
| Web | favicon and document title |
| Android | a **home-screen shortcut** with exactly that name and icon |
| iOS | the icon of `variant`; the name cannot change at runtime at all |

### Android home-screen shortcut

The app's launcher entry shows the label and icon compiled into the build, so
IconShift places a shortcut instead — the same mechanism the "icon changer"
apps use:

```dart
await IconShift.setShortcutIdentity(name: 'Work Notes', variant: 'dark');
final state = await IconShift.getShortcutIdentity();
// state.isSupported / isPinned / name / iconKey
await IconShift.removeShortcutIdentity();
```

* Needs Android 8.0 (API 26) and a launcher that supports pinning;
  `IconShiftCapabilities.shortcut` reports both, with the reason when not.
* The **first** call shows the system's "add to home screen" dialog, so the
  outcome is `pending`; call `getShortcutIdentity()` afterwards to see
  whether the user accepted. Every later call updates the pinned shortcut
  silently (`applied`), with no dialog and no limit.
* The icon may be a bundled asset, a variant's icon or a downloaded
  [`RemoteIcon`](#remote-icons) — any image, no rebuild.
* It is an **extra** entry: the app drawer and settings keep the built-in
  name and icon. No app can take a pinned shortcut off the home screen;
  `removeShortcutIdentity()` disables it (greyed out) and
  `setShortcutIdentity()` enables it again.
* Launchers draw a small badge of the app's own icon on top of a shortcut
  icon; that badge cannot be removed.
* A few launchers only pick up a new label or icon after a reboot.

Verified on an Android 10 (API 29) emulator: after the user accepts once,
`setShortcutIdentity(name: 'Changed At Runtime', icon: …)` changes the label
and the image on the home screen immediately, with no further dialog
(`example/integration_test/pin_accept_test.dart`).

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
