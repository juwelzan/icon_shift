// Drives the runtime display-name paths against the real OS:
//   flutter test integration_test/shortcut_test.dart -d <device>
//
// The first pinned-shortcut request shows a system dialog; the test reports
// whether the OS accepted the call and what the launcher shows afterwards.

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

  testWidgets('the platform reports what it can do with a name', (_) async {
    final caps = await IconShift.getCapabilities();
    debugPrint('platform: $platform');
    debugPrint('displayName: ${caps.displayName}');
    debugPrint('shortcut: ${caps.shortcut}');
    debugPrint('canShowArbitraryIdentity: ${caps.canShowArbitraryIdentity}');
    expect(
      caps.canShowArbitraryIdentity,
      platform != IconShiftPlatform.ios,
      reason: 'only iOS has no way to show a name chosen at runtime',
    );
  });

  testWidgets('setArbitraryIdentity applies a name chosen at runtime', (
    _,
  ) async {
    final result = await IconShift.setArbitraryIdentity(
      name: 'Runtime Name',
      variant: 'dark',
    );
    debugPrint('setArbitraryIdentity: $result');
    debugPrint('icon: ${result.icon}');
    debugPrint('name: ${result.displayName}');

    if (platform == IconShiftPlatform.ios) {
      expect(result.displayName.status, OperationStatus.unsupported);
      return;
    }
    expect(
      result.displayName.status,
      anyOf(OperationStatus.applied, OperationStatus.pending),
      reason: 'the OS accepted the name: ${result.displayName}',
    );
  });

  testWidgets('Android: the shortcut carries the name and icon', (_) async {
    if (platform != IconShiftPlatform.android) return;

    var state = await IconShift.getShortcutIdentity();
    debugPrint('shortcut state: $state');
    expect(
      state.isSupported,
      isTrue,
      reason: 'this launcher cannot pin shortcuts: ${state.limitation}',
    );

    // Requesting it twice must not throw, whether or not the user accepted.
    final again = await IconShift.setShortcutIdentity(
      name: 'Second Name',
      icon: const AppIcon.asset('assets/icons/blue.png'),
    );
    debugPrint('second setShortcutIdentity: $again');
    expect(again.hasFailures, isFalse, reason: '$again');

    state = await IconShift.getShortcutIdentity();
    debugPrint('shortcut state after: $state');
    if (state.isPinned) {
      // Accepted earlier: updates are silent and visible immediately.
      expect(state.name, 'Second Name');
      expect(state.iconKey, 'assets/icons/blue.png');
      expect(again.displayName.status, OperationStatus.applied);
    } else {
      expect(again.displayName.status, OperationStatus.pending);
    }
  });

  testWidgets('the recent-apps label takes any string on Android', (_) async {
    if (platform != IconShiftPlatform.android) return;
    final result = await IconShift.setDisplayName('Task Label');
    debugPrint('setDisplayName: $result');
    expect(result.displayName.isSuccessful, isTrue, reason: '$result');
    final state = await IconShift.getCurrentIdentity();
    debugPrint('native display name: ${state.nativeDisplayName}');
    expect(state.nativeDisplayName, 'Task Label');
  });
}
