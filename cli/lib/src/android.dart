import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'config.dart';
import 'images.dart';
import 'ownership.dart';
import 'plan.dart';

/// Generated mipmaps are named `ic_icon_shift_<variant>`; anything else in
/// `res/` belongs to the app and is never touched.
const androidResourcePrefix = 'ic_icon_shift_';
const androidValuesFile = 'values/icon_shift.xml';
const manifestStartMarker = '<!-- icon_shift:aliases:start -->';
const manifestEndMarker = '<!-- icon_shift:aliases:end -->';
const minAndroidSourceSize = 192;

const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

void planAndroid(
  GeneratorConfig config,
  Plan plan,
  Map<String, SourceIcon> icons,
) {
  final options = config.android;
  final resDir = options.resDir;
  if (!Directory(p.join(plan.projectDir, resDir)).existsSync()) {
    plan.error(
      'Android resource folder "$resDir" not found. Set android.res_dir, or '
      'android.enabled: false if the app has no Android target.',
    );
    return;
  }

  // Mipmap resource per variant; null keeps the application's own icon.
  final iconResource = <String, String?>{};
  final layers = <String, Resolved>{}; // resource name -> resolved variant
  for (final id in config.variantIds) {
    final r = config.resolve(id, 'android');
    final hasOwnLayers =
        r.override?.monochrome != null ||
        r.override?.adaptiveForeground != null;
    if (r.icon == null) {
      iconResource[id] = null;
    } else if (id != defaultVariantId && r.usesDefaultIcon && !hasOwnLayers) {
      iconResource[id] = iconResource[defaultVariantId];
    } else {
      final name = '$androidResourcePrefix$id';
      iconResource[id] = name;
      layers[name] = r;
    }
  }

  final owned = <String>{};
  final adaptive = options.adaptiveBackground;
  for (final MapEntry(key: name, value: r) in layers.entries) {
    final icon = icons[r.icon!];
    if (icon == null) continue; // Load error already reported.
    if (icon.size < minAndroidSourceSize) {
      plan.error(
        'Android: "${r.icon}" is ${icon.size}px; at least '
        '${minAndroidSourceSize}px is needed for xxxhdpi (512px+ '
        'recommended). Refusing to upscale.',
      );
      continue;
    }
    final foregroundSource = r.override?.adaptiveForeground;
    final monochromeSource = r.override?.monochrome;
    if (adaptive == null &&
        (foregroundSource != null || monochromeSource != null)) {
      plan.error(
        'Android: variant "${r.id}" sets adaptive_foreground/monochrome, which '
        'are adaptive-icon layers; set android.adaptive_background too.',
      );
      continue;
    }
    // Explicit layers are full 108dp artwork; the plain icon is inset to
    // the 72dp visible area.
    final foreground = foregroundSource == null
        ? null
        : icons[foregroundSource];
    final monochrome = monochromeSource == null
        ? null
        : icons[monochromeSource];
    for (final layer in [foreground, monochrome]) {
      if (layer != null && layer.size < 432) {
        plan.error(
          'Android: "${layer.path}" is ${layer.size}px; adaptive layers need '
          '432px (108dp at xxxhdpi). Refusing to upscale.',
        );
      }
    }
    for (final MapEntry(key: density, value: factor) in _densities.entries) {
      final legacy = '$resDir/mipmap-$density/$name.png';
      plan.write(
        legacy,
        img.encodePng(resize(icon.image, (48 * factor).round())),
      );
      owned.add(legacy);
      if (adaptive == null) continue;
      final layerSize = (108 * factor).round();
      final fg = '$resDir/mipmap-$density/${name}_foreground.png';
      plan.write(
        fg,
        img.encodePng(
          foreground != null
              ? resize(foreground.image, layerSize)
              : inset(icon.image, layerSize, (72 * factor).round()),
        ),
      );
      owned.add(fg);
      if (monochrome != null) {
        final mono = '$resDir/mipmap-$density/${name}_monochrome.png';
        plan.write(mono, img.encodePng(resize(monochrome.image, layerSize)));
        owned.add(mono);
      }
    }
    if (adaptive != null) {
      final xml = '$resDir/mipmap-anydpi-v26/$name.xml';
      plan.writeString(xml, '''
<?xml version="1.0" encoding="utf-8"?>
<!-- $generatedMarker. Do not edit. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/icon_shift_adaptive_background" />
    <foreground android:drawable="@mipmap/${name}_foreground" />
${monochrome == null ? '' : '    <monochrome android:drawable="@mipmap/${name}_monochrome" />\n'}</adaptive-icon>
''');
      owned.add(xml);
    }
  }

  _planValues(config, plan, resDir, adaptive);
  _planStaleCleanup(plan, resDir, owned);
  _planManifest(config, plan, iconResource);
}

void _planValues(
  GeneratorConfig config,
  Plan plan,
  String resDir,
  String? adaptiveBackground,
) {
  final locales = <String>{
    for (final id in config.variantIds)
      ...config.resolve(id, 'android').names.keys,
  };
  final owned = <String>{};
  for (final locale in [null, ...locales]) {
    final folder = locale == null
        ? 'values'
        : 'values-${androidLocaleQualifier(locale)}';
    final path = '$resDir/$folder/icon_shift.xml';
    final existing = File(p.join(plan.projectDir, path));
    if (existing.existsSync() &&
        !hasGeneratedMarker(existing.readAsStringSync())) {
      plan.error(
        'Android: "$path" exists and was not created by $toolName; '
        'refusing to overwrite it.',
      );
      continue;
    }
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln('<!-- $generatedMarker. Do not edit. -->')
      ..writeln('<resources>');
    for (final id in config.variantIds) {
      final r = config.resolve(id, 'android');
      final name = locale == null ? r.name : _localized(r.names, locale);
      if (name != null) {
        b.writeln(
          '    <string name="icon_shift_label_$id">${androidString(name)}</string>',
        );
      }
    }
    if (locale == null && adaptiveBackground != null) {
      b.writeln(
        '    <color name="icon_shift_adaptive_background">'
        '$adaptiveBackground</color>',
      );
    }
    b.writeln('</resources>');
    plan.writeString(path, b.toString());
    owned.add(path);
  }
  // Localized label files of locales that are no longer configured.
  final res = Directory(p.join(plan.projectDir, resDir));
  for (final dir in res.listSync().whereType<Directory>()) {
    if (!p.basename(dir.path).startsWith('values-')) continue;
    final file = File(p.join(dir.path, 'icon_shift.xml'));
    final rel = p.posix.joinAll(
      p.split(p.relative(file.path, from: plan.projectDir)),
    );
    if (file.existsSync() &&
        !owned.contains(rel) &&
        hasGeneratedMarker(file.readAsStringSync())) {
      plan.delete(rel);
    }
  }
}

/// Exact locale first, then its language (`pt_BR` → `pt`).
String? _localized(Map<String, String> names, String locale) =>
    names[locale] ?? names[locale.split('_').first];

/// `de` → `de`, `pt_BR` → `pt-rBR`, `zh_Hant` → `b+zh+Hant`.
String androidLocaleQualifier(String locale) {
  final parts = locale.split('_');
  if (parts.length == 1) return parts.first;
  if (parts.length == 2 && RegExp(r'^[A-Z]{2}$').hasMatch(parts[1])) {
    return '${parts[0]}-r${parts[1]}';
  }
  return 'b+${parts.join('+')}';
}

/// Removes generated files of variants that no longer exist.
void _planStaleCleanup(Plan plan, String resDir, Set<String> owned) {
  final res = Directory(p.join(plan.projectDir, resDir));
  for (final dir in res.listSync().whereType<Directory>()) {
    if (!p.basename(dir.path).startsWith('mipmap-')) continue;
    for (final file in dir.listSync().whereType<File>()) {
      final base = p.basename(file.path);
      final relative = p.relative(file.path, from: plan.projectDir);
      if (base.startsWith(androidResourcePrefix) &&
          !owned.contains(p.posix.joinAll(p.split(relative)))) {
        plan.delete(relative);
      }
    }
  }
}

void _planManifest(
  GeneratorConfig config,
  Plan plan,
  Map<String, String?> iconResource,
) {
  final options = config.android;
  final manifestPath = options.manifest;
  final manifestFile = File(p.join(plan.projectDir, manifestPath));
  if (!manifestFile.existsSync()) {
    plan.error('Android manifest "$manifestPath" not found.');
    return;
  }
  final manifest = manifestFile.readAsStringSync();
  final retired = _retiredVariants(config, manifest, plan);

  final b = StringBuffer()
    ..writeln(manifestStartMarker)
    ..writeln(
      '        <!-- $generatedMarker. Do not edit between these markers. -->',
    );
  for (final id in [...config.variantIds, ...retired.keys]) {
    final retiredTo = retired[id];
    final source = retiredTo ?? id;
    final icon = iconResource[source];
    final hasLabel = config.resolve(source, 'android').name != null;
    if (retiredTo != null) {
      b.writeln(
        '        <!-- Retired variant "$id": kept disabled so devices that still '
        'show it keep a launcher entry; IconShift moves them to "$retiredTo". -->',
      );
    }
    b
      ..writeln('        <activity-alias')
      ..writeln('            android:name=".IconShiftAlias_$id"')
      ..writeln(
        '            android:targetActivity="${options.targetActivity}"',
      )
      ..writeln('            android:enabled="${id == defaultVariantId}"')
      ..writeln('            android:exported="true"');
    if (icon != null) b.writeln('            android:icon="@mipmap/$icon"');
    if (hasLabel) {
      b.writeln('            android:label="@string/icon_shift_label_$source"');
    }
    b
      ..writeln('            >')
      ..writeln('            <intent-filter>')
      ..writeln(
        '                <action android:name="android.intent.action.MAIN" />',
      )
      ..writeln(
        '                <category android:name="android.intent.category.LAUNCHER" />',
      )
      ..writeln('            </intent-filter>')
      ..writeln(
        '            <meta-data android:name="icon_shift.variant" android:value="$id" />',
      );
    if (retiredTo != null) {
      b.writeln(
        '            <meta-data android:name="icon_shift.retired_to" android:value="$retiredTo" />',
      );
    }
    b.writeln('        </activity-alias>');
  }
  b.write('        $manifestEndMarker');
  final snippet = b.toString();
  final start = manifest.indexOf(manifestStartMarker);
  final end = manifest.indexOf(manifestEndMarker);
  if (start >= 0 && end > start) {
    plan.writeString(
      manifestPath,
      manifest.replaceRange(start, end + manifestEndMarker.length, snippet),
    );
  } else {
    const snippetPath = 'build/icon_shift/AndroidManifest.snippet.xml';
    plan.writeString(snippetPath, '        $snippet\n');
    plan.warn(
      'Android: $manifestPath has no IconShift markers, so it was not '
      'changed. Paste $snippetPath inside <application> (it includes the '
      'markers, so later runs update it in place).',
    );
  }

  final filter = _launcherFilter(manifest, options.targetActivity);
  const toolingFilter = '''
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
                <data android:scheme="icon-shift-tooling"/>
            </intent-filter>''';
  if (filter == _LauncherFilter.visible) {
    plan.warn(
      'Android: ${options.targetActivity} has a MAIN/LAUNCHER intent-filter, '
      'so the launcher shows a second entry next to the IconShift alias. '
      'Add a <data android:scheme="icon-shift-tooling"/> element to that '
      'intent-filter: launchers then ignore it, while `flutter run` still '
      'finds the activity. The generator does not edit your activity.',
    );
  } else if (filter == _LauncherFilter.none) {
    plan.warn(
      'Android: ${options.targetActivity} has no MAIN/LAUNCHER intent-filter. '
      '`flutter run` only looks for launch activities on <activity> elements, '
      'not aliases; add this inside the activity (the <data> element keeps '
      'it out of the launcher):\n$toolingFilter',
    );
  }
}

/// Variants that must keep a (disabled) alias: everything in `renamed:`, plus
/// aliases found in the current manifest whose variant was removed.
Map<String, String> _retiredVariants(
  GeneratorConfig config,
  String manifest,
  Plan plan,
) {
  final retired = {...config.renamed};
  final start = manifest.indexOf(manifestStartMarker);
  final end = manifest.indexOf(manifestEndMarker);
  if (start >= 0 && end > start) {
    final region = manifest.substring(start, end);
    final ids = RegExp(
      r'<meta-data android:name="icon_shift\.variant" android:value="([a-z0-9_]+)"',
    ).allMatches(region).map((m) => m.group(1)!);
    for (final id in ids) {
      if (id == defaultVariantId || config.variants.containsKey(id)) continue;
      if (!retired.containsKey(id)) {
        retired[id] = defaultVariantId;
        plan.warn(
          'Android: variant "$id" was removed. Its alias is kept (disabled, '
          'pointing to "default") because devices that use it would otherwise '
          'lose their launcher entry after the update. Add "renamed: {$id: '
          '<variant>}" to send them elsewhere.',
        );
      }
    }
  }
  return retired;
}

enum _LauncherFilter { none, visible, toolingOnly }

/// Classifies the MAIN/LAUNCHER intent-filters of [activity]. A filter with a
/// `<data>` element never matches the launcher's query (an intent without
/// data), so it is "tooling only".
_LauncherFilter _launcherFilter(String manifest, String activity) {
  final simple = activity.startsWith('.')
      ? activity
      : '.${activity.split('.').last}';
  final elements = RegExp(r'<activity\b(?:[^>]*/>|[^>]*>[\s\S]*?</activity>)');
  final filters = RegExp(r'<intent-filter\b[\s\S]*?</intent-filter>');
  var result = _LauncherFilter.none;
  for (final match in elements.allMatches(manifest)) {
    final element = match.group(0)!;
    final name = RegExp(
      r'android:name="([^"]+)"',
    ).firstMatch(element)?.group(1);
    if (name == null || !(name == activity || name.endsWith(simple))) continue;
    for (final f in filters.allMatches(element)) {
      final filter = f.group(0)!;
      if (!filter.contains('android.intent.action.MAIN') ||
          !filter.contains('android.intent.category.LAUNCHER')) {
        continue;
      }
      if (!filter.contains('<data')) return _LauncherFilter.visible;
      result = _LauncherFilter.toolingOnly;
    }
  }
  return result;
}

/// Escapes [value] for an Android string resource.
String androidString(String value) {
  var escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", r"\'")
      .replaceAll('"', r'\"');
  if (escaped.startsWith('@') || escaped.startsWith('?')) {
    escaped = '\\$escaped';
  }
  return escaped;
}
