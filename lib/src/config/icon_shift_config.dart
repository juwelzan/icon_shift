import 'package:flutter/foundation.dart';

import '../exceptions.dart';
import 'app_identity.dart';
import 'platform.dart';

/// The complete set of identities an app can switch between.
///
/// ```dart
/// const config = IconShiftConfig(
///   defaultIdentity: AppIdentity(
///     name: 'My App',
///     icon: AppIcon.asset('assets/icons/app.png'),
///     platforms: {
///       // Android gets its own icon but keeps the shared name.
///       IconShiftPlatform.android:
///           IdentityOverride(icon: AppIcon.asset('assets/icons/android.png')),
///     },
///   ),
///   variants: {
///     'dark': AppIdentity(
///       name: 'My App Dark',
///       icon: AppIcon.asset('assets/icons/dark.png'),
///     ),
///   },
/// );
/// ```
@immutable
class IconShiftConfig {
  const IconShiftConfig({
    required this.defaultIdentity,
    this.variants = const {},
    this.renamedVariants = const {},
  });

  /// The id that always refers to [defaultIdentity]. It cannot be used as a
  /// key in [variants].
  static const String defaultVariantId = 'default';

  /// The identity the app ships with, and the fallback for every variant.
  final AppIdentity defaultIdentity;

  /// Alternative identities, keyed by variant id (`[a-z][a-z0-9_]*`).
  final Map<String, AppIdentity> variants;

  /// Variant ids that were renamed or removed in an app update, mapped to
  /// the variant that replaces them (or [defaultVariantId]). A saved
  /// selection of an old id is migrated on [IconShift.initialize]; on
  /// Android, icon_shift_cli keeps a disabled alias for each so devices that
  /// show the old variant keep a launcher entry.
  final Map<String, String> renamedVariants;

  /// [defaultVariantId] followed by the ids of [variants].
  List<String> get variantIds => [defaultVariantId, ...variants.keys];

  bool hasVariant(String variantId) =>
      variantId == defaultVariantId || variants.containsKey(variantId);

  /// Returns the identity of [variantId] as seen on [platform].
  ///
  /// `name` and `icon` are resolved independently; the first non-null value
  /// wins in this order:
  ///
  /// 1. `variants[variantId].platforms[platform]`
  /// 2. `variants[variantId]`
  /// 3. `defaultIdentity.platforms[platform]`
  /// 4. `defaultIdentity`
  ///
  /// With a [locale] (`de`, `pt_BR`), each level's `localizedNames` is
  /// checked (full locale, then language) before its `name`. A `null`
  /// [platform] skips the platform-specific steps.
  ///
  /// Throws [VariantNotFoundException] for an unknown [variantId].
  ResolvedIdentity resolve(
    String variantId,
    IconShiftPlatform? platform, {
    String? locale,
  }) {
    final AppIdentity? variant;
    if (variantId == defaultVariantId) {
      variant = null;
    } else {
      variant = variants[variantId];
      if (variant == null) {
        throw VariantNotFoundException(variantId, variantIds);
      }
    }
    final variantOverride = variant?.platforms[platform];
    final defaultOverride = defaultIdentity.platforms[platform];
    final tag = locale?.replaceAll('-', '_');

    String? nameAt(String? name, Map<String, String>? names) {
      if (tag != null && names != null && names.isNotEmpty) {
        final localized = names[tag] ?? names[tag.split('_').first];
        if (localized != null) return localized;
      }
      return name;
    }

    final ownName =
        nameAt(variantOverride?.name, variantOverride?.localizedNames) ??
        nameAt(variant?.name, variant?.localizedNames);
    final ownIcon = variantOverride?.icon ?? variant?.icon;
    return ResolvedIdentity(
      variantId: variantId,
      platform: platform,
      name:
          ownName ??
          nameAt(defaultOverride?.name, defaultOverride?.localizedNames) ??
          nameAt(defaultIdentity.name, defaultIdentity.localizedNames),
      icon: ownIcon ?? defaultOverride?.icon ?? defaultIdentity.icon,
      usesDefaultName: ownName == null,
      usesDefaultIcon: ownIcon == null,
      appearance: variant?.appearance ?? defaultIdentity.appearance,
      themeColor: variant?.themeColor ?? defaultIdentity.themeColor,
    );
  }

  /// The current id for a possibly renamed [variantId], or `null` if it is
  /// neither configured nor in [renamedVariants].
  String? migrateVariantId(String variantId) {
    var id = variantId;
    for (var hops = 0; hops < 8; hops++) {
      if (hasVariant(id)) return id;
      final next = renamedVariants[id];
      if (next == null) return null;
      id = next;
    }
    return null; // Cycle.
  }

  @override
  bool operator ==(Object other) =>
      other is IconShiftConfig &&
      other.defaultIdentity == defaultIdentity &&
      mapEquals(other.variants, variants) &&
      mapEquals(other.renamedVariants, renamedVariants);

  @override
  int get hashCode => Object.hash(
    defaultIdentity,
    Object.hashAllUnordered(variants.entries.map((e) => (e.key, e.value))),
  );
}

/// The effective name and icon of one variant on one platform.
@immutable
class ResolvedIdentity {
  const ResolvedIdentity({
    required this.variantId,
    required this.platform,
    required this.name,
    required this.icon,
    required this.usesDefaultName,
    required this.usesDefaultIcon,
    this.appearance,
    this.themeColor,
  });

  final String variantId;
  final IconShiftPlatform? platform;

  /// Effective display name, or `null` if none is configured anywhere.
  final String? name;

  /// Effective icon, or `null` if none is configured anywhere.
  final AppIcon? icon;

  /// `true` when the variant does not define its own name, so switching to
  /// it restores the app's shipped name.
  final bool usesDefaultName;

  /// `true` when the variant does not define its own icon, so switching to
  /// it restores the app's shipped icon.
  final bool usesDefaultIcon;

  /// Appearance metadata of the variant (or the default identity).
  final IdentityAppearance? appearance;

  /// ARGB theme color of the variant (or the default identity).
  final int? themeColor;

  bool get isDefault => variantId == IconShiftConfig.defaultVariantId;

  @override
  bool operator ==(Object other) =>
      other is ResolvedIdentity &&
      other.variantId == variantId &&
      other.platform == platform &&
      other.name == name &&
      other.icon == icon &&
      other.usesDefaultName == usesDefaultName &&
      other.usesDefaultIcon == usesDefaultIcon &&
      other.appearance == appearance &&
      other.themeColor == themeColor;

  @override
  int get hashCode => Object.hash(
    variantId,
    platform,
    name,
    icon,
    usesDefaultName,
    usesDefaultIcon,
    appearance,
    themeColor,
  );

  @override
  String toString() =>
      'ResolvedIdentity($variantId on ${platform?.name ?? 'any'}: '
      'name: $name, icon: $icon)';
}
