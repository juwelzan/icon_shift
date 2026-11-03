# Icon configuration

## Sources

One square PNG (1024 × 1024 recommended) can serve every platform; override
it per platform or variant where you need different artwork.

| Use | Minimum | Notes |
| --- | --- | --- |
| Android legacy mipmaps | 192 px | 48 dp at mdpi … xxxhdpi |
| Android adaptive layers (`adaptive_foreground`, `monochrome`) | 432 px | full 108 dp layers |
| iOS app icon sets | 1024 px | transparency is flattened onto `ios.background_color` |
| macOS AppIcon (`macos.app_icon`) | 1024 px | 16–1024 px, Xcode builds the `.icns` |
| Windows `.ico` (`windows.app_icon`) | 256 px | 16, 24, 32, 48, 64, 128, 256 |
| Linux hicolor (`linux.icons`) | 256 px | 16–512 px, or an SVG override copied to `scalable/` |
| Web (`web.icons`) | 512 px | favicon 32, PWA 192/512, maskable 192/512 |
| Runtime desktop icons | any | PNG/JPEG decoded natively |

The CLI never upscales, rejects non-square images, and rejects SVG wherever a
raster is needed (it cannot rasterize SVG reliably without heavy
dependencies — export a PNG).

Any image may also be an **`https://` URL**: `generate`, `validate`,
`preview` and `assets` download it into `remote.assets_dir` (default
`assets/icon_shift/remote/`) first, and everything else — native resources,
the generated Dart config — uses the downloaded file. See
[Server-provided icons](#server-provided-icons).

## YAML reference

```yaml
default:
  name: Notes
  icon: assets/icons/app.png
  appearances:                                   # iOS 26 / macOS 26 modes
    dark: assets/icons/app_dark.png              # Dark
    tinted: assets/icons/app_tinted.png          # Tinted (grayscale)
    clear: assets/icons/app_clear.png            # Clear (previews; see below)
  platforms:
    android:
      icon: assets/icons/app_android.png
      adaptive_foreground: assets/icons/fg.png   # 108 dp layer
      monochrome: assets/icons/mono.png          # Android 13 themed icons
    ios:
      dark: assets/icons/app_dark_ios.png        # iOS-only artwork wins over
                                                 # the shared appearances
    linux:
      icon: assets/icons/app.svg                 # SVG allowed here
    web:
      icon: assets/icons/favicon.png

variants:
  dark:   { icon: assets/icons/dark.png, appearance: dark, theme_color: "#121212" }
  summer:
    icon: https://cdn.example.com/icons/summer.png       # downloaded
    appearances: { dark: https://cdn.example.com/icons/summer_dark.png }
  blue:   { icon: assets/icons/blue.png }
  green:  { icon: assets/icons/green.png }
  winter: { name: Notes ❄, icon: assets/icons/winter.png }   # seasonal

renamed:
  night: dark          # devices using "night" are moved to "dark"

android:
  adaptive_background: "#FFFFFF"   # enables adaptive icons (and monochrome)
  set_display_name: true           # default.name → <application android:label>
ios:
  background_color: "#FFFFFF"
  primary_icon: false              # true: also regenerate AppIcon.appiconset
  set_display_name: true           # default.name → CFBundleDisplayName,
                                   # names: → <lang>.lproj/InfoPlist.strings
macos:   { app_icon: false }
windows: { app_icon: false }
linux:   { icons: false, output_dir: linux/packaging }
web:     { icons: false, maskable_background: "#FFFFFF" }
dart:    { output: lib/icon_shift_config.g.dart }
remote:
  manifest: https://cdn.example.com/icons/manifest.json  # optional
  assets_dir: assets/icon_shift/remote                  # add to flutter > assets
```

## The display name

One name in `icon_shift.yaml` reaches every platform through
`icon_shift_cli generate`. It is written into the native build, so it changes
with the next build and install — never by itself at runtime.

```yaml
default:
  name: Acme Notes                      # the app's name everywhere
  names:                                # optional translations
    bn: অ্যাকমে নোটস
    de: Acme Notizen
  icon: assets/icons/app.png
  platforms:
    android: { name: Acme Notes Android }   # per-platform override
```

```sh
dart run icon_shift_cli generate      # writes the native resources
flutter build apk                     # or ipa / appbundle
```

| Platform | What `generate` writes | Where it shows |
| --- | --- | --- |
| Android | `<string name="icon_shift_app_name">` in `res/values*/icon_shift.xml`, and `<application android:label="@string/icon_shift_app_name">` | Settings, app list, share sheets, "App info" |
| Android | `<string name="icon_shift_label_<variant>">` per variant, on each activity-alias | The launcher entry (the active variant's label) |
| iOS | `CFBundleDisplayName` in `Info.plist`, plus `<lang>.lproj/InfoPlist.strings` registered in the Xcode project | The home screen and settings |
| macOS, Windows, Linux, web | the window/document title at runtime; shipped names stay build-time (`identity --apply`) | See [runtime identity](runtime_identity.md) |

Names may contain any Unicode — Bangla, emoji, spaces, `&`, `<`, quotes — and
are escaped for XML, Android string resources and `.strings` files.

**The display name is not the application id.** `generate` never touches
`applicationId`, the Apple bundle identifier or the package name; changing
those is a separate, deliberate step (`identity --apply`, see
[build-time identity](build_time_identity.md)) that installs a *new* app.

Opt out per platform when the project manages its own label:

```yaml
android: { set_display_name: false }   # leaves <application android:label> alone
ios:     { set_display_name: false }   # leaves CFBundleDisplayName alone
```

### Android: two labels

Android shows the **activity-alias label** in the launcher (so icon and name
switch together per variant) and the **application label** everywhere else.
`generate` writes both from `default.name`; variants override the launcher
label only. If `application.display_name` differs from `default.name`,
`generate` warns, because `identity --apply` would write a different name.

### Verifying what was built

```sh
# Android: what the launcher and installer read
aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk | grep application-label

# iOS
/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' \
  build/ios/iphonesimulator/Runner.app/Info.plist
```

### The name did not change

* **The generator did not run.** `generate` is a build-time step; run it after
  every configuration change, then rebuild.
* **An old build is installed.** Android and iOS read the name from the
  installed bundle: reinstall, and on iOS delete the app first if the home
  screen keeps the old name.
* **Stale build output.** `flutter clean`, then `generate`, then build.
  On iOS also delete `~/Library/Developer/Xcode/DerivedData` for the project.
* **The launcher caches labels.** Some Android launchers need a few seconds,
  a launcher restart or a reboot.
* **Another tool owns the label.** If `<application android:label>` is not
  `@string/icon_shift_app_name` after `generate`, something rewrites the
  manifest (another package, a manifest placeholder, or
  `android.set_display_name: false`).
* **You expected a runtime change.** Changing the name of the *installed* app
  from inside the app is not possible on Android or iOS; see
  [runtime identity](runtime_identity.md) for what each platform does allow.

## Appearances: Default, Dark, Clear, Tinted

iOS 26 and macOS 26 (Liquid Glass) let the user pick the home-screen icon
mode: **Default**, **Dark**, **Clear** or **Tinted**. Give each icon its
artwork under `appearances:` (or per platform, `platforms.ios.dark` /
`tinted` / `clear`, likewise for `macos`). Appearances belong to the icon
they sit next to: a variant with its own icon never inherits the default's
dark artwork, and a platform override that replaces the icon brings its own.

| Platform | Default | Dark | Tinted | Clear |
| --- | --- | --- | --- | --- |
| iOS 18+ / 26 | icon set | written to the icon set (`luminosity: dark`); the OS switches by itself | written to the icon set (`luminosity: tinted`) | asset catalogs have no slot; iOS 26 derives it from the regular icon (custom clear layers need an Icon Composer `.icon` file) |
| macOS | Dock icon | IconShift shows it while the system is dark | — | — |
| Windows, Linux, web | window/taskbar icon, favicon | IconShift shows it while the system is dark | — | — |
| Android | alias icon | — (no dark launcher icons) | use `monochrome` (themed icons, Android 13+) | — |

At runtime the same artwork is available as `AppIdentity.appearances`
(`IconAppearances(dark:, tinted:, clear:)`) for previews, and
`IconShift.initialize(followSystemAppearance: true)` — the default — swaps
the dark artwork in and out on the platforms that apply images themselves.

## Server-provided icons

Launcher icons on **iOS and Android must be compiled into the app**: neither
OS accepts a downloaded image (iOS only switches between alternate icons in
the bundle, Android only between activity-aliases). Icons from a server
therefore reach those platforms through the build:

1. The server publishes images and, optionally, a manifest:

   ```json
   {
     "variants": {
       "halloween": {
         "name": "Spooky Notes",
         "icon": "halloween.png",
         "appearances": {
           "dark": "halloween_dark.png",
           "tinted": "halloween_tinted.png",
           "clear": "halloween_clear.png"
         }
       }
     }
   }
   ```

   Variants use the same keys as icon_shift.yaml; relative URLs resolve
   against the manifest URL; only https is accepted (http only for
   `localhost`). A variant also defined in icon_shift.yaml keeps the local
   definition.
2. `dart run icon_shift_cli generate` downloads everything (PNG/JPEG,
   ≤ 10 MB each), names the files after a hash of their URL, and generates
   the Android aliases, iOS icon sets (with dark/tinted) and the Dart config.
   Later runs reuse the downloads; `generate --refresh-remote` fetches them
   again.
3. Ship the build. At runtime the app switches to the variant with
   `setIdentity('halloween')`, or with `setRemoteIcon` and `"variant":
   "halloween"` (see [runtime identity](runtime_identity.md#remote-icons)).

macOS, Windows, Linux and web can additionally show a downloaded image
without a new build: `IconShift.setRemoteIcon`.

## What gets generated

| Output | Owner | Notes |
| --- | --- | --- |
| `res/mipmap-*/ic_icon_shift_<id>*.png`, `mipmap-anydpi-v26/ic_icon_shift_<id>.xml` | CLI | adaptive XML includes `<monochrome>` when configured |
| `res/values*/icon_shift.xml` | CLI | the application label (`icon_shift_app_name`) and the per-variant launcher labels, per locale (`values-de`, `values-pt-rBR`, `values-b+zh+Hant`) |
| `<application android:label>` in AndroidManifest.xml | app | repointed at `@string/icon_shift_app_name` unless `android.set_display_name: false` |
| manifest aliases between markers | CLI | retired aliases for removed/renamed variants |
| `Info.plist` `CFBundleDisplayName`, `Runner/<lang>.lproj/InfoPlist.strings` + Xcode project entries | CLI | home-screen name from `default.name` / `names:`; `ios.set_display_name: false` to skip |
| `Assets.xcassets/<id>.appiconset` | CLI | `info.author: icon_shift_cli`; light/dark/tinted |
| `AppIcon.appiconset` (iOS/macOS), `app_icon.ico`, `web/icons/*`, `web/favicon.png` | app | only with the opt-in flags; backed up first |
| `linux/packaging/*` | CLI | hicolor icons + `<app-id>.desktop` for your packaging |

## Themed icons — what the OS really does

| Platform | Theme behaviour |
| --- | --- |
| Android 13+ | Shows the monochrome layer tinted by the wallpaper **if the user enabled themed icons**. Apps cannot enable it. |
| iOS 18+ / 26 | Picks default/dark/tinted artwork from the icon set by the home-screen mode; derives Clear (iOS 26) from the regular artwork. |
| macOS | Bundle icon from the asset catalog; IconShift swaps the Dock icon to the dark artwork in dark mode. |
| Windows, Linux | No themed app icons. |
| Web | A favicon can follow `prefers-color-scheme`; IconShiftThemeSync can switch favicons at runtime. |

None of them switches the launcher icon when your *Flutter* theme changes;
`IconShiftThemeSync` does that explicitly, where supported.

## Validation

* `dart run icon_shift_cli assets --check` — existence, format, square,
  sizes per use, transparency.
* `IconShift.validateConfiguration()` — at runtime: bundled assets, native
  resources (aliases, alternate icons), SVG on desktop.
