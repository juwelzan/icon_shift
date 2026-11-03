import 'package:flutter/foundation.dart';

import 'result.dart';

/// Where a launcher name ended up after `IconShift.changeLauncherName`.
enum LauncherNameScope {
  /// The app's own launcher entry — home screen and app drawer (Android:
  /// the active activity-alias).
  appEntry,

  /// A window or browser-tab title, the nearest equivalent on desktop and
  /// web.
  windowTitle,

  /// The OS cannot show this name on the installed app's launcher entry:
  /// iOS for any name, Android for a name that is not compiled in.
  unsupported,
}

/// What `IconShift.changeLauncherName` did, read back from the OS.
@immutable
class LauncherNameResult {
  const LauncherNameResult({
    required this.requested,
    required this.scope,
    required this.status,
    required this.result,
    this.appEntryName,
    this.availableNames = const [],
    this.message,
  });

  /// The name that was asked for.
  final String requested;

  final LauncherNameScope scope;

  /// `applied`, `unchanged`, `unsupported` or `failed` (the launcher did not
  /// report the new name).
  final OperationStatus status;

  /// The underlying per-property outcome.
  final IconShiftResult result;

  /// The app entry's name as the OS reports it **after** the call.
  final String? appEntryName;

  /// Names the app entry can switch to on this install (Android: the
  /// labels compiled into the activity-aliases).
  final List<String> availableNames;

  final String? message;

  /// The app entry itself now shows [requested] — on Android in the app
  /// drawer too.
  bool get isAppEntryChanged =>
      scope == LauncherNameScope.appEntry &&
      (status == OperationStatus.applied ||
          status == OperationStatus.unchanged) &&
      appEntryName == requested;

  bool get isSuccessful =>
      status == OperationStatus.applied || status == OperationStatus.unchanged;

  @override
  String toString() =>
      'LauncherNameResult("$requested" → ${scope.name}, ${status.name}, '
      'app entry: ${appEntryName ?? '?'}'
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

  /// Names the app entry can switch to without a rebuild.
  final List<String> availableNames;

  /// The app entry can change at runtime at all (Android: yes, among
  /// [availableNames]; iOS: no).
  final bool canSwitchAppEntry;

  @override
  String toString() =>
      'LauncherNameInfo(app entry: $appEntryName, '
      'available: $availableNames)';
}
