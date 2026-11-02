import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'config.dart';
import 'images.dart';
import 'ownership.dart';
import 'plan.dart';

const iosIconSize = 1024;
const _buildSettings = [
  'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS',
  'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES',
];

/// Writes one `<variant>.appiconset` per variant with its own iOS icon, with
/// optional dark/tinted appearances. The primary `AppIcon` set is only
/// touched when `ios.primary_icon: true`.
void planIos(GeneratorConfig config, Plan plan, Map<String, SourceIcon> icons) {
  final options = config.ios;
  final catalog = options.assetCatalog;
  final catalogDir = Directory(p.join(plan.projectDir, catalog));
  if (!catalogDir.existsSync()) {
    plan.error(
      'iOS asset catalog "$catalog" not found. Set ios.asset_catalog, or '
      'ios.enabled: false if the app has no iOS target.',
    );
    return;
  }

  final planned = <String>{};
  for (final id in config.variants.keys) {
    final r = config.resolve(id, 'ios');
    if (r.usesDefaultIcon) continue; // Uses the primary icon.
    if (_planIconSet(
      plan,
      options,
      icons,
      r,
      '$catalog/$id.appiconset',
      owned: true,
    )) {
      planned.add('$id.appiconset');
    }
  }

  if (options.primaryIcon) {
    final r = config.resolve(defaultVariantId, 'ios');
    if (r.icon == null) {
      plan.error(
        'ios.primary_icon is true but the default identity has no icon.',
      );
    } else {
      _planIconSet(
        plan,
        options,
        icons,
        r,
        '$catalog/AppIcon.appiconset',
        owned: false,
      );
      plan.info(
        'iOS: AppIcon.appiconset is regenerated from the default icon (backed up before writing).',
      );
    }
  }

  for (final dir in catalogDir.listSync().whereType<Directory>()) {
    final name = p.basename(dir.path);
    if (name.endsWith('.appiconset') &&
        !planned.contains(name) &&
        _isOurs(File(p.join(dir.path, 'Contents.json')))) {
      plan.delete(p.relative(dir.path, from: plan.projectDir));
    }
  }

  if (planned.isNotEmpty &&
      !_hasAlternateIconSetting(plan, options.projectDir)) {
    plan.warn(
      'iOS: alternate icon sets are only bundled when the build setting '
      'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES is set for the '
      'Runner target (Xcode: Build Settings → "Include All App Icon Assets"), '
      'or add it to ${options.projectDir}/Flutter/Debug.xcconfig and '
      'Release.xcconfig.',
    );
  }
}

/// Plans one single-size (Xcode 14+) icon set. [owned] sets are marked with
/// our author so later runs may update or remove them; the primary set is
/// overwritten only on explicit opt-in.
bool _planIconSet(
  Plan plan,
  IosOptions options,
  Map<String, SourceIcon> icons,
  Resolved r,
  String setDir, {
  required bool owned,
}) {
  final contents = File(p.join(plan.projectDir, setDir, 'Contents.json'));
  if (owned && contents.existsSync() && !_isOurs(contents)) {
    plan.error(
      'iOS: "$setDir" exists and was not created by $toolName; refusing to '
      'overwrite it. Rename the variant or remove that set.',
    );
    return false;
  }
  final images = <Map<String, Object>>[];
  var ok = true;
  void add(
    String? source,
    String file, {
    String? appearance,
    bool flattenAlpha = true,
  }) {
    if (source == null) return;
    final icon = icons[source];
    if (icon == null) {
      ok = false;
      return;
    }
    if (icon.size < iosIconSize) {
      plan.error(
        'iOS: "${icon.path}" is ${icon.size}px; iOS needs '
        '$iosIconSize×$iosIconSize. Refusing to upscale.',
      );
      ok = false;
      return;
    }
    var image = resize(icon.image, iosIconSize);
    if (flattenAlpha && icon.hasAlpha) {
      image = flatten(image, options.backgroundColor);
      plan.info(
        'iOS: "${icon.path}" has transparency; flattened onto '
        '${options.backgroundColor} (App Store icons may not contain alpha; '
        'set ios.background_color to change it).',
      );
    }
    plan.write('$setDir/$file', img.encodePng(image));
    images.add({
      if (appearance != null)
        'appearances': [
          {'appearance': 'luminosity', 'value': appearance},
        ],
      'filename': file,
      'idiom': 'universal',
      'platform': 'ios',
      'size': '1024x1024',
    });
  }

  add(r.icon, 'icon_1024.png');
  // Dark artwork keeps its transparency (iOS composites it on a dark
  // background); tinted artwork is a grayscale image.
  add(
    r.override?.dark,
    'icon_1024_dark.png',
    appearance: 'dark',
    flattenAlpha: false,
  );
  add(r.override?.tinted, 'icon_1024_tinted.png', appearance: 'tinted');
  if (!ok) return false;

  plan.writeString(
    '$setDir/Contents.json',
    '${const JsonEncoder.withIndent('  ').convert({
      'images': images,
      'info': {'author': owned ? iosAuthor : 'xcode', 'version': 1},
    })}\n',
  );
  return true;
}

bool _isOurs(File contents) {
  if (!contents.existsSync()) return false;
  try {
    final json = jsonDecode(contents.readAsStringSync()) as Map;
    return isOwnIosAuthor((json['info'] as Map?)?['author']);
  } on Object {
    return false;
  }
}

bool _hasAlternateIconSetting(Plan plan, String projectDir) {
  final root = Directory(p.join(plan.projectDir, projectDir));
  if (!root.existsSync()) return false;
  final flutterDir = Directory(p.join(root.path, 'Flutter'));
  final candidates = [
    File(p.join(root.path, 'Runner.xcodeproj', 'project.pbxproj')),
    if (flutterDir.existsSync())
      ...flutterDir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.xcconfig'),
      ),
  ];
  return candidates.any(
    (f) =>
        f.existsSync() &&
        _buildSettings.any((s) => f.readAsStringSync().contains(s)),
  );
}
