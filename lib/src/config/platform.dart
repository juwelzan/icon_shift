import 'package:flutter/foundation.dart';

/// The platforms IconShift has an implementation for.
enum IconShiftPlatform {
  android,
  ios,
  macos,
  windows,
  linux,
  web;

  /// The platform the app is currently running on, or `null` when IconShift
  /// has no implementation for it (for example Fuchsia).
  ///
  /// Honors [debugDefaultTargetPlatformOverride] so it can be faked in tests.
  static IconShiftPlatform? get current {
    if (kIsWeb) return IconShiftPlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => IconShiftPlatform.android,
      TargetPlatform.iOS => IconShiftPlatform.ios,
      TargetPlatform.macOS => IconShiftPlatform.macos,
      TargetPlatform.windows => IconShiftPlatform.windows,
      TargetPlatform.linux => IconShiftPlatform.linux,
      TargetPlatform.fuchsia => null,
    };
  }
}
