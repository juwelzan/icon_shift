import 'package:flutter/foundation.dart';

import '../config/app_identity.dart';
import '../config/platform.dart';
import 'validation.dart';

/// What applying a variant would do, without applying it.
///
/// This is structured metadata, not a rendered launcher preview: IconShift
/// cannot render how a particular launcher will draw the icon.
@immutable
class IdentityPreview {
  const IdentityPreview({
    required this.variantId,
    required this.platforms,
    this.currentPlatform,
    this.warnings = const [],
  });

  final String variantId;

  /// The resolved name/icon on every platform.
  final Map<IconShiftPlatform, PlatformIdentityPreview> platforms;

  /// The platform the app runs on, if supported.
  final IconShiftPlatform? currentPlatform;

  /// Problems applying it here would run into (unsupported parts, missing
  /// assets or native resources), plus configuration findings.
  final List<ValidationIssue> warnings;

  PlatformIdentityPreview? get current =>
      currentPlatform == null ? null : platforms[currentPlatform];

  /// Applying it on the current platform would change everything it defines.
  bool get isFullyApplicable =>
      warnings.every((w) => w.severity == ValidationSeverity.info);

  @override
  String toString() {
    final b = StringBuffer('IdentityPreview($variantId)\n');
    platforms.forEach((p, v) => b.writeln('  ${p.name}: $v'));
    for (final w in warnings) {
      b.writeln('  $w');
    }
    return b.toString();
  }
}

/// The resolved identity of one variant on one platform.
@immutable
class PlatformIdentityPreview {
  const PlatformIdentityPreview({
    required this.displayName,
    required this.icon,
    required this.usesDefaultName,
    required this.usesDefaultIcon,
    required this.nameAppliesAtRuntime,
    required this.iconAppliesAtRuntime,
  });

  final String? displayName;

  /// Asset for in-app previews (not the OS-rendered launcher icon).
  final AppIcon? icon;
  final bool usesDefaultName;
  final bool usesDefaultIcon;

  /// Whether IconShift can show [displayName] on this platform at runtime
  /// (statically; the live check is [IconShift.getCapabilities]).
  final bool nameAppliesAtRuntime;
  final bool iconAppliesAtRuntime;

  @override
  String toString() =>
      'name: ${displayName ?? '(none)'}${nameAppliesAtRuntime ? '' : ' (not at runtime)'}, '
      'icon: ${icon?.assetKey ?? '(none)'}${iconAppliesAtRuntime ? '' : ' (not at runtime)'}';
}
