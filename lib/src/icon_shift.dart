import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:meta/meta.dart' show useResult;

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
import 'models/result.dart';
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
  /// Can be called again (e.g. after hot restart) to replace the config.
  static Future<void> initialize(
    IconShiftConfig config, {
    bool restoreSelection = true,
    String? locale,
  }) async {
    final engine = IconShiftEngine(
      platform: IconShiftPlatformInterface.instance,
      targetPlatform: IconShiftPlatform.current,
      locale: locale ?? _deviceLocale(),
    );
    await engine.initialize(config, restoreSelection: restoreSelection);
    _engine = engine;
  }

  static bool get isInitialized => _engine?.isInitialized ?? false;

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
