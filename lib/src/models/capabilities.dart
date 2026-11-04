import 'package:flutter/foundation.dart';

import '../config/platform.dart';
import 'launcher_name.dart';

/// Where a change made by IconShift is visible.
enum IdentityScope {
  /// The OS launcher (home screen, app drawer). Survives restarts.
  launcher,

  /// The Dock / taskbar / title-bar icon of the running app only.
  runningApp,

  /// The app's main window title.
  windowTitle,

  /// The browser tab (favicon, document title).
  browserTab,

  /// The app's entry in the recent-apps / task switcher screen (Android
  /// task label).
  taskSwitcher,

  /// Not supported.
  none,
}

/// What the current platform can do for one operation (icon or name).
@immutable
class OperationCapability {
  const OperationCapability({
    required this.isSupported,
    required this.scope,
    this.persistsNatively = false,
    this.requiresPreconfiguredResources = false,
    this.acceptsArbitraryValues = false,
    this.limitation,
  });

  const OperationCapability.unsupported(String reason)
    : this(isSupported: false, scope: IdentityScope.none, limitation: reason);

  /// Whether the operation can be performed at all right now.
  final bool isSupported;

  /// Where the change is visible.
  final IdentityScope scope;

  /// The OS keeps the change across app restarts by itself. When `false`,
  /// [IconShift.initialize] re-applies the saved selection.
  final bool persistsNatively;

  /// Values must be compiled into the app ahead of time (activity-aliases,
  /// alternate icon sets).
  final bool requiresPreconfiguredResources;

  /// Arbitrary values are accepted: any image asset for icons, any string
  /// for display names (see [IconShift.setDisplayName]).
  final bool acceptsArbitraryValues;

  /// Why the operation is unsupported, or a caveat of the supported one.
  final String? limitation;

  factory OperationCapability.fromMap(Map<Object?, Object?> map) {
    final scopeName = map['scope'] as String?;
    return OperationCapability(
      isSupported: map['supported'] as bool? ?? false,
      scope: IdentityScope.values.firstWhere(
        (s) => s.name == scopeName,
        orElse: () => IdentityScope.none,
      ),
      persistsNatively: map['persistsNatively'] as bool? ?? false,
      requiresPreconfiguredResources:
          map['requiresPreconfiguredResources'] as bool? ?? false,
      acceptsArbitraryValues: map['acceptsArbitraryValues'] as bool? ?? false,
      limitation: map['limitation'] as String?,
    );
  }

  Map<String, Object?> toMap() => {
    'supported': isSupported,
    'scope': scope.name,
    'persistsNatively': persistsNatively,
    'requiresPreconfiguredResources': requiresPreconfiguredResources,
    'acceptsArbitraryValues': acceptsArbitraryValues,
    'limitation': limitation,
  };

  @override
  bool operator ==(Object other) =>
      other is OperationCapability &&
      other.isSupported == isSupported &&
      other.scope == scope &&
      other.persistsNatively == persistsNatively &&
      other.requiresPreconfiguredResources == requiresPreconfiguredResources &&
      other.acceptsArbitraryValues == acceptsArbitraryValues &&
      other.limitation == limitation;

  @override
  int get hashCode => Object.hash(
    isSupported,
    scope,
    persistsNatively,
    requiresPreconfiguredResources,
    acceptsArbitraryValues,
    limitation,
  );

  @override
  String toString() {
    if (!isSupported) return 'unsupported${_suffix()}';
    final flags = [
      scope.name,
      if (persistsNatively) 'persists',
      if (requiresPreconfiguredResources) 'preconfigured',
      if (acceptsArbitraryValues) 'arbitrary values',
    ];
    return '${flags.join(', ')}${_suffix()}';
  }

  String _suffix() => limitation == null ? '' : ' — $limitation';
}

/// What the current platform lets IconShift change.
@immutable
class IconShiftCapabilities {
  const IconShiftCapabilities({
    required this.platform,
    required this.icon,
    required this.displayName,
    this.iconAndNameLinked = false,
    this.notes = const [],
  });

  /// Capabilities of a platform IconShift has no implementation for.
  IconShiftCapabilities.none(this.platform, String reason)
    : icon = OperationCapability.unsupported(reason),
      displayName = OperationCapability.unsupported(reason),
      iconAndNameLinked = false,
      notes = const [];

  final IconShiftPlatform? platform;
  final OperationCapability icon;
  final OperationCapability displayName;

  /// `true` when icon and display name can only change together (Android:
  /// each activity-alias has exactly one icon and one label).
  final bool iconAndNameLinked;

  /// Additional platform caveats worth showing a developer.
  final List<String> notes;

  bool get canChangeIcon => icon.isSupported;

  /// Any name and image chosen at runtime can be applied to the app itself
  /// (desktop and web; never Android's or iOS's launcher entry).
  bool get canShowArbitraryIdentity =>
      icon.acceptsArbitraryValues && displayName.acceptsArbitraryValues;
  bool get canChangeDisplayName => displayName.isSupported;

  /// Preconfigured variants can be switched to.
  bool get supportsVariants => canChangeIcon || canChangeDisplayName;

  /// Anything can be changed while the app runs.
  bool get supportsRuntimeChanges => canChangeIcon || canChangeDisplayName;

  /// Icons must be prepared as native resources at build time.
  bool get requiresPreconfiguredResources =>
      icon.requiresPreconfiguredResources;

  // --- Launcher identity (the installed app's home-screen / drawer entry).

  /// The installed app's own launcher name can change at runtime — among
  /// the names compiled into the app (Android only).
  bool get canChangeLauncherName =>
      platform == IconShiftPlatform.android &&
      iconAndNameLinked &&
      icon.isSupported;

  /// The installed app's own launcher icon can change at runtime — among
  /// the icons compiled into the app (Android activity-aliases, iOS
  /// alternate icons).
  bool get canChangeLauncherIcon =>
      (platform == IconShiftPlatform.android ||
          platform == IconShiftPlatform.ios) &&
      icon.isSupported &&
      icon.scope == IdentityScope.launcher;

  /// Launcher names are switched among values compiled into the app.
  bool get supportsPreconfiguredLauncherNames => canChangeLauncherName;

  /// Launcher icons are switched among values compiled into the app.
  bool get supportsPreconfiguredLauncherIcons => canChangeLauncherIcon;

  /// A launcher name that is not compiled into the app needs a new build —
  /// true on every platform: none lets an installed app take an arbitrary
  /// launcher name.
  bool get requiresNewBuildForCustomName => true;

  /// Launcher and identity features available here.
  Set<IconShiftFeature> get supportedFeatures => {
    if (supportsPreconfiguredLauncherNames)
      IconShiftFeature.preconfiguredLauncherNames,
    if (supportsPreconfiguredLauncherIcons)
      IconShiftFeature.preconfiguredLauncherIcons,
    if (icon.isSupported &&
        (icon.scope == IdentityScope.runningApp ||
            icon.scope == IdentityScope.browserTab))
      IconShiftFeature.runningAppIcon,
    if (displayName.isSupported &&
        (displayName.scope == IdentityScope.windowTitle ||
            displayName.scope == IdentityScope.browserTab))
      IconShiftFeature.windowTitle,
    if (displayName.isSupported &&
        displayName.scope == IdentityScope.taskSwitcher)
      IconShiftFeature.recentAppsLabel,
  };

  /// Every feature not in [supportedFeatures].
  Set<IconShiftFeature> get unsupportedFeatures =>
      IconShiftFeature.values.toSet().difference(supportedFeatures);

  factory IconShiftCapabilities.fromMap(
    IconShiftPlatform? platform,
    Map<Object?, Object?> map,
  ) {
    Map<Object?, Object?> sub(String key) =>
        (map[key] as Map<Object?, Object?>?) ?? const {};
    return IconShiftCapabilities(
      platform: platform,
      icon: OperationCapability.fromMap(sub('icon')),
      displayName: OperationCapability.fromMap(sub('displayName')),
      iconAndNameLinked: map['iconAndNameLinked'] as bool? ?? false,
      notes: [...?(map['notes'] as List<Object?>?)?.cast<String>()],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IconShiftCapabilities &&
      other.platform == platform &&
      other.icon == icon &&
      other.displayName == displayName &&
      other.iconAndNameLinked == iconAndNameLinked &&
      listEquals(other.notes, notes);

  @override
  int get hashCode => Object.hash(
    platform,
    icon,
    displayName,
    iconAndNameLinked,
    Object.hashAll(notes),
  );

  @override
  String toString() =>
      'IconShiftCapabilities(${platform?.name ?? 'unknown'}: icon: $icon; '
      'displayName: $displayName'
      '${iconAndNameLinked ? '; linked' : ''})';
}
