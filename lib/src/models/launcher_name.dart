import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import 'result.dart';

/// The outcome of `IconShift.changeLauncherName`. Only [success] means the
/// OS switched the launcher entry to the requested name.
enum LauncherNameStatus {
  /// The OS switched the app's own launcher entry and reports the requested
  /// name for it (Android: PackageManager read-back). Whether the launcher
  /// app has already redrawn its icon is not observable from inside the
  /// app; see [LauncherNameResult.launcherRefresh].
  success,

  /// The name is not one of the launcher identities compiled into the app.
  /// Nothing was changed. Ship a build that contains it once; afterwards it
  /// switches at runtime like the others.
  requiresPreconfiguredLauncher,

  /// The platform only takes a new launcher name from a new build (iOS).
  requiresNewBuild,

  /// This platform has no launcher name an app can change (desktop, web).
  unsupported,

  /// The native call failed or the OS refused it.
  platformError,

  /// The switch was requested but the OS does not report the new name, or
  /// more than one launcher entry is enabled.
  failed,
}

/// What the app can know about the launcher app's display after a switch.
enum LauncherRefresh {
  /// Nothing was switched.
  notApplicable,

  /// PackageManager switched the component. Launchers pick it up through
  /// the package-changed broadcast — usually within a second or two; a few
  /// third-party launchers only after their own restart. An app cannot read
  /// another app's screen, so this cannot be confirmed from inside the app.
  expected,
}

/// What `IconShift.changeLauncherName` did, read back from the OS.
@immutable
class LauncherNameResult {
  const LauncherNameResult({
    required this.requestedName,
    required this.status,
    required this.platform,
    required this.result,
    this.appliedName,
    this.changed = false,
    this.enabledEntries,
    this.availableNames = const [],
    this.launcherRefresh = LauncherRefresh.notApplicable,
    this.message,
  });

  /// The name that was asked for.
  final String requestedName;

  final LauncherNameStatus status;

  final IconShiftPlatform? platform;

  /// The launcher entry's name as the OS reports it **after** the call
  /// (Android: the label of the enabled activity-alias).
  final String? appliedName;

  /// `true` when this call switched the entry; `false` when it already
  /// showed [requestedName] or nothing changed.
  final bool changed;

  /// How many IconShift launcher entries are enabled after the call
  /// (Android). Anything but 1 is reported as [LauncherNameStatus.failed].
  final int? enabledEntries;

  /// Names the launcher entry can switch to on this install, read from the
  /// OS (Android: the labels of the compiled activity-aliases).
  final List<String> availableNames;

  final LauncherRefresh launcherRefresh;

  final String? message;

  /// The underlying per-property outcome.
  final IconShiftResult result;

  bool get isSuccess => status == LauncherNameStatus.success;

  /// The status as a stable string: `success`,
  /// `requires_preconfigured_launcher`, `requires_new_build`,
  /// `unsupported`, `platform_error`, `failed`.
  String get statusCode => switch (status) {
    LauncherNameStatus.success => 'success',
    LauncherNameStatus.requiresPreconfiguredLauncher =>
      'requires_preconfigured_launcher',
    LauncherNameStatus.requiresNewBuild => 'requires_new_build',
    LauncherNameStatus.unsupported => 'unsupported',
    LauncherNameStatus.platformError => 'platform_error',
    LauncherNameStatus.failed => 'failed',
  };

  Map<String, Object?> toJson() => {
    'status': statusCode,
    'requestedName': requestedName,
    'appliedName': appliedName,
    'platform': platform?.name,
    'changed': changed,
    'enabledEntries': ?enabledEntries,
    'availableNames': availableNames,
    'launcherRefresh': launcherRefresh.name,
    'message': ?message,
  };

  @override
  String toString() =>
      'LauncherNameResult($statusCode, requested: "$requestedName", '
      'applied: ${appliedName == null ? '?' : '"$appliedName"'}'
      '${changed ? ', changed' : ''}'
      '${enabledEntries == null ? '' : ', enabled entries: $enabledEntries'}'
      '${message == null ? '' : ' — $message'})';
}

/// The launcher names of this install, as the OS reports them.
@immutable
class LauncherNameInfo {
  const LauncherNameInfo({
    required this.appEntryName,
    required this.availableNames,
    required this.canSwitchAppEntry,
    this.requestedName,
  });

  /// What the home screen / app drawer shows for the app.
  final String? appEntryName;

  /// The last name passed to `changeLauncherName`, if any.
  final String? requestedName;

  /// Names the launcher entry can switch to without a rebuild.
  final List<String> availableNames;

  /// The launcher entry can change at runtime at all (Android: yes, among
  /// [availableNames]; iOS, desktop, web: no).
  final bool canSwitchAppEntry;

  @override
  String toString() =>
      'LauncherNameInfo(launcher shows: $appEntryName, '
      'available: $availableNames)';
}
