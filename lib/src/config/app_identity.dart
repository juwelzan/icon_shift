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

/// Platform-specific replacement for the [AppIdentity.name] and/or
/// [AppIdentity.icon] of an identity. A `null` field inherits.
@immutable
class IdentityOverride {
  const IdentityOverride({this.name, this.icon});

  final String? name;
  final AppIcon? icon;

  bool get isEmpty => name == null && icon == null;

  @override
  bool operator ==(Object other) =>
      other is IdentityOverride && other.name == name && other.icon == icon;

  @override
  int get hashCode => Object.hash(name, icon);

  @override
  String toString() => 'IdentityOverride(name: $name, icon: $icon)';
}

/// A display name and icon, with optional per-platform overrides.
///
/// Used both for [IconShiftConfig.defaultIdentity] and for each variant.
/// Any field left `null` inherits from the default identity; see
/// [IconShiftConfig.resolve] for the exact rules.
@immutable
class AppIdentity {
  const AppIdentity({this.name, this.icon, this.platforms = const {}});

  final String? name;
  final AppIcon? icon;

  /// Overrides that apply only on the given platform.
  final Map<IconShiftPlatform, IdentityOverride> platforms;

  @override
  bool operator ==(Object other) =>
      other is AppIdentity &&
      other.name == name &&
      other.icon == icon &&
      mapEquals(other.platforms, platforms);

  @override
  int get hashCode => Object.hash(
    name,
    icon,
    Object.hashAllUnordered(platforms.entries.map((e) => (e.key, e.value))),
  );

  @override
  String toString() =>
      'AppIdentity(name: $name, icon: $icon, platforms: $platforms)';
}
