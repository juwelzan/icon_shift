# Multi-tenant (white-label) branding

One app, one branded experience per tenant. Branding comes from your own
server at runtime; only the **launcher** name and icon are limited by what
Android and iOS allow (see
[Native launcher branding](#native-launcher-branding)).

IconShift assumes no particular back end: you supply a
[branding provider](#branding-providers), and it handles caching, tenant
isolation, offline start and the native work.

## Branding providers

A `BrandingProvider` answers two questions: which tenant this is, and what
its branding is.

```dart
// A JSON endpoint per tenant (a host per tenant):
HttpBrandingProvider.host(
  Uri.parse('https://abc.example.com'),
  path: '/api/v1/branding',
);

// One endpoint for every tenant:
HttpBrandingProvider(
  url: Uri.parse('https://api.example.com/branding?tenant=school_123'),
  tenantId: 'school_123',
  headers: {'Authorization': 'Bearer $token'},
);

// Branding from code you already have:
CallbackBrandingProvider(
  tenantId: institution.id,
  fetch: () async =>
      BrandingProfile.parse(await api.getBranding(), tenantId: institution.id),
);

// A fixed profile (app-local branding, tests):
StaticBrandingProvider(const BrandingProfile(tenantId: 'local', appName: 'My App'));
```

`tenantId` is the cache key, so two tenants can never see each other's
branding. Writing your own provider is three lines: implement `tenantId` and
`fetch()`.

### Response shape

`BrandingProfile.parse` reads a JSON object, unwrapping a `data` envelope if
there is one:

```json
{
  "data": {
    "app_name": "ABC School",
    "logo_url": "https://cdn.example.com/abc/logo.png",
    "launcher_icon_url": "https://cdn.example.com/abc/icon.png",
    "primary_color": "#2563EB",
    "secondary_color": "#4F46E5",
    "institution_id": "school_123"
  }
}
```

Every field is optional. The defaults also accept `name`,
`institution_name`, `logo`, `icon_url`, `favicon_url`, `app_code`,
`tenant_id`, `branding_version` and `version`. Unknown fields are kept in
`BrandingProfile.extras`.

When the field names differ, map them instead of writing an adapter:

```dart
const fields = BrandingFieldMap(
  envelope: 'result',          // or null when the payload is top level
  appName: ['title'],
  launcherIconUrl: ['icon'],
  primaryColor: ['brand_colour'],
);
HttpBrandingProvider(url: endpoint, tenantId: id, fields: fields);
```

## Using it

```dart
await IconShift.initialize(
  iconShiftConfig,
  defaultBranding: const BrandingProfile(
    tenantId: 'default',
    appName: 'My App',           // before a tenant is chosen
  ),
  // Optional: start loading a tenant right away, without blocking startup.
  brandingProvider: savedTenant,
);

// After the user picks a tenant:
await IconShift.loadBranding(
  HttpBrandingProvider.host(
    Uri.parse('https://abc.example.com'),
    path: '/api/v1/branding',
  ),
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
      title: b.displayName ?? 'My App',
      theme: ThemeData(
        colorSchemeSeed: Color(b.primaryColor ?? 0xFF2563EB),
      ),
      home: Scaffold(
        appBar: AppBar(title: Text(b.displayName ?? 'My App')),
      ),
    );
  },
);
```

| Call | What it does |
| --- | --- |
| `IconShift.loadBranding(provider)` | Cached branding first, then the provider. Switching tenant drops the previous one's cache before anything is shown. |
| `IconShift.refreshBranding()` | Re-fetches the active tenant. |
| `IconShift.applyBranding(profile)` | Shows a profile the app already has (a push payload, a bundled file) and caches it. |
| `IconShift.branding.clear()` | Logout: forgets the tenant and its cache, back to `defaultBranding`. |
| `IconShift.branding.loadLogo()` | Downloads `logo_url` (https, ≤ 5 MB, must be an image) or returns `null`. |
| `IconShift.applyLauncherBranding()` | Applies the name and icon to the launcher as far as the platform allows, and reports how far. |
| `IconShift.branding.value` | `BrandingState(profile, status, tenantId, error)`. |

`BrandingStatus` tells the UI where the branding came from: `idle`, `cached`,
`live`, `offline` (server unreachable — cached or default is shown, nothing
throws) or `invalid` (unusable answer — the previous branding stays).

### Rebuilds and requests

* Unchanged branding is not re-cached and listeners are not notified: the
  version comes from the server, or is a content hash when it sends none —
  many endpoints send neither a version nor an `ETag`.
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
| Android | a home-screen **shortcut** with the tenant's name and downloaded icon — the app's own entry can only show what the build compiled in (the user accepts once, later changes are silent) |
| iOS | the icon of `fallbackVariant` if it is in the build; the name **cannot** change at runtime |

It returns a `NativeBrandingReport`, so the app can tell "done" from "needs
a branded build" instead of guessing:

```dart
final report = await IconShift.applyLauncherBranding(fallbackVariant: 'dark');
switch (report.scope) {
  case NativeBrandingScope.applied:       // the app's own launcher entry
  case NativeBrandingScope.shortcut:      // a shortcut beside it (Android)
  case NativeBrandingScope.requiresBuild: // build this tenant its own app
  case NativeBrandingScope.unsupported:   // nothing to change here
}
```

Neither Android nor iOS lets an installed app turn an arbitrary downloaded
image into its own launcher icon. So:

### Mode A — one shared app (default)

Every tenant uses the same build. In-app branding is fully dynamic; the
launcher shows the app's own name. Tenants that want their name on the home
screen get the optional shortcut on Android. Switching tenants never needs a
reinstall.

### Mode B — a branded build per institution, automated

`icon_shift_cli brand` turns the shared codebase into one institution's app
and puts it back afterwards, so a build service can loop over schools.

```sh
dart run icon_shift_cli brand \
  --host https://abc.example.com \
  --slug abc_school \
  --application-id com.example.{slug} \
  --bundle-id com.example.{slug} \
  --build apk --build ios \
  --artifacts out/
```

What one run does:

1. `GET https://abc.example.com/api/v1/branding` — or `--branding-file` for
   a document the pipeline already has.
2. Validates the response: name, `#RRGGBB` colours, https URLs.
3. Downloads the school's logo into `remote.assets_dir`.
4. Writes the Android resources: launcher icons per density (adaptive, with
   the school's primary colour as the background), the alias labels, and
   `<application android:label>` through `icon_shift_app_name`.
5. Writes the iOS asset catalog — the **primary** `AppIcon`, not just an
   alternate set — and `CFBundleDisplayName`.
6. Applies the per-institution `applicationId` and bundle id. `{slug}`
   expands to `abc_school` for Android and `abc-school` for Apple, which
   rejects `_`.
7. Runs `flutter build` for each `--build` target.
8. Reads the finished artifact back (`aapt2 dump badging`, `Info.plist`) and
   **fails the run** if the name or id does not match.
9. Copies the artifact and a `build.json` record into `--artifacts`.
10. Restores the working tree from the backup (`--no-revert` to keep it).

| Option | Meaning |
| --- | --- |
| `--host` | School host serving the branding endpoint |
| `--branding-path` | Endpoint path (default `/api/v1/branding`) |
| `--name` / `--icon` | Brand from local values instead of a server |
| `--slug` | Build identifier; default from the host |
| `--application-id` / `--bundle-id` | Templates containing `{slug}` |
| `--build` | `apk`, `appbundle`, `ios`, `ios-simulator` (repeatable) |
| `--artifacts` | Where to collect artifacts and `build.json` |
| `--no-verify` | Skip the artifact check |
| `--no-revert` | Leave the branded working tree in place |
| `-n` | Show the changes without writing or building |

The institution's name wins over `application.display_name` and over any
shared per-platform or per-locale name, so no device language falls back to
the shared app's name.

#### In a build service

```sh
for host in $(curl -s https://admin.example.com/api/v1/tenants | jq -r '.data[].host'); do
  dart run icon_shift_cli brand --host "https://$host" \
    --application-id com.example.{slug} --bundle-id com.example.{slug} \
    --build appbundle --artifacts out/ || echo "FAILED: $host"
done
```

A pipeline whose API IconShift cannot call directly hands the document over
instead:

```sh
dart run icon_shift_cli brand --branding-file tenant.json --slug abc_school …
```

Each run starts from the same clean codebase, so builds are repeatable and
order does not matter. `build.json` records the institution, the ids and the
verified artifact values for the distribution step.

iOS still needs signing for a device build or an IPA: run `--build ios` on a
machine with the institution's provisioning profile, or hand the branded tree
(`--no-revert`) to Xcode Cloud / Fastlane.

#### Verified

Three tenants were built from one codebase; the first two were installed:

| | Tenant A (live server) | Tenant B (own logo) |
| --- | --- | --- |
| Branding source | a live school host | a local test server |
| Android label | `Amena Baki Residential Model School and College` | `Sunrise Academy` |
| applicationId | `com.digiedu.amena_baki` | `com.digiedu.sunrise` |
| Launcher label in every locale | the tenant's name | the tenant's name |
| iOS `CFBundleDisplayName` | same name | `Sunrise Academy` |
| Bundle id | `com.digiedu.amena-baki` | `com.digiedu.sunrise` |
| Launcher icon | shared (no logo published) | the downloaded logo |

Both appear side by side in the Android app drawer and on the iOS home
screen with their own names, and the shared codebase was byte-identical
before and after every build.

A third tenant was built from a bespoke response shape through
`--branding-file` (`{"data": {...}}` with `institution_id`), producing
`application-label:'Riverdale Academy'` and
`package: name='com.example.riverdale'` — the engine is not tied to one
back end.

Mode A and Mode B share the same configuration and the same runtime API: a
school can start on the shared app and move to its own build later.

## Checking a school's endpoint

```sh
flutter test tool/branding_live_check.dart \
  --dart-define=url=https://abc.example.com/api/v1/branding
```

It fetches and parses through the package's own provider and prints the
profile and the exact JSON that would be cached.
