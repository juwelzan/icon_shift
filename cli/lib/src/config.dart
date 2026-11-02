import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'identity.dart';

/// Thrown for an invalid `icon_shift.yaml`.
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => message;
}

const platformNames = ['android', 'ios', 'macos', 'windows', 'linux', 'web'];
const defaultVariantId = 'default';
final variantIdPattern = RegExp(r'^[a-z][a-z0-9_]{0,49}$');
final _localePattern = RegExp(r'^[a-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})*$');
final _colorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Rejects absolute paths and `..` so a config can never make the CLI read
/// or write outside the project.
String checkProjectPath(String value, String where) {
  final normalized = p.posix.normalize(value.replaceAll(r'\', '/'));
  if (p.posix.isAbsolute(normalized) ||
      RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
      normalized == '..' ||
      normalized.startsWith('../')) {
    throw ConfigException(
      '"$where" must be a path inside the project, got "$value".',
    );
  }
  return normalized;
}

/// Per-platform override of an identity.
class OverrideSpec {
  OverrideSpec({
    this.name,
    this.icon,
    this.names = const {},
    this.monochrome,
    this.adaptiveForeground,
    this.dark,
    this.tinted,
  });

  final String? name;
  final String? icon;
  final Map<String, String> names;

  /// Android: monochrome layer for themed icons (API 33+).
  final String? monochrome;

  /// Android: adaptive foreground replacing the inset of [icon].
  final String? adaptiveForeground;

  /// iOS: dark / tinted appearance artwork (iOS 18+).
  final String? dark;
  final String? tinted;

  Iterable<String> get images => [
    ?icon,
    ?monochrome,
    ?adaptiveForeground,
    ?dark,
    ?tinted,
  ];
}

/// Name and icon with per-platform overrides; mirrors `AppIdentity`.
class IdentitySpec {
  IdentitySpec({
    this.name,
    this.icon,
    this.names = const {},
    this.appearance,
    this.themeColor,
    this.platforms = const {},
  });

  final String? name;
  final String? icon;

  /// Localized names keyed by locale (`de`, `pt_BR`).
  final Map<String, String> names;

  /// `light` or `dark`: which system appearance this variant is meant for.
  final String? appearance;

  /// `#RRGGBB`, used for the web theme color.
  final String? themeColor;
  final Map<String, OverrideSpec> platforms;
}

/// The effective name and icon of a variant on one platform.
class Resolved {
  Resolved(
    this.id,
    this.name,
    this.icon,
    this.usesDefaultIcon, {
    this.names = const {},
    this.override,
  });
  final String id;
  final String? name;
  final String? icon;
  final bool usesDefaultIcon;

  /// Localized names, merged with the same precedence as [name].
  final Map<String, String> names;

  /// The variant's own override for the platform, for extra icon layers.
  final OverrideSpec? override;
}

class AndroidOptions {
  AndroidOptions({
    required this.enabled,
    required this.resDir,
    required this.manifest,
    required this.targetActivity,
    this.adaptiveBackground,
  });

  final bool enabled;
  final String resDir;
  final String manifest;
  final String targetActivity;

  /// `#RRGGBB`; when set, adaptive icons are generated as well.
  final String? adaptiveBackground;
}

class IosOptions {
  IosOptions({
    required this.enabled,
    required this.assetCatalog,
    required this.backgroundColor,
    required this.projectDir,
    this.primaryIcon = false,
  });

  final bool enabled;
  final String assetCatalog;

  /// App Store icons may not have alpha; transparent pixels are flattened
  /// onto this `#RRGGBB` color.
  final String backgroundColor;
  final String projectDir;

  /// Also (re)write the primary `AppIcon.appiconset` from the default icon.
  final bool primaryIcon;
}

/// Opt-in icon outputs for platforms whose runtime uses Flutter assets.
class DesktopWebOptions {
  DesktopWebOptions({
    this.macosAppIcon = false,
    this.macosAssetCatalog = 'macos/Runner/Assets.xcassets',
    this.windowsAppIcon = false,
    this.windowsIconPath = 'windows/runner/resources/app_icon.ico',
    this.linuxIcons = false,
    this.linuxOutputDir = 'linux/packaging',
    this.webIcons = false,
    this.webDir = 'web',
    this.webMaskableBackground = '#FFFFFF',
  });

  final bool macosAppIcon;
  final String macosAssetCatalog;
  final bool windowsAppIcon;
  final String windowsIconPath;

  /// hicolor icons and a `.desktop` entry template for packaging.
  final bool linuxIcons;
  final String linuxOutputDir;

  /// favicon, PWA icons and maskable icons, plus the manifest icon list.
  final bool webIcons;
  final String webDir;
  final String webMaskableBackground;
}

class GeneratorConfig {
  GeneratorConfig({
    required this.defaultIdentity,
    required this.variants,
    required this.android,
    required this.ios,
    DesktopWebOptions? outputs,
    this.renamed = const {},
    this.dartOutput,
    this.application,
    this.buildProfiles = const {},
  }) : outputs = outputs ?? DesktopWebOptions();

  final IdentitySpec defaultIdentity;
  final Map<String, IdentitySpec> variants;
  final AndroidOptions android;
  final IosOptions ios;
  final DesktopWebOptions outputs;

  /// Variants that were renamed (`old: new`) or removed (`old: default`).
  /// Android keeps a disabled alias for each so users whose launcher shows
  /// an old variant still have a launcher entry after the update.
  final Map<String, String> renamed;

  /// Path of the generated Dart config, or `null` to skip it.
  final String? dartOutput;

  /// Build-time identity (`application:`), or `null`.
  final BuildIdentity? application;

  /// Named overlays merged over [application] (`build_profiles:`).
  final Map<String, BuildIdentity> buildProfiles;

  List<String> get variantIds => [defaultVariantId, ...variants.keys];

  /// The build identity for [profile] (or the base one when `null`).
  BuildIdentity? buildIdentity([String? profile]) {
    if (profile == null) return application;
    final overlay = buildProfiles[profile];
    if (overlay == null) {
      throw ConfigException(
        'Unknown build profile "$profile". Defined: '
        '${buildProfiles.keys.isEmpty ? 'none' : buildProfiles.keys.join(', ')}.',
      );
    }
    return (application ?? BuildIdentity()).merge(overlay);
  }

  /// Same rules as `IconShiftConfig.resolve` in the plugin.
  Resolved resolve(String id, String platform) {
    final variant = id == defaultVariantId ? null : variants[id];
    final vo = variant?.platforms[platform];
    final dO = defaultIdentity.platforms[platform];
    final ownIcon = vo?.icon ?? variant?.icon;
    return Resolved(
      id,
      vo?.name ?? variant?.name ?? dO?.name ?? defaultIdentity.name,
      ownIcon ?? dO?.icon ?? defaultIdentity.icon,
      ownIcon == null,
      names: {
        ...defaultIdentity.names,
        ...?dO?.names,
        ...?variant?.names,
        ...?vo?.names,
      },
      override: id == defaultVariantId ? dO : vo,
    );
  }

  /// Every image path referenced anywhere.
  Set<String> get allIcons => {
    for (final spec in [defaultIdentity, ...variants.values]) ...[
      ?spec.icon,
      for (final o in spec.platforms.values) ...o.images,
    ],
  };

  static GeneratorConfig parse(String yamlSource, {bool fromPubspec = false}) {
    final Object? doc;
    try {
      doc = loadYaml(yamlSource);
    } on YamlException catch (e) {
      throw ConfigException('Invalid YAML: ${e.message}');
    }
    Object? root = doc;
    if (fromPubspec) {
      root = doc is YamlMap ? doc['icon_shift'] : null;
      if (root == null) {
        throw ConfigException('pubspec.yaml has no "icon_shift:" section.');
      }
    }
    final map = _map(root, 'configuration');
    _allowKeys(map, 'configuration', const {
      'default',
      'variants',
      'renamed',
      'android',
      'ios',
      'macos',
      'windows',
      'linux',
      'web',
      'dart',
      'application',
      'build_profiles',
    });

    final defaultIdentity = _identity(map['default'], 'default');
    final variants = <String, IdentitySpec>{};
    final variantsNode = map['variants'];
    if (variantsNode != null) {
      _map(variantsNode, 'variants').forEach((key, value) {
        final id = key.toString();
        _checkVariantId(id, 'variants');
        variants[id] = _identity(value, 'variants.$id');
      });
    }

    final renamed = <String, String>{};
    final renamedNode = map['renamed'];
    if (renamedNode != null) {
      _map(renamedNode, 'renamed').forEach((key, value) {
        final from = key.toString();
        _checkVariantId(from, 'renamed');
        final to = _string(value, 'renamed.$from')!;
        if (variants.containsKey(from)) {
          throw ConfigException(
            'renamed.$from: "$from" is still a configured variant.',
          );
        }
        if (to != defaultVariantId && !variants.containsKey(to)) {
          throw ConfigException(
            'renamed.$from points to "$to", which is not a variant.',
          );
        }
        renamed[from] = to;
      });
    }

    final android = _optionalMap(map['android'], 'android');
    final ios = _optionalMap(map['ios'], 'ios');
    final macos = _optionalMap(map['macos'], 'macos');
    final windows = _optionalMap(map['windows'], 'windows');
    final linux = _optionalMap(map['linux'], 'linux');
    final web = _optionalMap(map['web'], 'web');
    final dart = _optionalMap(map['dart'], 'dart');
    _allowKeys(android, 'android', const {
      'enabled',
      'res_dir',
      'manifest',
      'target_activity',
      'adaptive_background',
    });
    _allowKeys(ios, 'ios', const {
      'enabled',
      'asset_catalog',
      'background_color',
      'project_dir',
      'primary_icon',
    });
    _allowKeys(macos, 'macos', const {'app_icon', 'asset_catalog'});
    _allowKeys(windows, 'windows', const {'app_icon', 'icon_path'});
    _allowKeys(linux, 'linux', const {'icons', 'output_dir'});
    _allowKeys(web, 'web', const {'icons', 'dir', 'maskable_background'});
    _allowKeys(dart, 'dart', const {'output'});

    final profiles = <String, BuildIdentity>{};
    final profilesNode = map['build_profiles'];
    if (profilesNode != null) {
      _map(profilesNode, 'build_profiles').forEach((key, value) {
        final name = key.toString();
        if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(name)) {
          throw ConfigException(
            'build_profiles: "$name" must be lowercase letters, digits, '
            '"-" or "_".',
          );
        }
        profiles[name] = BuildIdentity.parse(
          _map(value, 'build_profiles.$name'),
          'build_profiles.$name',
        );
      });
    }
    final applicationNode = map['application'];

    return GeneratorConfig(
      defaultIdentity: defaultIdentity,
      variants: variants,
      renamed: renamed,
      android: AndroidOptions(
        enabled: _bool(android['enabled'], 'android.enabled') ?? true,
        resDir:
            _path(android['res_dir'], 'android.res_dir') ??
            'android/app/src/main/res',
        manifest:
            _path(android['manifest'], 'android.manifest') ??
            'android/app/src/main/AndroidManifest.xml',
        targetActivity:
            _string(android['target_activity'], 'android.target_activity') ??
            '.MainActivity',
        adaptiveBackground: _color(
          android['adaptive_background'],
          'android.adaptive_background',
        ),
      ),
      ios: IosOptions(
        enabled: _bool(ios['enabled'], 'ios.enabled') ?? true,
        assetCatalog:
            _path(ios['asset_catalog'], 'ios.asset_catalog') ??
            'ios/Runner/Assets.xcassets',
        backgroundColor:
            _color(ios['background_color'], 'ios.background_color') ??
            '#FFFFFF',
        projectDir: _path(ios['project_dir'], 'ios.project_dir') ?? 'ios',
        primaryIcon: _bool(ios['primary_icon'], 'ios.primary_icon') ?? false,
      ),
      outputs: DesktopWebOptions(
        macosAppIcon: _bool(macos['app_icon'], 'macos.app_icon') ?? false,
        macosAssetCatalog:
            _path(macos['asset_catalog'], 'macos.asset_catalog') ??
            'macos/Runner/Assets.xcassets',
        windowsAppIcon: _bool(windows['app_icon'], 'windows.app_icon') ?? false,
        windowsIconPath:
            _path(windows['icon_path'], 'windows.icon_path') ??
            'windows/runner/resources/app_icon.ico',
        linuxIcons: _bool(linux['icons'], 'linux.icons') ?? false,
        linuxOutputDir:
            _path(linux['output_dir'], 'linux.output_dir') ?? 'linux/packaging',
        webIcons: _bool(web['icons'], 'web.icons') ?? false,
        webDir: _path(web['dir'], 'web.dir') ?? 'web',
        webMaskableBackground:
            _color(web['maskable_background'], 'web.maskable_background') ??
            '#FFFFFF',
      ),
      dartOutput: _path(dart['output'], 'dart.output'),
      application: applicationNode == null
          ? null
          : BuildIdentity.parse(
              _map(applicationNode, 'application'),
              'application',
            ),
      buildProfiles: profiles,
    );
  }

  static void _checkVariantId(String id, String where) {
    if (id == defaultVariantId) {
      throw ConfigException('$where: "default" is reserved; rename it.');
    }
    if (!variantIdPattern.hasMatch(id)) {
      throw ConfigException(
        '$where: variant id "$id" must match ${variantIdPattern.pattern}.',
      );
    }
  }

  static IdentitySpec _identity(Object? node, String where) {
    if (node == null) {
      if (where == 'default') {
        throw ConfigException('Missing "default:" identity.');
      }
      return IdentitySpec();
    }
    final map = _map(node, where);
    _allowKeys(map, where, const {
      'name',
      'icon',
      'names',
      'appearance',
      'theme_color',
      'platforms',
    });
    final appearance = _string(map['appearance'], '$where.appearance');
    if (appearance != null && appearance != 'light' && appearance != 'dark') {
      throw ConfigException('"$where.appearance" must be "light" or "dark".');
    }
    final platforms = <String, OverrideSpec>{};
    final platformsNode = map['platforms'];
    if (platformsNode != null) {
      _map(platformsNode, '$where.platforms').forEach((key, value) {
        final platform = key.toString();
        final at = '$where.platforms.$platform';
        if (!platformNames.contains(platform)) {
          throw ConfigException(
            'Unknown platform "$at". Use one of ${platformNames.join(', ')}.',
          );
        }
        final o = _map(value, at);
        _allowKeys(o, at, {
          'name',
          'icon',
          'names',
          if (platform == 'android') ...['monochrome', 'adaptive_foreground'],
          if (platform == 'ios') ...['dark', 'tinted'],
        });
        platforms[platform] = OverrideSpec(
          name: _name(o['name'], '$at.name'),
          icon: _path(o['icon'], '$at.icon'),
          names: _names(o['names'], '$at.names'),
          monochrome: _path(o['monochrome'], '$at.monochrome'),
          adaptiveForeground: _path(
            o['adaptive_foreground'],
            '$at.adaptive_foreground',
          ),
          dark: _path(o['dark'], '$at.dark'),
          tinted: _path(o['tinted'], '$at.tinted'),
        );
      });
    }
    return IdentitySpec(
      name: _name(map['name'], '$where.name'),
      icon: _path(map['icon'], '$where.icon'),
      names: _names(map['names'], '$where.names'),
      appearance: appearance,
      themeColor: _color(map['theme_color'], '$where.theme_color'),
      platforms: platforms,
    );
  }

  static Map<String, String> _names(Object? node, String where) {
    if (node == null) return const {};
    final names = <String, String>{};
    _map(node, where).forEach((key, value) {
      final locale = key.toString();
      if (!_localePattern.hasMatch(locale)) {
        throw ConfigException(
          '"$where.$locale" is not a locale like "de" or "pt_BR".',
        );
      }
      names[locale.replaceAll('-', '_')] = _name(value, '$where.$locale')!;
    });
    return names;
  }

  static String? _name(Object? node, String where) {
    final value = _string(node, where);
    if (value == null) return null;
    if (RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
      throw ConfigException('"$where" must not contain control characters.');
    }
    if (value.length > 255) {
      throw ConfigException('"$where" is longer than 255 characters.');
    }
    return value;
  }
}

Map<Object?, Object?> _map(Object? node, String where) {
  if (node is! Map) throw ConfigException('"$where" must be a map.');
  return node;
}

Map<Object?, Object?> _optionalMap(Object? node, String where) =>
    node == null ? const {} : _map(node, where);

void _allowKeys(Map<Object?, Object?> map, String where, Set<String> allowed) {
  for (final key in map.keys) {
    if (!allowed.contains(key)) {
      throw ConfigException(
        'Unknown key "$where.$key". Allowed: ${allowed.join(', ')}.',
      );
    }
  }
}

String? _string(Object? node, String where) {
  if (node == null) return null;
  if (node is! String || node.trim().isEmpty) {
    throw ConfigException('"$where" must be a non-empty string.');
  }
  return node;
}

String? _path(Object? node, String where) {
  final value = _string(node, where);
  return value == null ? null : checkProjectPath(value, where);
}

bool? _bool(Object? node, String where) {
  if (node == null) return null;
  if (node is! bool) throw ConfigException('"$where" must be true or false.');
  return node;
}

String? _color(Object? node, String where) {
  final value = _string(node, where);
  if (value != null && !_colorPattern.hasMatch(value)) {
    throw ConfigException('"$where" must be a color like "#1A2B3C".');
  }
  return value;
}

/// Shared YAML helpers for other config sections.
abstract final class YamlFields {
  static Map<Object?, Object?> map(Object? node, String where) =>
      _map(node, where);
  static Map<Object?, Object?> optionalMap(Object? node, String where) =>
      _optionalMap(node, where);
  static void allowKeys(
    Map<Object?, Object?> map,
    String where,
    Set<String> allowed,
  ) => _allowKeys(map, where, allowed);
  static String? string(Object? node, String where) => _string(node, where);
  static String? color(Object? node, String where) => _color(node, where);
}
