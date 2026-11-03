// Checks the demo's wording against the real platform.
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

  testWidgets('a custom name reaches the recent-apps label', (_) async {
    if (IconShiftPlatform.current != IconShiftPlatform.android) return;
    final first = await IconShift.setDisplayName('Demo Name One');
    debugPrint(
      'FIRST: ${first.displayName.status} | ${first.displayName.message}',
    );
    expect(first.displayName.status, OperationStatus.applied);

    final again = await IconShift.setDisplayName('Demo Name One');
    debugPrint('AGAIN: ${again.displayName.status}');
    expect(
      again.displayName.status,
      OperationStatus.unchanged,
      reason: 'the same name is already in effect',
    );

    final state = await IconShift.getCurrentIdentity();
    debugPrint('NATIVE: ${state.nativeDisplayName}');
    expect(state.nativeDisplayName, 'Demo Name One');
  });
}
