# icon_shift_generator

Build-time generator for [icon_shift](../README.md). From one
`icon_shift.yaml` it creates:

* Android activity-alias launcher icons (`mipmap-*/ic_icon_shift_<id>.png`,
  optional adaptive icons), labels and the manifest aliases (between
  `<!-- icon_shift:aliases:start/end -->` markers),
* iOS alternate app icon sets (`<id>.appiconset`),
* an optional Dart `const iconShiftConfig`.

```bash
dart run icon_shift_generator --dry-run
dart run icon_shift_generator
dart run icon_shift_generator --check
```

It validates everything before writing anything, never upscales images,
rejects SVG, only touches files it owns and removes stale files it created.
See the main README's "Resource generator" section for the YAML schema.
