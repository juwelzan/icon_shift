# Troubleshooting

The display name does not change: see
[icon configuration](icon_configuration.md#the-name-did-not-change).

Start with `dart run icon_shift_cli doctor` and, in the app,
`print((await IconShift.getDiagnostics()).toReport())`.

| Symptom | Cause / fix |
| --- | --- |
| `flutter run`: "package identifier or launch activity not found" | `MainActivity` has no MAIN/LAUNCHER intent-filter. Add the tooling filter with `<data android:scheme="icon-shift-tooling"/>`. |
| Two launcher icons (Android) | `duplicate_launcher`: the MAIN/LAUNCHER filter on `MainActivity` lacks the `<data>` element. `multiple_aliases_enabled`: more than one alias has `android:enabled="true"`; only `default` should. |
| `missingNativeResource` on Android | No alias with `icon_shift.variant="<id>"`. Run `icon_shift_cli generate` and rebuild. |
| App icon disappeared after an update (Android) | An update removed the alias the device used. Keep `renamed:` entries; the CLI keeps retired aliases automatically when it sees a removed variant in the manifest, and the plugin restores a launcher entry at startup. |
| Icon does not change for a few seconds (Android) | Launcher cache; some OEM launchers need a restart. |
| `missingNativeResource` / `missing_alternate_icon` on iOS | Icon set not bundled. Name it like the variant and set `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`; rebuild. |
| `appNotActive` on iOS | Call while the app is in the foreground. |
| iOS shows an alert after each change | System behaviour; cannot be suppressed. IconShift skips re-applying the current icon. |
| iOS name `buildRequired` | iOS has no runtime rename. Set `application.display_name` and run `identity --apply`. |
| Linux icon "unsupported" | Wayland session; compositors use the `.desktop` icon. Package the generated `linux/packaging/` files. |
| Web title reverts | `MaterialApp(title:)` rebuilt; bind it to `getCurrentIdentity().nativeDisplayName`. |
| Web favicon not updating in Safari | Safari's dynamic favicon support is inconsistent. |
| Installed PWA keeps the old name/icon | Browsers refresh `manifest.json` on their own schedule; it is never per-user. |
| `MissingPluginException` | Rebuild fully after adding the plugin; hot restart is not enough. |
| `missing_asset` | The image is not under `flutter: assets:` in pubspec.yaml. |
| CLI: "expected 1 occurrence(s) of …" | The file differs from the Flutter template; make that change by hand (the CLI changes nothing rather than guess). |
| CLI: "refusing to overwrite" | A file with the generated name exists but was not created by the CLI. Rename the variant or remove the file. |
| `rollback` exit code 2 | Files were edited after the backup; they are listed and left alone. Use `--force` to overwrite them. |
| `dart run icon_shift_cli` "Crash when compiling" | Dart 3.13.4 precompile bug with `package:image`; run `dart run <path>/bin/icon_shift_cli.dart`. |
| Windows: old data gone after renaming | `path_provider` folders follow CompanyName/ProductName; copy data from the old folder. |
| New bundle id/applicationId does not update the installed app | Expected: a new id is a new app. Keep the old id for updates. |
