import '../config/app_identity.dart';
import '../config/icon_shift_config.dart';
import '../config/platform.dart';
import '../models/validation.dart';

/// Valid variant ids. Lowercase so ids can be used unchanged as Android
/// resource names and iOS alternate icon names.
final RegExp variantIdPattern = RegExp(r'^[a-z][a-z0-9_]{0,49}$');

const int maxDisplayNameLength = 255;

/// Launchers commonly truncate labels longer than this.
const int _longNameHint = 30;

const Set<String> _imageExtensions = {
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
  'ico',
  'svg',
};

/// Platforms whose runtime icon is decoded natively from the asset bytes.
const Set<IconShiftPlatform> _rasterOnlyPlatforms = {
  IconShiftPlatform.macos,
  IconShiftPlatform.windows,
  IconShiftPlatform.linux,
};

/// Returns why [name] is not a usable display name, or `null` if it is.
String? displayNameProblem(String name) {
  if (name.trim().isEmpty) return 'Display name must not be empty.';
  if (name.length > maxDisplayNameLength) {
    return 'Display name is longer than $maxDisplayNameLength characters.';
  }
  if (RegExp(r'[\u0000-\u001F\u007F]').hasMatch(name)) {
    return 'Display name must not contain control characters '
        '(newlines, tabs, …).';
  }
  return null;
}

/// Checks [config] without touching assets or native code.
///
/// Asset existence and native resources are checked by
/// [IconShift.validateConfiguration].
IconShiftValidationResult validateConfig(IconShiftConfig config) {
  final issues = <ValidationIssue>[];
  const defaultId = IconShiftConfig.defaultVariantId;

  void add(
    ValidationSeverity severity,
    String code,
    String message, {
    String? variantId,
    IconShiftPlatform? platform,
  }) {
    issues.add(
      ValidationIssue(
        severity: severity,
        code: code,
        message: message,
        variantId: variantId,
        platform: platform,
      ),
    );
  }

  void checkName(String? name, String variantId, IconShiftPlatform? platform) {
    if (name == null) return;
    final problem = displayNameProblem(name);
    if (problem != null) {
      add(
        ValidationSeverity.error,
        'invalid_display_name',
        '$problem Got "$name".',
        variantId: variantId,
        platform: platform,
      );
    } else if (name.length > _longNameHint) {
      add(
        ValidationSeverity.info,
        'long_display_name',
        'Display name "$name" is longer than $_longNameHint characters and '
            'may be truncated by launchers.',
        variantId: variantId,
        platform: platform,
      );
    }
  }

  void checkIcon(AppIcon? icon, String variantId, IconShiftPlatform? platform) {
    if (icon == null) return;
    if (icon.path.trim().isEmpty) {
      add(
        ValidationSeverity.error,
        'invalid_icon_path',
        'Icon asset path is empty.',
        variantId: variantId,
        platform: platform,
      );
      return;
    }
    final dot = icon.path.lastIndexOf('.');
    final ext = dot < 0 ? '' : icon.path.substring(dot + 1).toLowerCase();
    if (!_imageExtensions.contains(ext)) {
      add(
        ValidationSeverity.error,
        'invalid_icon_path',
        'Icon "${icon.path}" is not an image file. Supported: '
            '${_imageExtensions.join(', ')}.',
        variantId: variantId,
        platform: platform,
      );
    }
  }

  void checkIdentity(String variantId, AppIdentity identity) {
    checkName(identity.name, variantId, null);
    checkIcon(identity.icon, variantId, null);
    identity.platforms.forEach((platform, override) {
      if (override.isEmpty) {
        add(
          ValidationSeverity.warning,
          'empty_override',
          'Override for ${platform.name} sets neither name nor icon; '
              'remove it.',
          variantId: variantId,
          platform: platform,
        );
      }
      checkName(override.name, variantId, platform);
      checkIcon(override.icon, variantId, platform);
      if (platform == IconShiftPlatform.ios && override.name != null) {
        add(
          ValidationSeverity.info,
          'name_not_switchable',
          'iOS cannot change the display name at runtime; this name is '
              'only used for previews and metadata.',
          variantId: variantId,
          platform: platform,
        );
      }
    });
  }

  checkIdentity(defaultId, config.defaultIdentity);
  if (config.defaultIdentity.name == null) {
    add(
      ValidationSeverity.warning,
      'missing_default_name',
      'defaultIdentity has no name. Variants without a name of their own '
          'will have no name for previews; set defaultIdentity.name to the '
          'name the app ships with.',
      variantId: defaultId,
    );
  }
  if (config.defaultIdentity.icon == null) {
    add(
      ValidationSeverity.info,
      'missing_default_icon',
      'defaultIdentity has no icon, so the default variant has no preview '
          'image.',
      variantId: defaultId,
    );
  }

  for (final MapEntry(key: id, value: identity) in config.variants.entries) {
    if (id == defaultId) {
      add(
        ValidationSeverity.error,
        'reserved_variant_id',
        '"$defaultId" is reserved for defaultIdentity; rename this variant.',
        variantId: id,
      );
      continue;
    }
    if (!variantIdPattern.hasMatch(id)) {
      add(
        ValidationSeverity.error,
        'invalid_variant_id',
        'Variant id "$id" must match ${variantIdPattern.pattern} '
            '(lowercase letters, digits, underscores; it becomes an Android '
            'resource name and iOS alternate icon name).',
        variantId: id,
      );
    }
    checkIdentity(id, identity);
    if (identity.name == null &&
        identity.icon == null &&
        identity.platforms.isEmpty) {
      add(
        ValidationSeverity.warning,
        'variant_has_no_effect',
        'Variant defines no name, icon or platform override, so it is '
            'identical to the default identity.',
        variantId: id,
      );
    }
  }

  // Formats a runtime desktop icon cannot be decoded from.
  for (final id in config.variantIds) {
    for (final platform in _rasterOnlyPlatforms) {
      final icon = config.resolve(id, platform).icon;
      if (icon != null && icon.path.toLowerCase().endsWith('.svg')) {
        add(
          ValidationSeverity.error,
          'unsupported_icon_format',
          '${platform.name} needs a raster icon (PNG recommended); '
              '"${icon.path}" is SVG. Add a ${platform.name} override with a '
              'PNG.',
          variantId: id,
          platform: platform,
        );
      }
    }
  }

  return IconShiftValidationResult(List.unmodifiable(issues));
}
