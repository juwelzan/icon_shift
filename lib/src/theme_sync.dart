import 'dart:async';

import 'package:flutter/widgets.dart';

import 'config/app_identity.dart';
import 'config/icon_shift_config.dart';
import 'config/platform.dart';
import 'icon_shift.dart';
import 'models/result.dart';

/// Opt-in: switches the identity when the *system* brightness changes, using
/// variants whose [AppIdentity.appearance] matches.
///
/// Operating systems do not switch launcher icons with the Flutter theme on
/// their own. This helper makes the switch explicit, with these defaults:
///
/// * **iOS is excluded**: every icon change shows a system alert. Use asset
///   catalog dark/tinted appearances there — iOS 18+ applies them itself.
/// * **Android** is debounced ([debounce]) because each switch makes the
///   launcher rebuild its icon.
///
/// ```dart
/// final sync = IconShiftThemeSync(dark: 'dark', light: 'default')..start();
/// // later: sync.stop();
/// ```
class IconShiftThemeSync with WidgetsBindingObserver {
  IconShiftThemeSync({
    this.light,
    this.dark,
    this.platforms = const {
      IconShiftPlatform.android,
      IconShiftPlatform.macos,
      IconShiftPlatform.windows,
      IconShiftPlatform.linux,
      IconShiftPlatform.web,
    },
    this.debounce = const Duration(seconds: 2),
    this.onResult,
  });

  /// Variant for light mode. Defaults to the first variant with
  /// `appearance: light`, else the default identity.
  final String? light;

  /// Variant for dark mode. Defaults to the first variant with
  /// `appearance: dark`.
  final String? dark;

  /// Platforms on which the sync runs.
  final Set<IconShiftPlatform> platforms;
  final Duration debounce;

  /// Called with the result of each switch.
  final void Function(IconShiftResult result)? onResult;

  Timer? _timer;
  String? _applied;
  bool _started = false;

  bool get isActive => _started;

  /// The variant configured for [brightness], or `null` if none.
  String? variantFor(Brightness brightness) {
    final config = IconShift.config;
    final wanted = brightness == Brightness.dark
        ? IdentityAppearance.dark
        : IdentityAppearance.light;
    final explicit = brightness == Brightness.dark ? dark : light;
    if (explicit != null) return explicit;
    for (final MapEntry(:key, :value) in config.variants.entries) {
      if (value.appearance == wanted) return key;
    }
    return brightness == Brightness.light
        ? IconShiftConfig.defaultVariantId
        : null;
  }

  /// Starts listening and applies the variant for the current brightness.
  void start() {
    final platform = IconShiftPlatform.current;
    if (_started || platform == null || !platforms.contains(platform)) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _apply(Duration.zero);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangePlatformBrightness() => _apply(
    IconShiftPlatform.current == IconShiftPlatform.android
        ? debounce
        : Duration.zero,
  );

  void _apply(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () async {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      final variant = variantFor(brightness);
      if (!_started || variant == null || variant == _applied) return;
      _applied = variant;
      final result = await IconShift.setIdentity(variant);
      onResult?.call(result);
    });
  }
}
