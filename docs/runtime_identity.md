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
* `setDisplayName('Anything')` sets it to any string (scope
  `IdentityScope.taskSwitcher`); `setIdentity()` resets it to the alias label.

Flutter's `MaterialApp.title` writes the same recent-apps label (and the web
document title) on every rebuild. Bind it to IconShift so a rebuild does not
undo a change:

```dart
ValueListenableBuilder<String?>(
  valueListenable: IconShift.displayNameListenable,
  builder: (context, name, _) => MaterialApp(title: name ?? 'Notes', home: …),
)
```

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
