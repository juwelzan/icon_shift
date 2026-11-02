import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import 'capabilities.dart';

/// Application-identity properties, from what users see (names, icons) to
/// what the OS uses to identify an installation (ids, signing).
enum IdentityProperty {
  /// The name shown under the launcher icon / in the app list.
  displayName,

  /// The title of the app's window or browser tab.
  windowTitle,

  /// The icon used to launch the app (home screen, Finder, Start menu).
  launcherIcon,

  /// The icon of the running process (Dock, taskbar, title bar, favicon).
  runningAppIcon,

  /// Android adaptive icon layers; web maskable icons.
  adaptiveIcon,

  /// System-themed icons: Android monochrome, iOS dark/tinted.
  themedIcon,

  /// Browser UI tint (web theme color).
  themeColor,

  /// Android applicationId, Apple bundle id, Linux app id, MSIX identity,
  /// PWA manifest id.
  applicationId,

  /// Android Gradle namespace (code package, not the install identity).
  sourceNamespace,

  /// Executable / product file name.
  executableName,

  /// Version name and build number.
  version,

  /// Signing key, certificate, team or provisioning profile.
  signingIdentity,
}

/// How a property can change while the app runs.
enum RuntimeSupport {
  /// Any value; the OS keeps it.
  anyValue,

  /// Only values compiled into the app (activity-aliases, alternate icons).
  preconfigured,

  /// While the process runs; IconShift re-applies it on launch.
  sessionOnly,

  /// No supported runtime API.
  none,
}

/// What it takes to change one [IdentityProperty] on one platform.
@immutable
class PropertySupport {
  const PropertySupport({
    required this.runtime,
    this.buildTime = false,
    this.requiresReinstall = false,
    this.requiresNewSigningIdentity = false,
    this.preservesData = true,
    required this.note,
  });

  final RuntimeSupport runtime;

  /// It can be set before building (icon_shift_cli or the native project).
  final bool buildTime;

  /// Changing it makes the OS treat the app as a different installation.
  final bool requiresReinstall;

  /// Changing it needs a different signing identity or provisioning profile.
  final bool requiresNewSigningIdentity;

  /// Existing app data stays reachable after changing it.
  final bool preservesData;

  /// Platform-specific explanation.
  final String note;

  bool get isRuntimeChangeable => runtime != RuntimeSupport.none;

  /// Only changeable by rebuilding.
  bool get isBuildTimeOnly => !isRuntimeChangeable && buildTime;

  /// Neither at runtime nor at build time (not applicable).
  bool get isUnsupported => !isRuntimeChangeable && !buildTime;

  @override
  String toString() =>
      'runtime: ${runtime.name}, buildTime: $buildTime'
      '${requiresReinstall ? ', reinstall' : ''}'
      '${requiresNewSigningIdentity ? ', new signing identity' : ''}'
      '${preservesData ? '' : ', data not kept'}';
}

/// Everything IconShift knows about what a platform allows: the live runtime
/// capabilities plus the static identity property table.
@immutable
class PlatformCapabilities {
  const PlatformCapabilities({
    required this.platform,
    required this.runtime,
    required this.properties,
  });

  final IconShiftPlatform? platform;

  /// What IconShift can change right now (from the native side).
  final IconShiftCapabilities runtime;

  /// Static support of every [IdentityProperty] on [platform].
  final Map<IdentityProperty, PropertySupport> properties;

  List<IdentityProperty> get runtimeChangeable => [
    for (final e in properties.entries)
      if (e.value.isRuntimeChangeable) e.key,
  ];

  List<IdentityProperty> get buildTimeOnly => [
    for (final e in properties.entries)
      if (e.value.isBuildTimeOnly) e.key,
  ];

  List<IdentityProperty> get unsupported => [
    for (final e in properties.entries)
      if (e.value.isUnsupported) e.key,
  ];

  List<IdentityProperty> get requiringReinstall => [
    for (final e in properties.entries)
      if (e.value.requiresReinstall) e.key,
  ];

  /// Native setup IconShift needs for runtime changes on [platform].
  List<String> get requiredConfiguration => switch (platform) {
    IconShiftPlatform.android => const [
      'One <activity-alias> per variant with meta-data icon_shift.variant '
          '(icon_shift_cli generate writes them).',
      'MainActivity keeps a MAIN/LAUNCHER intent-filter with '
          '<data android:scheme="icon-shift-tooling"/> so `flutter run` works.',
    ],
    IconShiftPlatform.ios => const [
      'One app icon set per variant, named like the variant.',
      'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES.',
    ],
    IconShiftPlatform.macos ||
    IconShiftPlatform.windows ||
    IconShiftPlatform.linux ||
    IconShiftPlatform.web => const [
      'Icon images listed under flutter > assets in pubspec.yaml.',
    ],
    null => const [],
  };

  /// Runtime permissions IconShift needs. None: it never requests any.
  List<String> get requiredPermissions => const [];
}

/// The static support table for [platform].
Map<IdentityProperty, PropertySupport> identityPropertiesFor(
  IconShiftPlatform platform,
) => {for (final e in identityPropertyTable.entries) e.key: e.value[platform]!};

// GENERATED from cli/lib/src/property_table.dart; test/property_table_sync_test.dart
// keeps both identical.
const Map<IdentityProperty, Map<IconShiftPlatform, PropertySupport>>
identityPropertyTable = {
  IdentityProperty.displayName: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.preconfigured,
      buildTime: true,
      note: 'Launcher label of the active activity-alias.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'CFBundleDisplayName; read-only in a signed bundle.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'CFBundleDisplayName / PRODUCT_NAME; part of the signed bundle.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note:
          'Version-resource ProductName/FileDescription; shortcut names belong to the installer.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'Name= in the installed .desktop file, owned by the package.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note:
          'manifest.json name/short_name; browsers refresh installed PWAs on their own schedule.',
    ),
  },
  IdentityProperty.windowTitle: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Recents title comes from MaterialApp.title.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'No window titles.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      buildTime: true,
      note: 'NSWindow.title.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      buildTime: true,
      note: 'SetWindowTextW; also the taskbar button label.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      buildTime: true,
      note: 'GTK window and header bar title.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      buildTime: true,
      note: 'document.title (tab / installed-PWA window title).',
    ),
  },
  IdentityProperty.launcherIcon: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.preconfigured,
      buildTime: true,
      note: 'Activity-alias icons; launchers may cache for a few seconds.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.preconfigured,
      buildTime: true,
      note: 'Alternate app icons; the system shows a confirmation alert.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'Finder/Launchpad icon is in the signed bundle.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'Executable icon resource; shortcuts belong to the installer.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'Icon= of the installed .desktop file.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'Installed PWA icon comes from manifest.json.',
    ),
  },
  IdentityProperty.runningAppIcon: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not a separate concept on Android.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not a separate concept on iOS.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      note: 'Dock icon via NSApplication.applicationIconImage.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      note: 'WM_SETICON: title bar, Alt-Tab, unpinned taskbar button.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      note: 'gtk_window_set_icon; X11 only, ignored on Wayland.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      buildTime: true,
      note: 'Browser-tab favicon.',
    ),
  },
  IdentityProperty.adaptiveIcon: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.preconfigured,
      buildTime: true,
      note: 'API 26+; part of an alias icon resource.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'Maskable PWA icons.',
    ),
  },
  IdentityProperty.themedIcon: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note:
          'Monochrome layer (API 33+); the user enables themed icons, apps cannot.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note:
          'Dark/tinted appearances (iOS 18+), chosen by the system appearance.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'Asset catalog appearances, chosen by the system.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'No themed app icons.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Depends on the icon theme.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      buildTime: true,
      note: 'Favicon per prefers-color-scheme.',
    ),
  },
  IdentityProperty.themeColor: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not an app-identity property.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not an app-identity property.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not an app-identity property.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not an app-identity property.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not an app-identity property.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.sessionOnly,
      buildTime: true,
      note:
          '<meta name="theme-color"> at runtime; manifest theme_color at build time.',
    ),
  },
  IdentityProperty.applicationId: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresReinstall: true,
      preservesData: false,
      note:
          'applicationId; a new id is a separate app with its own data directory.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresReinstall: true,
      requiresNewSigningIdentity: true,
      preservesData: false,
      note:
          'Bundle identifier; needs a matching App ID and provisioning profile. Data is shared only via an App Group the old app already declared.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresReinstall: true,
      requiresNewSigningIdentity: true,
      preservesData: false,
      note:
          'Bundle identifier; new UserDefaults domain, sandbox container and TCC grants.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresReinstall: true,
      requiresNewSigningIdentity: true,
      preservesData: false,
      note:
          'MSIX Name+Publisher form the package family; unpackaged apps have no OS identity besides their path.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresReinstall: true,
      preservesData: false,
      note:
          'APPLICATION_ID / Flatpak app-id; Flatpak data lives in ~/.var/app/<id>.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresReinstall: true,
      note:
          'Manifest id; a new id installs as a new PWA. Storage is per origin.',
    ),
  },
  IdentityProperty.sourceNamespace: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note:
          'Gradle namespace (R/BuildConfig package); not the install identity.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
  },
  IdentityProperty.executableName: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'PRODUCT_NAME; not shown to users.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'PRODUCT_NAME: the .app and executable name.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      preservesData: false,
      note:
          'BINARY_NAME. path_provider derives %APPDATA% folders from version-resource names, so data may appear lost.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      preservesData: false,
      note: 'BINARY_NAME; data folders derived from it change.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'Not applicable.',
    ),
  },
  IdentityProperty.version: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note:
          'pubspec version → versionName/versionCode; versionCode must increase.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'pubspec version → CFBundleShortVersionString/CFBundleVersion.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'pubspec version → bundle version.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'pubspec version → version resource.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'pubspec version → version.json.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      note: 'pubspec version → version.json.',
    ),
  },
  IdentityProperty.signingIdentity: {
    IconShiftPlatform.android: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresReinstall: true,
      requiresNewSigningIdentity: true,
      preservesData: false,
      note:
          'A different key cannot update the installed app (except v3 key rotation / Play App Signing upgrade). IconShift never handles keys.',
    ),
    IconShiftPlatform.ios: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresNewSigningIdentity: true,
      note:
          'Team/provisioning in Xcode; changing team breaks keychain and App Group sharing.',
    ),
    IconShiftPlatform.macos: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresNewSigningIdentity: true,
      note:
          'Developer ID signing and notarization; keychain items are bound to the signer.',
    ),
    IconShiftPlatform.windows: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresReinstall: true,
      requiresNewSigningIdentity: true,
      preservesData: false,
      note: 'MSIX Publisher must equal the certificate subject.',
    ),
    IconShiftPlatform.linux: PropertySupport(
      runtime: RuntimeSupport.none,
      buildTime: true,
      requiresNewSigningIdentity: true,
      note: 'Package/repository signing only.',
    ),
    IconShiftPlatform.web: PropertySupport(
      runtime: RuntimeSupport.none,
      note: 'TLS of the origin; not an app property.',
    ),
  },
};
