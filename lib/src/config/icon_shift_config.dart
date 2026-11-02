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
  });

  /// The id that always refers to [defaultIdentity]. It cannot be used as a
  /// key in [variants].
  static const String defaultVariantId = 'default';

  /// The identity the app ships with, and the fallback for every variant.
  final AppIdentity defaultIdentity;

  /// Alternative identities, keyed by variant id (`[a-z][a-z0-9_]*`).
  final Map<String, AppIdentity> variants;

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
  /// A `null` [platform] skips the platform-specific steps.
  ///
  /// Throws [VariantNotFoundException] for an unknown [variantId].
  ResolvedIdentity resolve(String variantId, IconShiftPlatform? platform) {
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

    final ownName = variantOverride?.name ?? variant?.name;
    final ownIcon = variantOverride?.icon ?? variant?.icon;
    return ResolvedIdentity(
      variantId: variantId,
      platform: platform,
      name: ownName ?? defaultOverride?.name ?? defaultIdentity.name,
      icon: ownIcon ?? defaultOverride?.icon ?? defaultIdentity.icon,
      usesDefaultName: ownName == null,
      usesDefaultIcon: ownIcon == null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IconShiftConfig &&
      other.defaultIdentity == defaultIdentity &&
      mapEquals(other.variants, variants);

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

  bool get isDefault => variantId == IconShiftConfig.defaultVariantId;

  @override
  bool operator ==(Object other) =>
      other is ResolvedIdentity &&
      other.variantId == variantId &&
      other.platform == platform &&
      other.name == name &&
      other.icon == icon &&
      other.usesDefaultName == usesDefaultName &&
      other.usesDefaultIcon == usesDefaultIcon;

  @override
  int get hashCode => Object.hash(
    variantId,
    platform,
    name,
    icon,
    usesDefaultName,
    usesDefaultIcon,
  );

  @override
  String toString() =>
      'ResolvedIdentity($variantId on ${platform?.name ?? 'any'}: '
      'name: $name, icon: $icon)';
}
