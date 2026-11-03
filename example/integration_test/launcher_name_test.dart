// The installed app's launcher name changes at runtime — no rebuild, no
// reinstall:
//   flutter test integration_test/launcher_name_test.dart -d <android device>
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

  testWidgets('a compiled-in name reaches the app entry', (_) async {
    final r = await IconShift.changeLauncherName('IconShift Pro');
    switch (IconShiftPlatform.current) {
      case IconShiftPlatform.android:
        expect(r.isAppEntryChanged, isTrue, reason: '$r');
        expect(
          (await IconShift.getLauncherName()).appEntryName,
          'IconShift Pro',
        );
      case IconShiftPlatform.ios:
        expect(r.scope, LauncherNameScope.unsupported, reason: '$r');
      default:
        expect(r.isSuccessful, isTrue, reason: '$r');
    }
  });
}
