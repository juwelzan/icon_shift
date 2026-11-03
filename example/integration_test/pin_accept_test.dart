// Proves the full Android path: request the shortcut, wait for the user to
// accept the system dialog, then rename it live with no dialog.
//
//   flutter test integration_test/pin_accept_test.dart -d <device>
//
// Accept the "Add to home screen" dialog when it appears.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift_example/icon_shift_config.g.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(
    () => IconShift.initialize(iconShiftConfig, restoreSelection: false),
  );

  testWidgets('a pinned shortcut is renamed while the app runs', (_) async {
    if (IconShiftPlatform.current != IconShiftPlatform.android) return;

    var state = await IconShift.getShortcutIdentity();
    if (!state.isPinned) {
      final request = await IconShift.setShortcutIdentity(
        name: 'Pinned Name',
        variant: 'dark',
      );
      debugPrint('request: ${request.displayName}');
      for (var i = 0; i < 90 && !state.isPinned; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        state = await IconShift.getShortcutIdentity();
      }
    }
    debugPrint('after the dialog: $state');
    expect(
      state.isPinned,
      isTrue,
      reason: 'the "add to home screen" dialog was not accepted',
    );

    // The user accepted once; from here the name and icon change silently.
    final renamed = await IconShift.setShortcutIdentity(
      name: 'Renamed Live',
      icon: const AppIcon.asset('assets/icons/blue.png'),
    );
    debugPrint('silent rename: ${renamed.displayName}');
    expect(renamed.displayName.status, OperationStatus.applied);

    final after = await IconShift.getShortcutIdentity();
    debugPrint('launcher now shows: $after');
    expect(after.name, 'Renamed Live');
    expect(after.iconKey, 'assets/icons/blue.png');

    final again = await IconShift.setShortcutIdentity(name: 'Third Name');
    debugPrint('second silent rename: ${again.displayName}');
    expect(again.displayName.status, OperationStatus.applied);
    expect((await IconShift.getShortcutIdentity()).name, 'Third Name');
  });
}
