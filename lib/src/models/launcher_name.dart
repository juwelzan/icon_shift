import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import 'result.dart';

/// The outcome of a launcher operation (`IconShift.changeLauncherName`,
/// `IconShift.changeLauncherIcon`). Only [success] means the OS now shows
/// the requested value.
enum IconShiftStatus {
  /// The OS switched the installed app's own launcher entry and reports the
  /// requested value for it. Whether the launcher app has redrawn already is
  /// not observable from inside the app; see [LauncherResult.launcherRefresh].
  success,

  /// Android accepted the switch and applies it when the app leaves the
  /// foreground: disabling the launcher entry the visible screen was opened
  /// through would make the OS close the app. Pass `immediate: true` to
  /// switch now and accept that.
  pending,

  /// The value is not one of the launcher identities compiled into the app.
  /// Nothing was changed. Ship a build containing it once; afterwards it
  /// switches at runtime like the others.
  requiresPreconfiguredLauncher,

  /// The platform only takes this value from a new build (iOS launcher name).
  requiresNewBuild,

  /// The platform has no such launcher operation (desktop, web).
  unsupported,

  /// The native call failed, the OS refused, or the plugin is missing.
  platformError,

  /// The switch was requested but the OS does not report the new value, or
  /// more than one launcher entry is enabled.
  failed;

  /// Stable `snake_case` form: `success`, `pending`,
  /// `requires_preconfigured_launcher`, `requires_new_build`, `unsupported`,
  /// `platform_error`, `failed`.
  String get code => switch (this) {
    success => 'success',
    pending => 'pending',
    requiresPreconfiguredLauncher => 'requires_preconfigured_launcher',
    requiresNewBuild => 'requires_new_build',
    unsupported => 'unsupported',
    platformError => 'platform_error',
    failed => 'failed',
  };

  /// Parses [code]; `null` when it is not a known status.
  static IconShiftStatus? fromCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Which part of the launcher identity an operation targets.
enum LauncherProperty { name, icon }

/// What the app can know about the launcher app's display after a switch.
enum LauncherRefresh {
  /// Nothing was switched (yet).
  notApplicable,

  /// The OS switched the component. Launchers pick it up through the
  /// package-changed broadcast — usually within a second or two; a few
  /// third-party launchers only after their own restart. An app cannot read
  /// another app's screen, so this is not confirmed from inside the app.
  expected,
}

/// The result of a launcher operation, read back from the OS.
@immutable
class LauncherResult {
  const LauncherResult({
    required this.property,
    required this.status,
    required this.requestedValue,
    required this.platform,
    this.appliedValue,
    this.message,
    this.changed = false,
    this.enabledEntries,
    this.availableValues = const [],
    this.launcherRefresh = LauncherRefresh.notApplicable,
    this.details,
  });

  /// Parses [toJson] output (for logs, tests, an app's own API).
  factory LauncherResult.fromJson(Map<String, Object?> json) => LauncherResult(
    property: LauncherProperty.values.byName(json['property']! as String),
    status:
        IconShiftStatus.fromCode(json['status'] as String?) ??
        IconShiftStatus.failed,
    requestedValue: json['requestedValue']! as String,
    platform: switch (json['platform']) {
      final String name => IconShiftPlatform.values.byName(name),
      _ => null,
    },
    appliedValue: json['appliedValue'] as String?,
    message: json['message'] as String?,
    changed: json['changed'] as bool? ?? false,
    enabledEntries: json['enabledEntries'] as int?,
    availableValues: [...?(json['availableValues'] as List?)?.cast<String>()],
    launcherRefresh: LauncherRefresh.values.byName(
      json['launcherRefresh'] as String? ?? LauncherRefresh.notApplicable.name,
    ),
  );

  final LauncherProperty property;
  final IconShiftStatus status;

  /// The name or icon key that was asked for.
  final String requestedValue;

  /// What the OS reports **after** the call: the launcher label for a name,
  /// the active icon key for an icon.
  final String? appliedValue;

  final IconShiftPlatform? platform;
  final String? message;

  /// `true` when this call switched the entry; `false` when it already
  /// showed [requestedValue] or nothing changed.
  final bool changed;

  /// Android: enabled IconShift launcher entries after the call. Anything
  /// but 1 is reported as [IconShiftStatus.failed].
  final int? enabledEntries;

  /// Values this install can switch to without a new build (names or icon
  /// keys), read from the OS where it can tell.
  final List<String> availableValues;

  final LauncherRefresh launcherRefresh;

  /// The per-property outcome of the underlying operation, if one ran.
  final IconShiftResult? details;

  bool get success => status == IconShiftStatus.success;

  bool get requiresNewBuild =>
      status == IconShiftStatus.requiresNewBuild ||
      status == IconShiftStatus.requiresPreconfiguredLauncher;

  Map<String, Object?> toJson() => {
    'property': property.name,
    'status': status.code,
    'requestedValue': requestedValue,
    'appliedValue': appliedValue,
    'platform': platform?.name,
    'changed': changed,
    'requiresNewBuild': requiresNewBuild,
    'enabledEntries': ?enabledEntries,
    'availableValues': availableValues,
    'launcherRefresh': launcherRefresh.name,
    'message': ?message,
  };

  @override
  bool operator ==(Object other) =>
      other is LauncherResult &&
      other.property == property &&
      other.status == status &&
      other.requestedValue == requestedValue &&
      other.appliedValue == appliedValue &&
      other.platform == platform &&
      other.message == message &&
      other.changed == changed &&
      other.enabledEntries == enabledEntries &&
      listEquals(other.availableValues, availableValues) &&
      other.launcherRefresh == launcherRefresh;

  @override
  int get hashCode => Object.hash(
    property,
    status,
    requestedValue,
    appliedValue,
    platform,
    message,
    changed,
    enabledEntries,
    Object.hashAll(availableValues),
    launcherRefresh,
  );

  @override
  String toString() =>
      'LauncherResult(${property.name} ${status.code}, requested: '
      '"$requestedValue", applied: '
      '${appliedValue == null ? '?' : '"$appliedValue"'}'
      '${changed ? ', changed' : ''}'
      '${enabledEntries == null ? '' : ', enabled entries: $enabledEntries'}'
      '${message == null ? '' : ' — $message'})';
}

/// Launcher-related features, for [IconShiftCapabilities.supportedFeatures].
enum IconShiftFeature {
  /// Switch the installed app's launcher name among names compiled into the
  /// app (Android).
  preconfiguredLauncherNames,

  /// Switch the installed app's launcher icon among icons compiled into the
  /// app (Android activity-aliases, iOS alternate icons).
  preconfiguredLauncherIcons,

  /// Give the installed app's launcher entry any name at runtime. No
  /// platform offers this; it is listed so it shows up as unsupported.
  customLauncherName,

  /// Give the installed app's launcher entry any image at runtime. No
  /// platform offers this either.
  customLauncherIcon,

  /// Change the icon of the running app (Dock, taskbar, favicon).
  runningAppIcon,

  /// Change the window or browser-tab title.
  windowTitle,

  /// Change the recent-apps label (Android).
  recentAppsLabel,
}

/// The launcher identity of the installed app, as reliably as the OS
/// reports it.
@immutable
class LauncherIdentity {
  const LauncherIdentity({
    required this.platform,
    this.name,
    this.iconKey,
    this.isNameVerified = false,
    this.isIconVerified = false,
    this.pendingIconKey,
  });

  final IconShiftPlatform? platform;

  /// The launcher name, or `null` when the platform cannot report it.
  final String? name;

  /// The launcher icon key (`default` or a variant id), or `null` when the
  /// platform cannot report it.
  final String? iconKey;

  /// [name] was read from the OS (Android PackageManager, iOS bundle), not
  /// taken from configuration.
  final bool isNameVerified;

  /// [iconKey] was read from the OS.
  final bool isIconVerified;

  /// Android: the identity a deferred switch will apply.
  final String? pendingIconKey;

  @override
  bool operator ==(Object other) =>
      other is LauncherIdentity &&
      other.platform == platform &&
      other.name == name &&
      other.iconKey == iconKey &&
      other.isNameVerified == isNameVerified &&
      other.isIconVerified == isIconVerified &&
      other.pendingIconKey == pendingIconKey;

  @override
  int get hashCode => Object.hash(
    platform,
    name,
    iconKey,
    isNameVerified,
    isIconVerified,
    pendingIconKey,
  );

  @override
  String toString() =>
      'LauncherIdentity(name: ${name ?? '?'}${isNameVerified ? ' (OS)' : ''}, '
      'icon: ${iconKey ?? '?'}${isIconVerified ? ' (OS)' : ''}'
      '${pendingIconKey == null ? '' : ', pending: $pendingIconKey'})';
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
