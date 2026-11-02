import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'config.dart';
import 'images.dart';
import 'plan.dart';

const iosAuthor = 'icon_shift_generator';
const iosIconSize = 1024;
const _buildSettings = [
  'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS',
  'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES',
];

/// Writes one `<variant>.appiconset` per variant with its own iOS icon. The
/// primary `AppIcon` set is never touched.
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
    final icon = icons[r.icon!];
    if (icon == null) continue;
    if (icon.size < iosIconSize) {
      plan.error(
        'iOS: "${icon.path}" is ${icon.size}px; iOS needs '
        '$iosIconSize×$iosIconSize. Refusing to upscale.',
      );
      continue;
    }
    final setDir = '$catalog/$id.appiconset';
    final contents = File(p.join(plan.projectDir, setDir, 'Contents.json'));
    if (contents.existsSync() && !_isOurs(contents)) {
      plan.error(
        'iOS: "$setDir" exists and was not created by icon_shift_generator; '
        'refusing to overwrite it. Rename the variant or remove that set.',
      );
      continue;
    }
    var image = resize(icon.image, iosIconSize);
    if (icon.hasAlpha) {
      image = flatten(image, options.backgroundColor);
      plan.info(
        'iOS: "${icon.path}" has transparency; flattened onto '
        '${options.backgroundColor} (App Store icons may not contain alpha; '
        'set ios.background_color to change it).',
      );
    }
    plan.write('$setDir/icon_1024.png', img.encodePng(image));
    plan.writeString(
      '$setDir/Contents.json',
      '${const JsonEncoder.withIndent('  ').convert({
        'images': [
          {'filename': 'icon_1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'},
        ],
        'info': {'author': iosAuthor, 'version': 1},
      })}\n',
    );
    planned.add('$id.appiconset');
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

bool _isOurs(File contents) {
  if (!contents.existsSync()) return false;
  try {
    final json = jsonDecode(contents.readAsStringSync()) as Map;
    return (json['info'] as Map?)?['author'] == iosAuthor;
  } on Object {
    return false;
  }
}

bool _hasAlternateIconSetting(Plan plan, String projectDir) {
  final root = Directory(p.join(plan.projectDir, projectDir));
  if (!root.existsSync()) return false;
  final candidates = [
    File(p.join(root.path, 'Runner.xcodeproj', 'project.pbxproj')),
    ...Directory(p.join(root.path, 'Flutter')).existsSync()
        ? Directory(p.join(root.path, 'Flutter'))
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.xcconfig'))
        : const <File>[],
  ];
  return candidates.any(
    (f) =>
        f.existsSync() &&
        _buildSettings.any((s) => f.readAsStringSync().contains(s)),
  );
}
