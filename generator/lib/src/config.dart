import 'package:yaml/yaml.dart';

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

/// Name and icon with per-platform overrides; mirrors `AppIdentity`.
class IdentitySpec {
  IdentitySpec({this.name, this.icon, this.platforms = const {}});

  final String? name;
  final String? icon;
  final Map<String, ({String? name, String? icon})> platforms;
}

/// The effective name and icon of a variant on one platform.
class Resolved {
  Resolved(this.id, this.name, this.icon, this.usesDefaultIcon);
  final String id;
  final String? name;
  final String? icon;
  final bool usesDefaultIcon;
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
  });

  final bool enabled;
  final String assetCatalog;

  /// App Store icons may not have alpha; transparent pixels are flattened
  /// onto this `#RRGGBB` color.
  final String backgroundColor;
  final String projectDir;
}

class GeneratorConfig {
  GeneratorConfig({
    required this.defaultIdentity,
    required this.variants,
    required this.android,
    required this.ios,
    this.dartOutput,
  });

  final IdentitySpec defaultIdentity;
  final Map<String, IdentitySpec> variants;
  final AndroidOptions android;
  final IosOptions ios;

  /// Path of the generated Dart config, or `null` to skip it.
  final String? dartOutput;

  List<String> get variantIds => [defaultVariantId, ...variants.keys];

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
    );
  }

  /// Every icon path referenced anywhere.
  Set<String> get allIcons => {
    for (final spec in [defaultIdentity, ...variants.values]) ...[
      ?spec.icon,
      for (final o in spec.platforms.values) ?o.icon,
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

    final defaultIdentity = _identity(map['default'], 'default');
    final variantsNode = map['variants'];
    final variants = <String, IdentitySpec>{};
    if (variantsNode != null) {
      _map(variantsNode, 'variants').forEach((key, value) {
        final id = key.toString();
        if (id == defaultVariantId) {
          throw ConfigException('"default" is reserved; rename that variant.');
        }
        if (!variantIdPattern.hasMatch(id)) {
          throw ConfigException(
            'Variant id "$id" must match ${variantIdPattern.pattern}.',
          );
        }
        variants[id] = _identity(value, 'variants.$id');
      });
    }

    final android = _optionalMap(map['android'], 'android');
    final ios = _optionalMap(map['ios'], 'ios');
    final dart = _optionalMap(map['dart'], 'dart');

    return GeneratorConfig(
      defaultIdentity: defaultIdentity,
      variants: variants,
      android: AndroidOptions(
        enabled: _bool(android['enabled'], 'android.enabled') ?? true,
        resDir:
            _string(android['res_dir'], 'android.res_dir') ??
            'android/app/src/main/res',
        manifest:
            _string(android['manifest'], 'android.manifest') ??
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
            _string(ios['asset_catalog'], 'ios.asset_catalog') ??
            'ios/Runner/Assets.xcassets',
        backgroundColor:
            _color(ios['background_color'], 'ios.background_color') ??
            '#FFFFFF',
        projectDir: _string(ios['project_dir'], 'ios.project_dir') ?? 'ios',
      ),
      dartOutput: _string(dart['output'], 'dart.output'),
    );
  }

  static IdentitySpec _identity(Object? node, String where) {
    if (node == null) {
      if (where == 'default') {
        throw ConfigException('Missing "default:" identity.');
      }
      return IdentitySpec();
    }
    final map = _map(node, where);
    for (final key in map.keys) {
      if (!const {'name', 'icon', 'platforms'}.contains(key)) {
        throw ConfigException('Unknown key "$where.$key".');
      }
    }
    final platforms = <String, ({String? name, String? icon})>{};
    final platformsNode = map['platforms'];
    if (platformsNode != null) {
      _map(platformsNode, '$where.platforms').forEach((key, value) {
        final p = key.toString();
        if (!platformNames.contains(p)) {
          throw ConfigException(
            'Unknown platform "$where.platforms.$p". Use one of '
            '${platformNames.join(', ')}.',
          );
        }
        final o = _map(value, '$where.platforms.$p');
        for (final k in o.keys) {
          if (k != 'name' && k != 'icon') {
            throw ConfigException('Unknown key "$where.platforms.$p.$k".');
          }
        }
        platforms[p] = (
          name: _string(o['name'], '$where.platforms.$p.name'),
          icon: _string(o['icon'], '$where.platforms.$p.icon'),
        );
      });
    }
    return IdentitySpec(
      name: _string(map['name'], '$where.name'),
      icon: _string(map['icon'], '$where.icon'),
      platforms: platforms,
    );
  }

  static Map<Object?, Object?> _map(Object? node, String where) {
    if (node is! Map) throw ConfigException('"$where" must be a map.');
    return node;
  }

  static Map<Object?, Object?> _optionalMap(Object? node, String where) =>
      node == null ? const {} : _map(node, where);

  static String? _string(Object? node, String where) {
    if (node == null) return null;
    if (node is! String || node.trim().isEmpty) {
      throw ConfigException('"$where" must be a non-empty string.');
    }
    return node;
  }

  static bool? _bool(Object? node, String where) {
    if (node == null) return null;
    if (node is! bool) throw ConfigException('"$where" must be true or false.');
    return node;
  }

  static String? _color(Object? node, String where) {
    final value = _string(node, where);
    if (value != null && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      throw ConfigException('"$where" must be a color like "#1A2B3C".');
    }
    return value;
  }
}
