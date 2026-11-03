# Multi-tenant (white-label) branding

One app, one branded experience per institution. Branding comes from the
school's own server at runtime; only the **launcher** name and icon are
limited by what Android and iOS allow (see
[Native launcher branding](#native-launcher-branding)).

## How a school is identified

DigiEdu / Schoolmate gives every institution its own host, and the branding
endpoint needs no login:

```
GET https://<school>.digiedu.online/api/v1/branding
Accept: application/json
```

```json
{
  "data": {
    "app_name": "Amena Baki Residential Model School and College",
    "logo_url": null,
    "favicon_url": null,
    "primary_color": "#1e40af",
    "secondary_color": "#3b82f6",
    "app_code": "588846"
  },
  "message": "Branding retrieved successfully."
}
```

The **host is the tenant**: it is the cache key, so two schools can never see
each other's branding. `BrandingTenant(host: …)` builds the endpoint URL and
the tenant id from it.

The response is parsed by [`BrandingProfile`](../lib/src/branding/branding_profile.dart),
which also accepts `institution_name`/`name`, `launcher_icon_url`/`icon_url`,
`institution_id`/`tenant_id` and `branding_version`/`version`, with or
without the `data` envelope — so another back end needs no adapter. Unknown
fields are kept in `BrandingProfile.extras`.

## Using it

```dart
await IconShift.initialize(
  iconShiftConfig,
  defaultBranding: const BrandingProfile(
    tenantId: 'default',
    appName: 'Schoolmate',          // before a school is chosen
  ),
);

final branding = IconShift.branding;

// After the user picks or types a school address:
await branding.load(
  BrandingTenant(host: Uri.parse('https://abc.digiedu.online')),
);
```

`load()` shows the cached branding immediately and refreshes from the server
in the background, so **startup never waits for the network**.

```dart
ValueListenableBuilder<BrandingState>(
  valueListenable: IconShift.branding,
  builder: (context, state, _) {
    final b = state.profile;
    return MaterialApp(
      title: b.displayName ?? 'Schoolmate',
      theme: ThemeData(
        colorSchemeSeed: Color(b.primaryColor ?? 0xFF1E40AF),
      ),
      home: Scaffold(
        appBar: AppBar(title: Text(b.displayName ?? 'Schoolmate')),
      ),
    );
  },
);
```

| Call | What it does |
| --- | --- |
| `load(tenant)` | Cached branding first, then the server. Switching tenant drops the previous school's cache before anything is shown. |
| `refresh()` | Re-fetches the active school. |
| `clear()` | Logout: forgets the school and its cache, back to `defaultBranding`. |
| `loadLogo()` | Downloads `logo_url` (https, ≤ 5 MB, must be an image) or returns `null`. |
| `applyLauncherBranding()` | Applies the name and icon to the launcher as far as the platform allows. |
| `IconShift.branding.value` | `BrandingState(profile, status, tenant, error)`. |

`BrandingStatus` tells the UI where the branding came from: `idle`, `cached`,
`live`, `offline` (server unreachable — cached or default is shown, nothing
throws) or `invalid` (unusable answer — the previous branding stays).

### Rebuilds and requests

* Unchanged branding is not re-cached and listeners are not notified: the
  version comes from the server, or is a content hash when it sends none
  (this endpoint sends no `branding_version` and no `ETag`).
* Concurrent `load()` calls share one request.

### Safety

* URLs must be `https` (`http` only for `localhost`); bad ones are dropped,
  the rest of the branding still applies.
* Colours must be `#RGB`, `#RRGGBB` or `#AARRGGBB`; names must be printable
  and ≤ 255 characters.
* The branding document is capped at 256 KB, images at 5 MB.
* Branding can never change the application id or bundle identifier — those
  are build-time only, see [build-time identity](build_time_identity.md).

## Native launcher branding

The home-screen name and icon are **not** part of in-app branding.

| Platform | What `applyLauncherBranding()` does |
| --- | --- |
| macOS, Windows, Linux | Dock/taskbar icon and window title, from the downloaded image |
| Web | favicon and tab title |
| Android | a home-screen **shortcut** with the school's name and downloaded icon — the app's own entry can only show what the build compiled in (the user accepts once, later changes are silent) |
| iOS | the icon of `fallbackVariant` if it is in the build; the name **cannot** change at runtime |

Neither Android nor iOS lets an installed app turn an arbitrary downloaded
image into its own launcher icon. So:

### Mode A — one shared Schoolmate app (default)

Every school uses the same build. In-app branding is fully dynamic; the
launcher shows "Schoolmate". Schools that want their name on the home screen
get the optional shortcut on Android. Switching schools never needs a
reinstall.

### Mode B — a branded build per school

For schools that must own the home-screen identity, build per institution
from the same codebase:

```yaml
# icon_shift.yaml
default:
  name: Schoolmate
  icon: assets/icons/schoolmate.png

remote:
  manifest: https://admin.digiedu.online/api/v1/branding/manifest   # optional

build_profiles:
  abc_school:
    display_name: ABC School
    android: { application_id: com.digiedu.abcschool }
    ios:     { bundle_id: com.digiedu.abcschool }
```

```sh
dart run icon_shift_cli identity --apply --profile abc_school
dart run icon_shift_cli generate        # downloads https: icons, writes resources
flutter build appbundle
```

`generate` writes the Android application label and launcher labels and the
iOS `CFBundleDisplayName` (see
[the display name](icon_configuration.md#the-display-name)); icons come from
the config or from `remote.manifest`, so a build pipeline can produce one
APK/AAB and IPA per school without touching the codebase.

Mode A and Mode B share the same configuration and the same runtime API: a
school can start on the shared app and move to its own build later.

## Checking a school's endpoint

```sh
flutter test tool/branding_live_check.dart \
  --dart-define=host=https://abc.digiedu.online
```

It fetches and parses through the package's own code and prints the profile
and the exact JSON that would be cached.
