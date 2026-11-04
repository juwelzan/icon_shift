import 'package:flutter/foundation.dart';

import '../config/icon_shift_config.dart';
import '../config/platform.dart';
import 'launcher_name.dart';

/// The app's identity as requested by the app and as reported by the OS.
///
/// The *requested* values are what the app last asked for (persisted across
/// restarts). The *native* values are read back from the OS and are the
/// source of truth for what users actually see:
///
/// * Android: the enabled activity-alias and its label.
/// * iOS: `UIApplication.alternateIconName`.
/// * macOS, Windows, Linux, web: what IconShift applied in the current
///   process (these changes do not outlive the process).
@immutable
class IconShiftState {
  const IconShiftState({
    required this.platform,
    this.requestedIdentity,
    this.requestedIconVariant,
    this.requestedDisplayName,
    this.nativeIconVariant,
    this.nativeDisplayName,
    this.pendingIconVariant,
    this.launcher,
  });

  /// The installed app's launcher identity (name under the icon, icon key),
  /// with which values were read from the OS. `null` from implementations
  /// that predate it.

  final IconShiftPlatform? platform;

  /// Variant last applied with [IconShift.setIdentity], or `null` if the
  /// icon/name were last set individually or the default is active.
  final String? requestedIdentity;

  /// Variant whose icon the app last requested, or `null` for the default.
  final String? requestedIconVariant;

  /// Display name the app last requested, or `null` for the shipped name.
  final String? requestedDisplayName;

  /// Variant whose icon the OS reports as active, `'default'` for the
  /// shipped icon, or `null` when the platform cannot tell.
  final String? nativeIconVariant;

  /// Display name the OS reports (launcher label, window title, document
  /// title), or `null` when the platform cannot tell.
  final String? nativeDisplayName;

  /// Variant the OS has accepted but not applied yet, if any.
  final String? pendingIconVariant;

  final LauncherIdentity? launcher;

  /// Effective icon variant: native when known, otherwise requested.
  String get currentIconVariant =>
      nativeIconVariant ??
      requestedIconVariant ??
      IconShiftConfig.defaultVariantId;

  /// `false` when the OS reports a different icon than the app requested —
  /// for example after a failed switch or a reinstall that reset native
  /// state. `true` when the platform cannot report its native icon.
  bool get isIconInSync =>
      nativeIconVariant == null ||
      pendingIconVariant != null ||
      nativeIconVariant ==
          (requestedIconVariant ?? IconShiftConfig.defaultVariantId);

  /// `false` when a requested display name is not what the OS reports.
  bool get isDisplayNameInSync =>
      requestedDisplayName == null ||
      nativeDisplayName == null ||
      nativeDisplayName == requestedDisplayName;

  @override
  bool operator ==(Object other) =>
      other is IconShiftState &&
      other.platform == platform &&
      other.requestedIdentity == requestedIdentity &&
      other.requestedIconVariant == requestedIconVariant &&
      other.requestedDisplayName == requestedDisplayName &&
      other.nativeIconVariant == nativeIconVariant &&
      other.nativeDisplayName == nativeDisplayName &&
      other.pendingIconVariant == pendingIconVariant &&
      other.launcher == launcher;

  @override
  int get hashCode => Object.hash(
    platform,
    requestedIdentity,
    requestedIconVariant,
    requestedDisplayName,
    nativeIconVariant,
    nativeDisplayName,
    pendingIconVariant,
    launcher,
  );

  @override
  String toString() =>
      'IconShiftState(requested: identity=$requestedIdentity, '
      'icon=$requestedIconVariant, name=$requestedDisplayName; '
      'native: icon=$nativeIconVariant, name=$nativeDisplayName'
      '${pendingIconVariant == null ? '' : ', pending=$pendingIconVariant'})';
}
