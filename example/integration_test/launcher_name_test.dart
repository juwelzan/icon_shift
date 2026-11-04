// The installed app's launcher name changes at runtime — no rebuild, no
// reinstall:
//   flutter test integration_test/launcher_name_test.dart -d <device>
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift_example/icon_shift_config.g.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => IconShift.initialize(iconShiftConfig, restoreSelection: false),
  );
  tearDownAll(() async => IconShift.restoreDefault());

  testWidgets('a compiled-in name reaches the launcher entry', (_) async {
    final r = await IconShift.changeLauncherName('IconShift Pro');
    switch (IconShiftPlatform.current) {
      case IconShiftPlatform.android:
        expect(r.status.name, 'success', reason: '$r');
        expect(
          (await IconShift.getLauncherName()).appEntryName,
          'IconShift Pro',
        );
        final unknown = await IconShift.changeLauncherName('Not In The APK');
        expect(
          unknown.status,
          'requiresPreconfiguredLauncher',
        );
        expect(unknown.appliedName, 'IconShift Pro');
      case IconShiftPlatform.ios:
        expect(r.status.name, 'requiresNewBuild', reason: '$r');
      default:
        expect(r.status.name, 'unsupported', reason: '$r');
    }
  });
}
