import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show Brightness, WidgetsBinding, WidgetsBindingObserver;
import 'package:meta/meta.dart' show useResult;

import 'config/app_identity.dart';
import 'config/icon_shift_config.dart';
import 'config/platform.dart';
import 'engine.dart';
import 'exceptions.dart';
import 'models/application_info.dart';
import 'models/capabilities.dart';
import 'models/diagnostics.dart';
import 'models/identity_properties.dart';
import 'models/identity_variant.dart';
import 'models/preview.dart';
import 'models/remote_icon.dart';
import 'models/result.dart';
import 'models/shortcut_identity.dart';
import 'models/state.dart';
import 'models/validation.dart';
import 'platform/icon_shift_platform_interface.dart';

/// Switches the app's icon and display name between preconfigured variants.
///
/// ```dart
/// await IconShift.initialize(config);
/// final result = await IconShift.setIdentity('dark');
/// if (!result.isComplete) print(result);
/// ```
///
/// What each platform can change is described by [getCapabilities] and in
/// `docs/PLATFORM_CAPABILITIES.md`. Methods that change the identity never
/// throw for OS limitations; they return an [IconShiftResult] describing
/// what happened to the icon and the name. They throw an
/// [IconShiftException] only for programming errors (not initialized,
/// unknown variant, invalid name).
abstract final class IconShift {
  static IconShiftEngine? _engine;

  static IconShiftEngine get _require =>
      _engine ?? (throw const NotInitializedException());

  /// Validates [config], reads the platform's capabilities and the saved
  /// selection, and — on platforms where changes do not survive a restart
  /// (macOS, Windows, Linux, web) — re-applies the saved selection unless
  /// [restoreSelection] is `false`.
  ///
  /// Throws [InvalidConfigurationException] when [config] has errors. In
  /// debug builds, warnings from [validateConfiguration] are printed.
  ///
  /// Names are localized for [locale] (`de`, `pt_BR`; default: the device
  /// locale) where [AppIdentity.localizedNames] are configured.
  ///
  /// With [followSystemAppearance] (the default), platforms that apply
  /// icon images at runtime (macOS, Windows, Linux, web) show the
  /// [IconAppearances.dark] artwork of the current icon while the system is
  /// in dark mode, and switch back when it changes. iOS needs no help: it
  /// picks the dark/tinted artwork compiled into the icon set itself.
  ///
  /// Can be called again (e.g. after hot restart) to replace the config.
  static Future<void> initialize(
    IconShiftConfig config, {
    bool restoreSelection = true,
    String? locale,
    bool followSystemAppearance = true,
  }) async {
    final engine = IconShiftEngine(
      platform: IconShiftPlatformInterface.instance,
      targetPlatform: IconShiftPlatform.current,
      locale: locale ?? _deviceLocale(),
      systemAppearance: followSystemAppearance ? _systemAppearance : null,
      displayNameNotifier: _displayName,
    );
    await engine.initialize(config, restoreSelection: restoreSelection);
    _engine = engine;
    _AppearanceObserver.instance.enabled = followSystemAppearance;
  }

  static bool get isInitialized => _engine?.isInitialized ?? false;

  static final _displayName = ValueNotifier<String?>(null);

  /// The name the app currently presents: the custom name from
  /// [setDisplayName], else the selected variant's name (localized).
  ///
  /// Bind `MaterialApp.title` to it. Flutter writes that title into the
  /// Android recent-apps label and the web document title on every rebuild,
  /// which would otherwise undo [setDisplayName] / [setIdentity]:
  ///
  /// ```dart
  /// ValueListenableBuilder<String?>(
  ///   valueListenable: IconShift.displayNameListenable,
  ///   builder: (context, name, _) => MaterialApp(title: name ?? 'My App'),
  /// )
  /// ```
  static ValueListenable<String?> get displayNameListenable => _displayName;

  /// The configuration passed to [initialize].
  static IconShiftConfig get config => _require.config;

  /// Applies the icon and display name of [variantId]. Use
  /// [IconShiftConfig.defaultVariantId] or [restoreDefault] for the default.
  ///
  /// The icon is changed first; if it fails, the name is skipped so icon and
  /// name do not end up from different variants.
  @useResult
  static Future<IconShiftResult> setIdentity(String variantId) =>
      _require.setIdentity(variantId);

  /// Applies only the icon of [variantId].
  ///
  /// Where icon and label are linked (Android), this also applies the
  /// variant's label; [IconShiftResult.displayName] reports it.
  @useResult
  static Future<IconShiftResult> setIcon(String variantId) =>
      _require.setIcon(variantId);

  /// Sets an arbitrary display name where the platform allows it (window
  /// title on desktop, document title on web). Returns an unsupported
  /// outcome on Android and iOS.
  ///
  /// Throws [InvalidArgumentException] for an empty name, control characters
  /// or more than 255 characters.
  @useResult
  static Future<IconShiftResult> setDisplayName(String name) =>
      _require.setDisplayName(name);

  /// Changes the icon to that of [iconVariant] and the name to
  /// [displayName] in one call. At least one must be given. Both are
  /// validated before anything is applied.
  @useResult
  static Future<IconShiftResult> setCustomIdentity({
    String? iconVariant,
    String? displayName,
  }) => _require.setCustomIdentity(
    iconVariant: iconVariant,
    displayName: displayName,
  );

  /// Applies an icon published by a server. On macOS, Windows and Linux it
  /// is downloaded and shown (its dark artwork in dark mode); on web the URL
  /// becomes the favicon. iOS and Android cannot show a downloaded launcher
  /// icon: there IconShift switches to [RemoteIcon.variant] when it is part
  /// of this build, and otherwise returns an unsupported outcome.
  ///
  /// The selection is saved and re-applied on the next launch (downloading
  /// again where needed).
  @useResult
  static Future<IconShiftResult> setRemoteIcon(RemoteIcon icon) =>
      _require.setRemoteIcon(icon);

  /// Shows [name] and an icon in the strongest way the platform allows,
  /// so one call changes the visible identity everywhere:
  ///
  /// | Platform | What it changes |
  /// | --- | --- |
  /// | macOS, Windows, Linux | Dock/taskbar icon and window title |
  /// | Web | favicon and document title |
  /// | Android | a home-screen shortcut with exactly this name and icon (the app entry itself can only show values compiled into the build) |
  /// | iOS | the icon of [variant]; the name cannot change at runtime at all |
  ///
  /// On Android the first call shows the system's "add to home screen"
  /// dialog; after the user accepts once, every later call is silent. Use
  /// [setShortcutIdentity] directly when you want that behaviour
  /// explicitly, and [getCapabilities] to know what will happen
  /// ([IconShiftCapabilities.canShowArbitraryIdentity]).
  @useResult
  static Future<IconShiftResult> setArbitraryIdentity({
    String? variant,
    String? name,
    AppIcon? icon,
    RemoteIcon? remoteIcon,
  }) => _require.setArbitraryIdentity(
    variant: variant,
    name: name,
    icon: icon,
    remoteIcon: remoteIcon,
  );

  /// Puts [name] and an icon on a home-screen shortcut IconShift owns, the
  /// only launcher entry whose name and image can be chosen while the app
  /// runs (Android 8+ with a launcher that supports pinning).
  ///
  /// ```dart
  /// await IconShift.setShortcutIdentity(
  ///   name: 'Work Notes',
  ///   icon: AppIcon.asset('assets/icons/work.png'),
  /// );
  /// // or straight from a server:
  /// await IconShift.setShortcutIdentity(remoteIcon: icon, name: icon.name);
  /// ```
  ///
  /// The icon comes from [remoteIcon] (downloaded), [icon] (a bundled asset)
  /// or the icon of [variant]; the name from [name], else the remote icon's
  /// or that variant's name. The first call asks the user to place the
  /// shortcut (the result is then `pending`); later calls update it with no
  /// dialog. The shortcut is an **extra** entry: the app's own name and icon
  /// in the app drawer and settings stay as built.
  @useResult
  static Future<IconShiftResult> setShortcutIdentity({
    String? variant,
    String? name,
    AppIcon? icon,
    RemoteIcon? remoteIcon,
  }) => _require.setShortcutIdentity(
    variant: variant,
    name: name,
    icon: icon,
    remoteIcon: remoteIcon,
  );

  /// The home-screen shortcut as the launcher shows it: whether it is
  /// supported, whether the user placed it, and its current name and icon.
  static Future<ShortcutIdentityState> getShortcutIdentity() =>
      _require.getShortcutIdentity();

  /// Disables the shortcut, showing [message] when it is tapped. No app may
  /// take a shortcut off the home screen; only the user can.
  /// [setShortcutIdentity] enables it again.
  @useResult
  static Future<IconShiftResult> removeShortcutIdentity({
    String message = 'This shortcut is no longer available.',
  }) => _require.removeShortcutIdentity(message);

  /// Downloads the [RemoteIcon] JSON at [url] (https only). Throws
  /// [InvalidArgumentException] when it cannot be fetched or parsed.
  ///
  /// ```dart
  /// final icon = await IconShift.fetchRemoteIcon(
  ///   Uri.parse('https://example.com/app-icon.json'),
  /// );
  /// final result = await IconShift.setRemoteIcon(icon);
  /// ```
  static Future<RemoteIcon> fetchRemoteIcon(Uri url) =>
      _require.fetchRemoteIcon(url);

  /// Re-applies the current icon for the system appearance. Called
  /// automatically when it changes unless `followSystemAppearance: false`.
  static Future<IconShiftResult?> refreshAppearance() =>
      _require.refreshAppearance();

  /// Restores the icon and name the app ships with and clears the saved
  /// selection.
  @useResult
  static Future<IconShiftResult> restoreDefault() => _require.restoreDefault();

  /// The requested and the OS-reported identity.
  static Future<IconShiftState> getCurrentIdentity() =>
      _require.getCurrentIdentity();

  /// What this platform lets IconShift change.
  static Future<IconShiftCapabilities> getCapabilities() =>
      _require.getCapabilities();

  /// All variants (default first) resolved for this platform, with
  /// availability, for building a picker.
  static Future<List<IdentityVariant>> getVariants() => _require.getVariants();

  /// Checks the configuration, that icon assets are bundled, and that the
  /// native resources each variant needs exist in this build.
  static Future<IconShiftValidationResult> validateConfiguration() =>
      _require.validateConfiguration();

  /// Platform, capabilities, state and validation in one report.
  static Future<IconShiftDiagnostics> getDiagnostics() =>
      _require.getDiagnostics();

  /// What this platform allows for every identity property — runtime,
  /// build-time only, reinstall/signing implications — plus the live
  /// runtime capabilities.
  static Future<PlatformCapabilities> getPlatformCapabilities() =>
      _require.getPlatformCapabilities();

  /// Identity metadata the OS exposes about the running app (display name,
  /// application/bundle id, version, installation type, current icon).
  static Future<ApplicationInfo> getApplicationInfo() =>
      _require.getApplicationInfo();

  /// What [setIdentity] with [variantId] would do here and on every
  /// platform, with warnings, without changing anything.
  static Future<IdentityPreview> previewIdentity(String variantId) =>
      _require.previewIdentity(variantId);

  /// Forgets the saved selection (it will not be re-applied on launch)
  /// without changing what the OS currently shows. Use [restoreDefault] to
  /// also reset the visible identity.
  static Future<void> clearSavedSelection() => _require.clearSavedSelection();

  static IconAppearanceMode _systemAppearance() {
    try {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark
          ? IconAppearanceMode.dark
          : IconAppearanceMode.light;
    } on Object {
      return IconAppearanceMode.light; // Binding not initialized.
    }
  }

  static String? _deviceLocale() {
    try {
      return WidgetsBinding.instance.platformDispatcher.locale.toString();
    } on Object {
      return null; // Binding not initialized (pure Dart tests).
    }
  }

  /// Replaces the engine, for tests of code that uses [IconShift].
  @visibleForTesting
  static set debugEngine(IconShiftEngine? engine) => _engine = engine;
}

/// Calls [IconShift.refreshAppearance] when the system brightness changes.
class _AppearanceObserver with WidgetsBindingObserver {
  static final instance = _AppearanceObserver();

  bool _registered = false;

  set enabled(bool value) {
    if (value == _registered) return;
    try {
      if (value) {
        WidgetsBinding.instance.addObserver(this);
      } else {
        WidgetsBinding.instance.removeObserver(this);
      }
      _registered = value;
    } on Object {
      // Binding not initialized (pure Dart tests): nothing to observe.
    }
  }

  @override
  void didChangePlatformBrightness() {
    final engine = IconShift._engine;
    if (engine == null || !engine.isInitialized) return;
    engine.refreshAppearance().then((result) {
      if (result != null && !result.isComplete) {
        debugPrint(
          'IconShift: applying the icon for the new appearance: $result',
        );
      }
    }, onError: (Object e) => debugPrint('IconShift: $e'));
  }
}
