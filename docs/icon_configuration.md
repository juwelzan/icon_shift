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

## YAML reference

```yaml
default:
  name: Notes
  icon: assets/icons/app.png
  platforms:
    android:
      icon: assets/icons/app_android.png
      adaptive_foreground: assets/icons/fg.png   # 108 dp layer
      monochrome: assets/icons/mono.png          # Android 13 themed icons
    ios:
      dark: assets/icons/app_dark.png            # iOS 18 dark appearance
      tinted: assets/icons/app_tinted.png        # iOS 18 tinted appearance
    linux:
      icon: assets/icons/app.svg                 # SVG allowed here
    web:
      icon: assets/icons/favicon.png

variants:
  dark:   { icon: assets/icons/dark.png, appearance: dark, theme_color: "#121212" }
  blue:   { icon: assets/icons/blue.png }
  green:  { icon: assets/icons/green.png }
  winter: { name: Notes ❄, icon: assets/icons/winter.png }   # seasonal

renamed:
  night: dark          # devices using "night" are moved to "dark"

android:
  adaptive_background: "#FFFFFF"   # enables adaptive icons (and monochrome)
ios:
  background_color: "#FFFFFF"
  primary_icon: false              # true: also regenerate AppIcon.appiconset
macos:   { app_icon: false }
windows: { app_icon: false }
linux:   { icons: false, output_dir: linux/packaging }
web:     { icons: false, maskable_background: "#FFFFFF" }
dart:    { output: lib/icon_shift_config.g.dart }
```

## What gets generated

| Output | Owner | Notes |
| --- | --- | --- |
| `res/mipmap-*/ic_icon_shift_<id>*.png`, `mipmap-anydpi-v26/ic_icon_shift_<id>.xml` | CLI | adaptive XML includes `<monochrome>` when configured |
| `res/values*/icon_shift.xml` | CLI | labels per locale (`values-de`, `values-pt-rBR`, `values-b+zh+Hant`) |
| manifest aliases between markers | CLI | retired aliases for removed/renamed variants |
| `Assets.xcassets/<id>.appiconset` | CLI | `info.author: icon_shift_cli`; light/dark/tinted |
| `AppIcon.appiconset` (iOS/macOS), `app_icon.ico`, `web/icons/*`, `web/favicon.png` | app | only with the opt-in flags; backed up first |
| `linux/packaging/*` | CLI | hicolor icons + `<app-id>.desktop` for your packaging |

## Themed icons — what the OS really does

| Platform | Theme behaviour |
| --- | --- |
| Android 13+ | Shows the monochrome layer tinted by the wallpaper **if the user enabled themed icons**. Apps cannot enable it. |
| iOS 18+ | Picks light/dark/tinted artwork from the icon set by the system appearance. |
| macOS | Uses appearance variants from the asset catalog. |
| Windows, Linux | No themed app icons. |
| Web | A favicon can follow `prefers-color-scheme`; IconShiftThemeSync can switch favicons at runtime. |

None of them switches the launcher icon when your *Flutter* theme changes;
`IconShiftThemeSync` does that explicitly, where supported.

## Validation

* `dart run icon_shift_cli assets --check` — existence, format, square,
  sizes per use, transparency.
* `IconShift.validateConfiguration()` — at runtime: bundled assets, native
  resources (aliases, alternate icons), SVG on desktop.
