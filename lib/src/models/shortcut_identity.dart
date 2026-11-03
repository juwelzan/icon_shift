import 'package:flutter/foundation.dart';

/// The home-screen shortcut IconShift owns, as the launcher shows it now.
///
/// A shortcut is the only launcher entry whose name and icon can be chosen
/// while the app runs: see `IconShift.setShortcutIdentity`.
@immutable
class ShortcutIdentityState {
  const ShortcutIdentityState({
    this.isSupported = false,
    this.isPinned = false,
    this.name,
    this.iconKey,
    this.limitation,
  });

  factory ShortcutIdentityState.fromMap(Map<Object?, Object?> map) =>
      ShortcutIdentityState(
        isSupported: map['supported'] as bool? ?? false,
        isPinned: map['pinned'] as bool? ?? false,
        name: map['name'] as String?,
        iconKey: map['iconKey'] as String?,
        limitation: map['limitation'] as String?,
      );

  /// This device and launcher can place a shortcut.
  final bool isSupported;

  /// The shortcut is on the home screen, so changes apply silently.
  final bool isPinned;

  /// The name the shortcut shows.
  final String? name;

  /// Asset key, remote icon key or variant id of the icon it shows.
  final String? iconKey;

  /// Why it is unsupported, or a caveat of the supported case.
  final String? limitation;

  @override
  bool operator ==(Object other) =>
      other is ShortcutIdentityState &&
      other.isSupported == isSupported &&
      other.isPinned == isPinned &&
      other.name == name &&
      other.iconKey == iconKey &&
      other.limitation == limitation;

  @override
  int get hashCode =>
      Object.hash(isSupported, isPinned, name, iconKey, limitation);

  @override
  String toString() =>
      'ShortcutIdentityState(supported: $isSupported, pinned: $isPinned, '
      'name: $name, icon: $iconKey)';
}
