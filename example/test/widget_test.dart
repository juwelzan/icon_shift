import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/icon_shift_platform_interface.dart';
import 'package:icon_shift_example/icon_shift_config.g.dart';
import 'package:icon_shift_example/main.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A desktop-like fake so the demo UI can be tested without a device.
class _FakePlatform extends IconShiftPlatformInterface
    with MockPlatformInterfaceMixin {
  String iconKey = 'default';
  String title = 'IconShift Demo';

  @override
  Future<IconShiftCapabilities> getCapabilities() async =>
      const IconShiftCapabilities(
        platform: IconShiftPlatform.macos,
        icon: OperationCapability(
          isSupported: true,
          scope: IdentityScope.runningApp,
          acceptsArbitraryValues: true,
        ),
        displayName: OperationCapability(
          isSupported: true,
          scope: IdentityScope.windowTitle,
          acceptsArbitraryValues: true,
        ),
      );

  @override
  Future<NativeIdentityState> getNativeState() async =>
      NativeIdentityState(iconKey: iconKey, displayName: title);

  @override
  Future<NativeOperationResult> setIcon(NativeIconRequest request) async {
    iconKey = request.key;
    return const NativeOperationResult('applied');
  }

  @override
  Future<NativeOperationResult> setDisplayName(String? name) async {
    title = name ?? 'IconShift Demo';
    return const NativeOperationResult('applied');
  }

  @override
  Future<NativeInspection> inspect(List<NativeVariantSpec> variants) async =>
      const NativeInspection();

  @override
  Future<Map<String, String>> loadSelection() async => {};

  @override
  Future<void> saveSelection(Map<String, String> selection) async {}
}

void main() {
  testWidgets('demo lists variants and applies one', (tester) async {
    final fake = _FakePlatform();
    IconShiftPlatformInterface.instance = fake;
    await tester.runAsync(() => IconShift.initialize(iconShiftConfig));

    await tester.pumpWidget(const DemoApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Capabilities (macos)'), findsOneWidget);
    expect(find.byKey(const ValueKey('variant-dark')), findsOneWidget);
    expect(find.text('IconShift Pro'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('identity-dark')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(fake.iconKey, 'dark');
    expect(fake.title, 'IconShift Dark');
    expect(find.textContaining('Done: icon applied'), findsOneWidget);
  });
}
