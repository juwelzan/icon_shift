import 'package:flutter/foundation.dart';

import 'platform.dart';

/// An icon image bundled with the app as a Flutter asset.
///
/// What the asset is used for depends on the platform:
///
/// * macOS, Windows, Linux, web: it is the image applied at runtime
///   (Dock/taskbar/window icon, favicon).
/// * Android, iOS: launcher icons must be compiled into the app as native
///   resources, so the asset is only used for in-app previews and as the
///   source image for `icon_shift_generator`.
@immutable
class AppIcon {
  /// An icon stored at [path] in the app's assets (declared in `pubspec.yaml`).
  ///
  /// Set [package] when the asset ships in another package.
  const AppIcon.asset(this.path, {this.package});

  /// Asset path as declared in `pubspec.yaml`, e.g. `assets/icons/dark.png`.
  final String path;

  /// Package that contains the asset, or `null` for the app's own assets.
  final String? package;

  /// The key to load this asset with from an `AssetBundle`.
  String get assetKey => package == null ? path : 'packages/$package/$path';

  @override
  bool operator ==(Object other) =>
      other is AppIcon && other.path == path && other.package == package;

  @override
  int get hashCode => Object.hash(path, package);

  @override
  String toString() => 'AppIcon.asset($assetKey)';
}

/// Artwork for the system icon appearances next to the regular (light)
/// icon: iOS/iPadOS 18+ dark and tinted, iOS 26 / macOS 26 Liquid Glass
/// clear.
///
/// * iOS: icon_shift_cli writes [dark] and [tinted] into each app icon set;
///   the OS then picks the right one for the home-screen mode by itself.
///   Asset catalogs have no slot for [clear]: iOS 26 derives the clear look
///   from the regular artwork, so [clear] is only used for previews.
/// * macOS, Windows, Linux, web: IconShift applies [dark] instead of the
///   regular icon while the system is in dark mode (see
///   `IconShift.initialize(followSystemAppearance:)`).
/// * Android: has no dark launcher icon; use `monochrome` in icon_shift.yaml
///   for themed icons (the counterpart of [tinted]).
@immutable
class IconAppearances {
  const IconAppearances({this.dark, this.tinted, this.clear});

  final AppIcon? dark;

  /// Grayscale artwork the OS tints with the user's color.
  final AppIcon? tinted;

  /// Artwork for the translucent Liquid Glass look.
  final AppIcon? clear;

  static const IconAppearances none = IconAppearances();

  bool get isEmpty => dark == null && tinted == null && clear == null;

  /// The artwork for [mode], or `null` when none is configured.
  AppIcon? operator [](IconAppearanceMode mode) => switch (mode) {
    IconAppearanceMode.light => null,
    IconAppearanceMode.dark => dark,
    IconAppearanceMode.tinted => tinted,
    IconAppearanceMode.clear => clear,
  };

  @override
  bool operator ==(Object other) =>
      other is IconAppearances &&
      other.dark == dark &&
      other.tinted == tinted &&
      other.clear == clear;

  @override
  int get hashCode => Object.hash(dark, tinted, clear);

  @override
  String toString() =>
      'IconAppearances(dark: $dark, tinted: $tinted, clear: $clear)';
}

/// The home-screen icon modes of iOS 26 / macOS 26 (Liquid Glass).
/// `light` is the regular icon ("Default" in the system settings).
enum IconAppearanceMode { light, dark, clear, tinted }

/// Which system appearance a variant is designed for. Metadata only: no OS
/// switches launcher icons automatically when the Flutter theme changes;
/// see [IconShiftThemeSync] for an explicit, opt-in sync.
enum IdentityAppearance { light, dark }

/// Platform-specific replacement for the name, localized names and/or icon
/// of an identity. A `null` field inherits.
@immutable
class IdentityOverride {
  const IdentityOverride({
    this.name,
    this.icon,
    this.localizedNames = const {},
    this.appearances = IconAppearances.none,
  });

  final String? name;
  final AppIcon? icon;

  /// Dark/tinted/clear artwork for this platform. See
  /// [AppIdentity.appearances] for how it is inherited.
  final IconAppearances appearances;

  /// Names by locale (`de`, `pt_BR`); see [AppIdentity.localizedNames].
  final Map<String, String> localizedNames;

  bool get isEmpty =>
      name == null &&
      icon == null &&
      localizedNames.isEmpty &&
      appearances.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is IdentityOverride &&
      other.name == name &&
      other.icon == icon &&
      mapEquals(other.localizedNames, localizedNames) &&
      other.appearances == appearances;

  @override
  int get hashCode =>
      Object.hash(name, icon, _hashMap(localizedNames), appearances);

  @override
  String toString() => 'IdentityOverride(name: $name, icon: $icon)';
}

int _hashMap(Map<Object?, Object?> map) =>
    Object.hashAllUnordered(map.entries.map((e) => (e.key, e.value)));

/// A display name and icon (an identity *profile*), with optional localized
/// names, theme metadata and per-platform overrides.
///
/// Used both for [IconShiftConfig.defaultIdentity] and for each variant.
/// Any field left `null` inherits from the default identity; see
/// [IconShiftConfig.resolve] for the exact rules.
@immutable
class AppIdentity {
  const AppIdentity({
    this.name,
    this.icon,
    this.localizedNames = const {},
    this.appearance,
    this.themeColor,
    this.platforms = const {},
    this.appearances = IconAppearances.none,
  });

  final String? name;
  final AppIcon? icon;

  /// Dark, tinted and clear versions of [icon]. They belong to the icon
  /// they are defined next to: a variant with its own icon never inherits
  /// the default identity's dark artwork, and a platform override that
  /// replaces the icon must bring its own appearances.
  final IconAppearances appearances;

  /// Names by locale: `{'de': 'Meine App', 'pt_BR': 'Meu App'}`. Lookup tries
  /// the full locale, then the language. Used where IconShift applies a
  /// name at runtime (window/document title) and for Android labels
  /// generated by icon_shift_cli.
  final Map<String, String> localizedNames;

  /// The system appearance this identity is designed for (metadata).
  final IdentityAppearance? appearance;

  /// ARGB color, e.g. `0xFF0D47A1`. Applied as the web theme color.
  final int? themeColor;

  /// Overrides that apply only on the given platform.
  final Map<IconShiftPlatform, IdentityOverride> platforms;

  @override
  bool operator ==(Object other) =>
      other is AppIdentity &&
      other.name == name &&
      other.icon == icon &&
      mapEquals(other.localizedNames, localizedNames) &&
      other.appearance == appearance &&
      other.themeColor == themeColor &&
      mapEquals(other.platforms, platforms) &&
      other.appearances == appearances;

  @override
  int get hashCode => Object.hash(
    name,
    icon,
    _hashMap(localizedNames),
    appearance,
    themeColor,
    _hashMap(platforms),
    appearances,
  );

  @override
  String toString() =>
      'AppIdentity(name: $name, icon: $icon, platforms: $platforms)';
}
