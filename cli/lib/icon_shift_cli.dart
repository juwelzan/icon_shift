/// Build-time tooling for the `icon_shift` plugin: resource generation,
/// build-time identity, validation, preview, backups and rollback.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'src/android.dart';
import 'src/config.dart';
import 'src/dart_output.dart';
import 'src/identity.dart';
import 'src/images.dart';
import 'src/ios.dart';
import 'src/plan.dart';
import 'src/platform_icons.dart';
import 'src/property_table.dart';

export 'src/backup.dart' show Backup, backupRoot;
export 'src/config.dart'
    show ConfigException, GeneratorConfig, checkProjectPath;
export 'src/identity.dart'
    show
        BuildIdentity,
        ProjectIdentity,
        androidApplicationIdProblem,
        androidNamespaceProblem,
        appleBundleIdProblem,
        binaryNameProblem,
        linuxApplicationIdProblem,
        planBuildIdentity,
        readProjectIdentity,
        versionProblem;
export 'src/plan.dart' show Level, Message, Plan, lineDiff;
export 'src/property_table.dart' show propertyTable, platforms;
export 'src/remote.dart'
    show RemoteException, RemoteFetch, RemoteResolution, resolveRemote;

/// Thrown when no configuration file exists.
class ConfigNotFoundException extends ConfigException {
  ConfigNotFoundException(super.message);
}

/// Reads the configuration of the Flutter project in [projectDir]: the file
/// at [configPath] if given, else `icon_shift.yaml`, else the `icon_shift:`
/// section of `pubspec.yaml`.
GeneratorConfig loadConfig(String projectDir, {String? configPath}) {
  if (configPath != null) {
    final file = File(
      p.isAbsolute(configPath) ? configPath : p.join(projectDir, configPath),
    );
    if (!file.existsSync()) {
      throw ConfigNotFoundException('Config "$configPath" not found.');
    }
    return GeneratorConfig.parse(file.readAsStringSync());
  }
  final standalone = File(p.join(projectDir, 'icon_shift.yaml'));
  if (standalone.existsSync()) {
    return GeneratorConfig.parse(standalone.readAsStringSync());
  }
  final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
  if (!pubspec.existsSync() ||
      !pubspec.readAsStringSync().contains(
        RegExp(r'^icon_shift:', multiLine: true),
      )) {
    throw ConfigNotFoundException(
      'No icon_shift.yaml (or "icon_shift:" section in pubspec.yaml) in $projectDir.',
    );
  }
  return GeneratorConfig.parse(pubspec.readAsStringSync(), fromPubspec: true);
}

/// Resource generation targets for `generate --platform`.
const resourceTargets = [
  'android',
  'ios',
  'macos',
  'windows',
  'linux',
  'web',
  'dart',
];

/// Validates [config] and computes every resource change. Nothing is
/// written; call [Plan.apply] for that (only when [Plan.hasErrors] is false).
///
/// [only] limits generation to some of [resourceTargets].
Plan plan(String projectDir, GeneratorConfig config, {Set<String>? only}) {
  final result = Plan(projectDir);
  bool wants(String target) => only == null || only.contains(target);

  final (:icons, :svg) = _loadIcons(projectDir, config, result);
  _checkAssetsDeclared(projectDir, config, result);

  if (wants('android') && config.android.enabled) {
    planAndroid(config, result, icons);
  }
  if (wants('ios') && config.ios.enabled) planIos(config, result, icons);
  final outputs = config.outputs;
  final filtered = GeneratorConfig(
    defaultIdentity: config.defaultIdentity,
    variants: config.variants,
    android: config.android,
    ios: config.ios,
    application: config.application,
    outputs: DesktopWebOptions(
      macosAppIcon: outputs.macosAppIcon && wants('macos'),
      macosAssetCatalog: outputs.macosAssetCatalog,
      windowsAppIcon: outputs.windowsAppIcon && wants('windows'),
      windowsIconPath: outputs.windowsIconPath,
      linuxIcons: outputs.linuxIcons && wants('linux'),
      linuxOutputDir: outputs.linuxOutputDir,
      webIcons: outputs.webIcons && wants('web'),
      webDir: outputs.webDir,
      webMaskableBackground: outputs.webMaskableBackground,
    ),
  );
  planPlatformIcons(filtered, result, icons, svg);
  if (wants('dart')) planDart(config, result);

  if (!outputs.macosAppIcon || !outputs.windowsAppIcon || !outputs.webIcons) {
    result.info(
      'macOS, Windows, Linux and web apply Flutter assets at runtime; their '
      'shipped icons are only generated when macos.app_icon, windows.app_icon, '
      'linux.icons or web.icons is enabled.',
    );
  }
  return result;
}

/// Loads every referenced raster image. SVG is accepted only where it can be
/// used as-is (Linux/web overrides); everything else needs a raster source.
({Map<String, SourceIcon> icons, Set<String> svg}) _loadIcons(
  String projectDir,
  GeneratorConfig config,
  Plan plan,
) {
  final svgAllowed = <String>{};
  final rasterNeeded = <String>{};
  for (final spec in [config.defaultIdentity, ...config.variants.values]) {
    if (spec.icon case final icon?) rasterNeeded.add(icon);
    rasterNeeded.addAll(spec.appearances.images);
    spec.platforms.forEach((platform, o) {
      if (o.icon case final icon?) {
        (platform == 'linux' || platform == 'web' ? svgAllowed : rasterNeeded)
            .add(icon);
      }
      rasterNeeded.addAll([
        ?o.monochrome,
        ?o.adaptiveForeground,
        ?o.dark,
        ?o.tinted,
        ?o.clear,
      ]);
    });
  }
  final icons = <String, SourceIcon>{};
  final svg = <String>{};
  for (final path in config.allIcons) {
    final isSvg = p.extension(path).toLowerCase() == '.svg';
    if (isSvg && svgAllowed.contains(path) && !rasterNeeded.contains(path)) {
      if (File(p.join(projectDir, path)).existsSync()) {
        svg.add(path);
      } else {
        plan.error('Icon "$path" does not exist.');
      }
      continue;
    }
    final loaded = loadSourceIcon(projectDir, path);
    if (loaded.error != null) {
      plan.error(loaded.error!);
    } else {
      icons[path] = loaded.icon!;
    }
  }
  return (icons: icons, svg: svg);
}

/// Image checks only (`assets --check`).
Plan checkAssets(String projectDir, GeneratorConfig config) {
  final result = Plan(projectDir);
  final (:icons, :svg) = _loadIcons(projectDir, config, result);
  _checkAssetsDeclared(projectDir, config, result);
  for (final icon in icons.values) {
    final notes = [
      if (icon.size < 1024)
        'below 1024px (iOS, macOS and generated store icons need 1024)',
      if (icon.size < 192) 'below 192px (Android needs 192)',
      if (icon.hasAlpha) 'has transparency (flattened for iOS)',
    ];
    result.info(
      '${icon.path}: ${icon.size}×${icon.size}${notes.isEmpty ? '' : ' — ${notes.join('; ')}'}',
    );
  }
  for (final path in svg) {
    result.info('$path: SVG (used as-is for Linux/web)');
  }
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
  // Only images the runtime uses (icons and their appearances), not
  // native-only layers.
  final runtimeIcons = {
    for (final spec in [config.defaultIdentity, ...config.variants.values]) ...[
      ?spec.icon,
      ...spec.appearances.images,
      for (final o in spec.platforms.values) ...[
        ?o.icon,
        ...o.appearances.images,
      ],
    ],
  };
  for (final icon in runtimeIcons) {
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

/// `doctor`: project-level checks beyond resource validation.
Plan doctor(String projectDir, {String? configPath}) {
  final result = Plan(projectDir);
  final pubspec = File(p.join(projectDir, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    result.error(
      'No pubspec.yaml in $projectDir; run from a Flutter app (or pass --project).',
    );
    return result;
  }
  final pubspecText = pubspec.readAsStringSync();
  if (!pubspecText.contains(RegExp(r'^\s+sdk:\s*flutter', multiLine: true))) {
    result.error('$projectDir is not a Flutter project.');
  }
  if (!pubspecText.contains(RegExp(r'^\s+icon_shift:', multiLine: true))) {
    result.warn(
      'icon_shift is not a dependency in pubspec.yaml; the runtime API will not be available.',
    );
  }
  final present = [
    for (final pl in platforms)
      if (Directory(p.join(projectDir, pl)).existsSync()) pl,
  ];
  result.info(
    'Platforms in this project: ${present.isEmpty ? 'none' : present.join(', ')}.',
  );

  GeneratorConfig? config;
  try {
    config = loadConfig(projectDir, configPath: configPath);
    result.info(
      'Configuration: ${config.variantIds.length} identities (${config.variantIds.join(', ')}).',
    );
  } on ConfigException catch (e) {
    result.error('Configuration: $e');
  }
  if (config != null) {
    // Resource validation, but only for platforms the project has.
    final check = plan(projectDir, config, only: {...present, 'dart'});
    result.messages.addAll(check.messages.where((m) => m.level != Level.info));
    if (!check.isEmpty) {
      result.warn(
        'Generated resources are out of date (${check.touchedPaths.length} file(s)); run `generate`.',
      );
    }
    if (config.application case final identity?) {
      final identityPlan = Plan(projectDir);
      planBuildIdentity(projectDir, identity, identityPlan);
      result.messages.addAll(
        identityPlan.messages.where((m) => m.level == Level.error),
      );
      if (!identityPlan.hasErrors && !identityPlan.isEmpty) {
        result.info(
          'Build identity differs from the project (${identityPlan.touchedPaths.length} file(s)); `identity --apply` would change it.',
        );
      }
    }
  }
  final gitignore = File(p.join(projectDir, '.gitignore'));
  if (!gitignore.existsSync() ||
      !gitignore.readAsStringSync().contains('.icon_shift')) {
    result.warn('Add ".icon_shift/" to .gitignore (it holds local backups).');
  }
  if (!Directory(p.join(projectDir, '.git')).existsSync()) {
    result.info(
      'No git repository detected; IconShift backups are your only undo.',
    );
  }
  return result;
}

/// `preview`: how each variant resolves on each platform, as text.
String preview(GeneratorConfig config, {String? variant}) {
  final ids = variant == null ? config.variantIds : [variant];
  if (variant != null && !config.variantIds.contains(variant)) {
    throw ConfigException(
      'Unknown variant "$variant". Configured: ${config.variantIds.join(', ')}.',
    );
  }
  const runtimeName = {
    'android': 'launcher label',
    'ios': '— (build-time only)',
    'macos': 'window title',
    'windows': 'window title',
    'linux': 'window title',
    'web': 'document.title',
  };
  const runtimeIcon = {
    'android': 'launcher icon',
    'ios': 'launcher icon',
    'macos': 'Dock icon (running)',
    'windows': 'window/taskbar icon',
    'linux': 'window icon (X11)',
    'web': 'favicon',
  };
  final b = StringBuffer();
  for (final id in ids) {
    final spec = id == defaultVariantId
        ? config.defaultIdentity
        : config.variants[id]!;
    b.writeln(
      '$id${spec.appearance == null ? '' : ' (${spec.appearance})'}${spec.themeColor == null ? '' : ' theme ${spec.themeColor}'}',
    );
    for (final pl in platforms) {
      final r = config.resolve(id, pl);
      final names = r.names.isEmpty
          ? ''
          : ' ${r.names.entries.map((e) => '${e.key}:${e.value}').join(', ')}';
      b.writeln(
        '  ${pl.padRight(8)} name: ${r.name ?? '(none)'}$names → ${runtimeName[pl]}',
      );
      final layers = [
        if (r.override?.monochrome != null)
          'monochrome ${r.override!.monochrome}',
        if (r.override?.adaptiveForeground != null)
          'foreground ${r.override!.adaptiveForeground}',
        if (r.appearances.dark case final dark?) 'dark $dark',
        if (r.appearances.tinted case final tinted?) 'tinted $tinted',
        if (r.appearances.clear case final clear?) 'clear $clear',
      ];
      b.writeln(
        '  ${''.padRight(8)} icon: ${r.icon ?? '(none)'}${r.usesDefaultIcon && id != defaultVariantId ? ' (default)' : ''}'
        '${layers.isEmpty ? '' : ' [${layers.join(', ')}]'} → ${runtimeIcon[pl]}',
      );
    }
  }
  if (config.renamed.isNotEmpty) {
    b.writeln(
      'retired: ${config.renamed.entries.map((e) => '${e.key} → ${e.value}').join(', ')}',
    );
  }
  return b.toString();
}

/// `capabilities`: the identity property table as text.
String capabilitiesReport({String? platform}) {
  final selected = platform == null ? platforms : [platform];
  final b = StringBuffer();
  for (final pl in selected) {
    b.writeln(pl);
    propertyTable.forEach((property, byPlatform) {
      final e = byPlatform[pl]!;
      final flags = [
        'runtime: ${e['runtime']}',
        'build-time: ${e['buildTime'] == true ? 'yes' : 'no'}',
        if (e['reinstall'] == true) 'reinstall',
        if (e['resign'] == true) 'new signing identity',
        if (e['dataKept'] == false) 'data NOT kept',
      ];
      b.writeln('  ${property.padRight(16)} ${flags.join(' · ')}');
      b.writeln('  ${''.padRight(16)} ${e['note']}');
    });
  }
  return b.toString();
}
