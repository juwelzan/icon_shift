/// Build-time resource generator for the `icon_shift` plugin.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'src/android.dart';
import 'src/config.dart';
import 'src/dart_output.dart';
import 'src/images.dart';
import 'src/ios.dart';
import 'src/plan.dart';

export 'src/config.dart' show ConfigException, GeneratorConfig;
export 'src/plan.dart' show Level, Message, Plan;

/// Reads the configuration of the Flutter project in [projectDir]: the file
/// at [configPath] if given, else `icon_shift.yaml`, else the `icon_shift:`
/// section of `pubspec.yaml`.
GeneratorConfig loadConfig(String projectDir, {String? configPath}) {
  if (configPath != null) {
    final file = File(
      p.isAbsolute(configPath) ? configPath : p.join(projectDir, configPath),
    );
    if (!file.existsSync()) {
      throw ConfigException('Config "$configPath" not found.');
    }
    return GeneratorConfig.parse(file.readAsStringSync());
  }
  final standalone = File(p.join(projectDir, 'icon_shift.yaml'));
  if (standalone.existsSync()) {
    return GeneratorConfig.parse(standalone.readAsStringSync());
  }
  final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw ConfigException('No icon_shift.yaml or pubspec.yaml in $projectDir.');
  }
  return GeneratorConfig.parse(pubspec.readAsStringSync(), fromPubspec: true);
}

/// Validates [config] and computes every file change. Nothing is written;
/// call [Plan.apply] for that (only when [Plan.hasErrors] is false).
Plan plan(String projectDir, GeneratorConfig config) {
  final result = Plan(projectDir);

  final icons = <String, SourceIcon>{};
  for (final path in config.allIcons) {
    final loaded = loadSourceIcon(projectDir, path);
    if (loaded.error != null) {
      result.error(loaded.error!);
    } else {
      icons[path] = loaded.icon!;
    }
  }
  _checkAssetsDeclared(projectDir, config, result);

  if (config.android.enabled) planAndroid(config, result, icons);
  if (config.ios.enabled) planIos(config, result, icons);
  planDart(config, result);

  result.info(
    'macOS, Windows, Linux and web use the Flutter assets directly at '
    'runtime; no native resources are generated for them.',
  );
  return result;
}

void _checkAssetsDeclared(
  String projectDir,
  GeneratorConfig config,
  Plan plan,
) {
  final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return;
  final Object? doc;
  try {
    doc = loadYaml(pubspec.readAsStringSync());
  } on YamlException {
    return;
  }
  final flutter = doc is YamlMap ? doc['flutter'] : null;
  final assets = [
    for (final entry
        in (flutter is YamlMap ? flutter['assets'] : null) ?? const [])
      if (entry is String) entry else if (entry is YamlMap) '${entry['path']}',
  ];
  for (final icon in config.allIcons) {
    final declared = assets.any(
      (a) =>
          a == icon ||
          (a.endsWith('/') &&
              p.posix.dirname(icon) == a.substring(0, a.length - 1)),
    );
    if (!declared) {
      plan.warn(
        '"$icon" is not listed under flutter > assets in pubspec.yaml; '
        'IconShift needs it at runtime for previews, desktop and web.',
      );
    }
  }
}
