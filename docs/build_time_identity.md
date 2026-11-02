# Build-time identity

`icon_shift_cli identity` changes the identity **of the next build** by
editing the native project files. It never modifies an installed app.
Changing an application id, bundle id or Linux app id produces a
**different app** for the OS: it installs next to the old one, cannot read
its data and is not delivered as an update to existing users.

## Configuration

```yaml
# icon_shift.yaml
application:
  display_name: Acme Notes
  version: 2.1.0+7                 # written to pubspec.yaml
  android:
    application_id: com.acme.notes
    namespace: com.acme.notes      # optional; moves Kotlin/Java sources
  ios:
    bundle_id: com.acme.notes
    display_name: Notes            # overrides display_name on iOS
  macos:
    bundle_id: com.acme.notes.mac
  windows:
    binary_name: acme_notes
    company_name: Acme Inc.
    product_name: Acme Notes
    copyright: © Acme Inc.
  linux:
    application_id: com.acme.Notes
    binary_name: acme_notes
  web:
    name: Acme Notes
    short_name: Notes
    description: Take notes
    theme_color: "#0D47A1"
    background_color: "#FFFFFF"

build_profiles:                    # overlays merged over application:
  staging:
    display_name: Acme Notes (Staging)
    android: { application_id: com.acme.notes.staging }
    ios: { bundle_id: com.acme.notes.staging }
```

## Workflow

```bash
dart run icon_shift_cli identity --show                       # current values
dart run icon_shift_cli preview --profile staging             # resolution + diff
dart run icon_shift_cli identity --apply --profile staging -n # dry run with diffs
dart run icon_shift_cli identity --apply --profile staging    # write (backed up)
flutter clean && flutter build apk                             # rebuild
dart run icon_shift_cli identity --reset                       # undo the last apply
```

## What is edited

| Platform | Files | Values |
| --- | --- | --- |
| all | `pubspec.yaml` | `version:` |
| Android | `android/app/build.gradle(.kts)`, `AndroidManifest.xml` (or `strings.xml` when the label is `@string/…`), `src/main/{kotlin,java}/<package>/` | `applicationId`, `namespace` + source move and `package` lines, `<application android:label>` |
| iOS | `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner/Info.plist` | every `PRODUCT_BUNDLE_IDENTIFIER` with the Runner id (tests/extensions keep their suffix), `CFBundleDisplayName` |
| macOS | `macos/Runner/Configs/AppInfo.xcconfig`, `project.pbxproj`, `Info.plist` | `PRODUCT_BUNDLE_IDENTIFIER` (+ test target), `CFBundleName`, `CFBundleDisplayName` |
| Windows | `windows/CMakeLists.txt`, `runner/Runner.rc`, `runner/main.cpp` | `BINARY_NAME`, CompanyName/FileDescription/ProductName/InternalName/OriginalFilename/LegalCopyright, window title |
| Linux | `linux/CMakeLists.txt`, `runner/my_application.cc` | `APPLICATION_ID`, `BINARY_NAME`, header bar / window title |
| Web | `web/manifest.json`, `web/index.html` | name, short_name, description, colors; `<title>`, `apple-mobile-web-app-title` |

Every edit matches an exact pattern from the Flutter template and expects a
fixed number of matches. If a file was customised so that the pattern does
not match, the CLI reports it and changes **nothing** — it does not guess.

## Identifier rules

| Identifier | Rule |
| --- | --- |
| Android applicationId | ≥ 2 segments, each `[A-Za-z][A-Za-z0-9_]*` |
| Android namespace | as above, no Java keywords |
| Apple bundle id | reverse-DNS, `[A-Za-z0-9-]` segments, no `_`, ≤ 155 chars |
| Linux application id | D-Bus name: ≥ 2 segments `[A-Za-z_][A-Za-z0-9_-]*`; warns below 3 segments (Flatpak) or with `-` |
| Windows/Linux binary name | `[A-Za-z0-9_][A-Za-z0-9_.-]*`, ≤ 64, not a reserved device name |
| version | `1.2.3`, optional `-pre`, optional `+build` |

## Backups and rollback

Every write (identity or resources) first copies the affected files to
`.icon_shift/backups/<timestamp>/before/` and afterwards records what it
wrote in `after/`. `rollback` restores a file only if it still matches
`after/` — files you edited since are listed as conflicts (exit code 2) and
left alone unless you pass `--force`. Add `.icon_shift/` to `.gitignore`.

```bash
dart run icon_shift_cli rollback --list
dart run icon_shift_cli rollback            # most recent
dart run icon_shift_cli rollback --id 20261102_221530
```

## Signing, provisioning, notarization

Not handled, on purpose. After changing an Apple bundle id register the App
ID and use a matching provisioning profile in Xcode; macOS builds must be
re-signed and notarized; MSIX `Publisher` must equal your certificate
subject; Android keeps whatever `signingConfig` your Gradle file uses. The CLI
never reads or stores keys or certificates.

## Data migration between identities

| Platform | Can the new app read the old app's data? |
| --- | --- |
| Android | No. Options: the old app ships an export (signature-protected ContentProvider with the same key, or user-driven share/SAF), or sync through a backend. |
| iOS / macOS | Only via an App Group or keychain access group of the same Team that the **old** app already declared. |
| Windows | Unpackaged: files remain in the old `%APPDATA%\<Company>\<Product>` folder; copy them explicitly (with user consent). MSIX: separate package data. |
| Linux | Native: files remain in the old XDG folders; Flatpak: `~/.var/app/<old id>`. |
| Web | Same origin keeps storage; a new manifest `id` only creates a new installed PWA. |

IconShift never deletes or moves user data.
