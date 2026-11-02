import 'package:flutter/foundation.dart';

import '../config/platform.dart';

/// How the running app was installed, where the platform can tell.
enum InstallationType {
  /// Installed from a store or package (Play/App Store/MSIX/deb/rpm…), or
  /// the platform does not distinguish.
  standard,

  /// Packaged as MSIX (Windows).
  msix,

  /// Flatpak sandbox (Linux).
  flatpak,

  /// Snap sandbox (Linux).
  snap,

  /// AppImage (Linux).
  appImage,

  /// Unpackaged executable (Windows, Linux development builds).
  unpackaged,

  /// Browser tab (web).
  browser,

  /// Installed PWA in a standalone window (web).
  installedPwa,

  /// Not determinable.
  unknown,
}

/// Identity metadata the OS exposes about the running app. Every field is
/// `null` when the platform does not expose it; IconShift never guesses.
///
/// Distinct properties are kept distinct: [displayName] (what users see),
/// [applicationId] (Android applicationId / bundle id / Linux app id / MSIX
/// package family), [executableName] (file name of the binary) and
/// [windowTitle] / document title.
@immutable
class ApplicationInfo {
  const ApplicationInfo({
    required this.platform,
    this.displayName,
    this.applicationId,
    this.version,
    this.buildNumber,
    this.executableName,
    this.windowTitle,
    this.installationType = InstallationType.unknown,
    this.currentIconVariant,
    this.osVersion,
  });

  factory ApplicationInfo.fromMap(
    IconShiftPlatform? platform,
    Map<Object?, Object?> map,
  ) {
    final type = map['installationType'] as String?;
    return ApplicationInfo(
      platform: platform,
      displayName: map['displayName'] as String?,
      applicationId: map['applicationId'] as String?,
      version: map['version'] as String?,
      buildNumber: map['buildNumber'] as String?,
      executableName: map['executableName'] as String?,
      windowTitle: map['windowTitle'] as String?,
      installationType: InstallationType.values.firstWhere(
        (t) => t.name == type,
        orElse: () => InstallationType.unknown,
      ),
      osVersion: map['osVersion'] as String?,
    );
  }

  final IconShiftPlatform? platform;

  /// Name the OS shows for the installed app (launcher label, bundle display
  /// name, product name). On Android this is the active alias label.
  final String? displayName;

  /// The installation identity: Android applicationId, Apple bundle id,
  /// Linux application id, MSIX package family name, or web origin.
  final String? applicationId;

  final String? version;
  final String? buildNumber;

  /// File name of the running executable (desktop).
  final String? executableName;

  /// Current window or document title (desktop/web).
  final String? windowTitle;

  final InstallationType installationType;

  /// Active icon variant, `'default'` for the shipped icon, `null` when the
  /// platform cannot tell.
  final String? currentIconVariant;

  /// OS version string, for diagnostics.
  final String? osVersion;

  ApplicationInfo copyWith({String? currentIconVariant}) => ApplicationInfo(
    platform: platform,
    displayName: displayName,
    applicationId: applicationId,
    version: version,
    buildNumber: buildNumber,
    executableName: executableName,
    windowTitle: windowTitle,
    installationType: installationType,
    currentIconVariant: currentIconVariant ?? this.currentIconVariant,
    osVersion: osVersion,
  );

  @override
  bool operator ==(Object other) =>
      other is ApplicationInfo &&
      other.platform == platform &&
      other.displayName == displayName &&
      other.applicationId == applicationId &&
      other.version == version &&
      other.buildNumber == buildNumber &&
      other.executableName == executableName &&
      other.windowTitle == windowTitle &&
      other.installationType == installationType &&
      other.currentIconVariant == currentIconVariant &&
      other.osVersion == osVersion;

  @override
  int get hashCode => Object.hash(
    platform,
    displayName,
    applicationId,
    version,
    buildNumber,
    executableName,
    windowTitle,
    installationType,
    currentIconVariant,
    osVersion,
  );

  @override
  String toString() =>
      'ApplicationInfo(${platform?.name}: $displayName, id: $applicationId, '
      'version: $version+$buildNumber, installed as ${installationType.name}'
      '${currentIconVariant == null ? '' : ', icon: $currentIconVariant'})';
}
