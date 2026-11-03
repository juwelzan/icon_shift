// Runs IconShift against the real platform implementation:
//   flutter test integration_test -d <device>
// (web: flutter drive --driver test_driver/integration_test.dart
//        --target integration_test/plugin_integration_test.dart -d chrome)

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift_example/icon_shift_config.g.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final platform = IconShiftPlatform.current;

  setUpAll(
    () => IconShift.initialize(iconShiftConfig, restoreSelection: false),
  );
  tearDownAll(() async {
    final result = await IconShift.restoreDefault();
    debugPrint('restoreDefault on teardown: $result');
  });

  testWidgets('reports capabilities matching the platform', (_) async {
    final caps = await IconShift.getCapabilities();
    debugPrint('capabilities: $caps');
    expect(caps.platform, platform);
    switch (platform) {
      case IconShiftPlatform.android:
        expect(caps.icon.scope, IdentityScope.launcher);
        expect(caps.iconAndNameLinked, isTrue);
        // The arbitrary name reaches the recent-apps label, and a pinned
        // shortcut carries any name and icon; the app's own launcher entry
        // still only shows what the build compiled in.
        expect(caps.displayName.scope, IdentityScope.taskSwitcher);
        expect(caps.icon.acceptsArbitraryValues, isFalse);
      case IconShiftPlatform.ios:
        expect(caps.icon.isSupported, isTrue);
        expect(caps.displayName.isSupported, isFalse);
      case IconShiftPlatform.macos ||
          IconShiftPlatform.windows ||
          IconShiftPlatform.linux:
        expect(caps.displayName.scope, IdentityScope.windowTitle);
      case IconShiftPlatform.web:
        expect(caps.icon.scope, IdentityScope.browserTab);
      case null:
        fail('unsupported platform');
    }
  });

  testWidgets('configuration and native resources validate', (_) async {
    final validation = await IconShift.validateConfiguration();
    debugPrint('$validation');
    expect(validation.errors, isEmpty);
    if (platform == IconShiftPlatform.android) {
      expect(
        validation.issues.map((i) => i.code),
        isNot(contains('duplicate_launcher')),
      );
    }
    final variants = await IconShift.getVariants();
    expect(variants.map((v) => v.id), ['default', 'dark', 'blue', 'pro']);
    expect(variants.every((v) => v.isAvailable), isTrue, reason: '$variants');
  });

  testWidgets('switches identity, reads it back, restores default', (_) async {
    final dark = await IconShift.setIdentity('dark');
    debugPrint('setIdentity(dark): $dark');
    expect(dark.icon.status, OperationStatus.applied);
    expect(dark.hasFailures, isFalse);

    var state = await IconShift.getCurrentIdentity();
    debugPrint('after dark: $state');
    expect(state.nativeIconVariant, 'dark');
    expect(state.isIconInSync, isTrue);
    switch (platform) {
      case IconShiftPlatform.android ||
          IconShiftPlatform.macos ||
          IconShiftPlatform.windows ||
          IconShiftPlatform.linux ||
          IconShiftPlatform.web:
        expect(state.nativeDisplayName, 'IconShift Dark');
        expect(dark.isComplete, isTrue);
      case IconShiftPlatform.ios:
        expect(dark.displayName.status, OperationStatus.unsupported);
      case null:
        break;
    }

    final again = await IconShift.setIdentity('dark');
    expect(again.icon.status, OperationStatus.unchanged);

    final pro = await IconShift.setIdentity('pro');
    debugPrint('setIdentity(pro): $pro');
    state = await IconShift.getCurrentIdentity();
    // Android: "pro" is its own alias; elsewhere it uses the shipped icon.
    expect(
      state.nativeIconVariant,
      platform == IconShiftPlatform.android ? 'pro' : 'default',
    );

    final restored = await IconShift.restoreDefault();
    debugPrint('restoreDefault: $restored');
    expect(restored.hasFailures, isFalse);
    state = await IconShift.getCurrentIdentity();
    expect(state.nativeIconVariant, 'default');
    expect(state.requestedIconVariant, isNull);
    if (platform == IconShiftPlatform.android) {
      expect(state.nativeDisplayName, 'IconShift Android');
    }
  });

  testWidgets('arbitrary display names follow the capability', (_) async {
    final caps = await IconShift.getCapabilities();
    final result = await IconShift.setDisplayName('Custom Name');
    debugPrint('setDisplayName: $result');
    if (caps.displayName.acceptsArbitraryValues) {
      expect(result.displayName.status, OperationStatus.applied);
      expect(
        (await IconShift.getCurrentIdentity()).nativeDisplayName,
        'Custom Name',
      );
    } else {
      expect(result.displayName.status, OperationStatus.unsupported);
    }

    final batch = await IconShift.setCustomIdentity(
      iconVariant: 'blue',
      displayName: 'Blue Name',
    );
    debugPrint('setCustomIdentity: $batch');
    expect(batch.icon.status, OperationStatus.applied);
    expect(batch.hasFailures, isFalse);
    expect(batch.isComplete, caps.displayName.acceptsArbitraryValues);
  });

  testWidgets('application info comes from the OS', (_) async {
    final info = await IconShift.getApplicationInfo();
    debugPrint('$info');
    switch (platform) {
      case IconShiftPlatform.android:
        expect(info.applicationId, 'com.example.icon_shift_example');
        expect(info.version, isNotNull);
        expect(
          info.currentIconVariant,
          (await IconShift.getCurrentIdentity()).nativeIconVariant,
        );
      case IconShiftPlatform.ios || IconShiftPlatform.macos:
        expect(info.applicationId, 'com.example.iconShiftExample');
        expect(info.version, isNotNull);
      case IconShiftPlatform.web:
        expect(info.applicationId, startsWith('http'));
        expect(info.installationType, InstallationType.browser);
      case IconShiftPlatform.windows || IconShiftPlatform.linux:
        expect(info.executableName, isNotNull);
      case null:
        break;
    }
  });

  testWidgets('platform capabilities and previews are consistent', (_) async {
    final caps = await IconShift.getPlatformCapabilities();
    expect(caps.platform, platform);
    expect(caps.buildTimeOnly, contains(IdentityProperty.applicationId));
    expect(
      caps.runtimeChangeable,
      isNot(contains(IdentityProperty.applicationId)),
    );
    final preview = await IconShift.previewIdentity('dark');
    debugPrint('$preview');
    expect(preview.current!.displayName, isNotNull);
    if (platform == IconShiftPlatform.ios) {
      expect(preview.warnings.map((w) => w.code), contains('name_not_applied'));
    }
  });

  testWidgets('diagnostics are produced', (_) async {
    final report = (await IconShift.getDiagnostics()).toReport();
    debugPrint(report);
    expect(report, contains('platform: ${platform!.name}'));
  });

  test('kIsWeb matches platform', () {
    expect(kIsWeb, platform == IconShiftPlatform.web);
  });
}
