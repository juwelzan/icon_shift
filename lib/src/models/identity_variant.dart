import 'package:flutter/foundation.dart';

import '../config/app_identity.dart';

/// A configured variant, resolved for the current platform, for building
/// an icon picker.
@immutable
class IdentityVariant {
  const IdentityVariant({
    required this.id,
    required this.isDefault,
    required this.displayName,
    required this.previewIcon,
    required this.isAvailable,
    required this.isCurrentIcon,
    this.unavailableReason,
  });

  final String id;
  final bool isDefault;

  /// The name this variant resolves to on the current platform. Whether the
  /// OS can show it depends on [IconShiftCapabilities.displayName].
  final String? displayName;

  /// The asset configured for this variant on the current platform. Use it
  /// for previews only: on Android and iOS the launcher shows the native
  /// resource, which is not guaranteed to look the same.
  final AppIcon? previewIcon;

  /// The platform can switch to this variant (its native resources exist and
  /// the platform supports icon or name changes).
  final bool isAvailable;

  /// Why [isAvailable] is `false`.
  final String? unavailableReason;

  /// This variant's icon is the active one.
  final bool isCurrentIcon;

  @override
  bool operator ==(Object other) =>
      other is IdentityVariant &&
      other.id == id &&
      other.isDefault == isDefault &&
      other.displayName == displayName &&
      other.previewIcon == previewIcon &&
      other.isAvailable == isAvailable &&
      other.unavailableReason == unavailableReason &&
      other.isCurrentIcon == isCurrentIcon;

  @override
  int get hashCode => Object.hash(
    id,
    isDefault,
    displayName,
    previewIcon,
    isAvailable,
    unavailableReason,
    isCurrentIcon,
  );

  @override
  String toString() =>
      'IdentityVariant($id, name: $displayName, available: $isAvailable'
      '${isCurrentIcon ? ', current' : ''})';
}
