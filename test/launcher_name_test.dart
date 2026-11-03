import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/icon_shift_platform_interface.dart';

import 'fakes.dart';

const schoolConfig = IconShiftConfig(
  defaultIdentity: AppIdentity(
    name: 'Schoolmate',
    icon: AppIcon.asset('assets/default.png'),
  ),
  variants: {
    'abc': AppIdentity(name: 'ABC School'),
    'xyz': AppIdentity(name: 'XYZ College'),
    'dark': AppIdentity(
      name: 'Night School',
      icon: AppIcon.asset('assets/dark.png'),
    ),
  },
);

/// Android-like: the app entry is the enabled alias, and its label is what
/// the launcher reads — like PackageManager.
class LauncherFake extends FakePlatform {
  LauncherFake(super.capabilities, {this.appEntryLabel});

  String? appEntryLabel;

  @override
  Future<NativeOperationResult> setIcon(NativeIconRequest request) async {
    final result = await super.setIcon(request);
    final label = aliasLabels[request.key];
    if (label != null) appEntryLabel = label;
    return result;
  }

  @override
  Future<ApplicationInfo> getApplicationInfo() async =>
      ApplicationInfo(platform: null, displayName: appEntryLabel);
}

const androidCaps = IconShiftCapabilities(
  platform: IconShiftPlatform.android,
  icon: OperationCapability(
    isSupported: true,
    scope: IdentityScope.launcher,
    persistsNatively: true,
    requiresPreconfiguredResources: true,
  ),
  displayName: OperationCapability(
    isSupported: true,
    scope: IdentityScope.taskSwitcher,
    acceptsArbitraryValues: true,
  ),
  iconAndNameLinked: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(LauncherFake, IconShiftEngine)> android() async {
    final platform = LauncherFake(androidCaps, appEntryLabel: 'Schoolmate')
      ..aliasLabels = {
        'default': 'Schoolmate',
        'abc': 'ABC School',
        'xyz': 'XYZ College',
        'dark': 'Night School',
      };
    final e = IconShiftEngine(
      platform: platform,
      targetPlatform: IconShiftPlatform.android,
      assetBundle: FakeAssetBundle({'assets/default.png', 'assets/dark.png'}),
    );
    await e.initialize(schoolConfig);
    return (platform, e);
  }

  group('Android', () {
    test('a compiled-in name switches the app entry', () async {
      final (platform, e) = await android();
      final r = await e.changeLauncherName('ABC School');
      expect(r.scope, LauncherNameScope.appEntry);
      expect(r.status, OperationStatus.applied);
      expect(r.appEntryName, 'ABC School', reason: 'read back from the OS');
      expect(r.isAppEntryChanged, isTrue);
      expect(platform.iconKey, 'abc');

      // The server later sends another compiled-in name.
      final next = await e.changeLauncherName('XYZ College');
      expect(next.appEntryName, 'XYZ College');
      expect(platform.iconKey, 'xyz');

      // Asking for the same name again changes nothing.
      final again = await e.changeLauncherName('XYZ College');
      expect(again.status, OperationStatus.unchanged);
    });

    test('a variant with its own icon says the icon changed too', () async {
      final (_, e) = await android();
      final r = await e.changeLauncherName('Night School');
      expect(r.isAppEntryChanged, isTrue);
      expect(r.message, contains('icon changed too'));
    });

    test('a name that is not compiled in changes nothing', () async {
      final (platform, e) = await android();
      final r = await e.changeLauncherName('Sunrise Academy');
      expect(r.scope, LauncherNameScope.unsupported);
      expect(r.status, OperationStatus.unsupported);
      expect(r.result.displayName.errorCode, IconShiftErrorCode.buildRequired);
      expect(
        r.appEntryName,
        'Schoolmate',
        reason: 'the app entry is untouched',
      );
      expect(r.availableNames, containsAll(['Schoolmate', 'ABC School']));
      expect(r.message, contains('"ABC School"'));
      expect(platform.iconKey, 'default');
      expect(
        platform.calls.where((c) => !c.startsWith('inspect')),
        isEmpty,
        reason: 'no native call at all: nothing else is created',
      );
    });

    test('getLauncherName and refreshLauncherName read the OS', () async {
      final (platform, e) = await android();
      expect((await e.refreshLauncherName()), isNull);
      await e.changeLauncherName('ABC School');

      // Something switched the alias back behind our back.
      await e.setIdentity('default');
      var info = await e.getLauncherName();
      expect(info.appEntryName, 'Schoolmate');
      expect(info.requestedName, 'ABC School');
      expect(info.canSwitchAppEntry, isTrue);
      expect(info.availableNames, hasLength(4));

      final refreshed = await e.refreshLauncherName();
      expect(refreshed!.appEntryName, 'ABC School');
      info = await e.getLauncherName();
      expect(info.appEntryName, 'ABC School');
    });

    test('a launcher that does not follow is reported, not hidden', () async {
      final (platform, e) = await android();
      platform.aliasLabels['abc'] = 'Stale Name';
      final r = await e.changeLauncherName('ABC School');
      expect(r.status, OperationStatus.failed);
      expect(r.appEntryName, 'Stale Name');
      expect(r.isAppEntryChanged, isFalse);
    });
  });

  test('iOS reports that no public API exists', () async {
    final platform = LauncherFake(iosLike, appEntryLabel: 'Schoolmate');
    final e = IconShiftEngine(
      platform: platform,
      targetPlatform: IconShiftPlatform.ios,
      assetBundle: FakeAssetBundle({'assets/default.png'}),
    );
    await e.initialize(schoolConfig);
    final r = await e.changeLauncherName('ABC School');
    expect(r.scope, LauncherNameScope.unsupported);
    expect(r.status, OperationStatus.unsupported);
    expect(r.appEntryName, 'Schoolmate');
    expect(r.message, contains('no public API'));
    expect(r.result.displayName.errorCode, IconShiftErrorCode.buildRequired);
    expect(platform.iconRequests, isEmpty);
    final info = await e.getLauncherName();
    expect(info.canSwitchAppEntry, isFalse);
  });

  test('desktop uses the window title', () async {
    final platform = LauncherFake(desktopLike);
    final e = IconShiftEngine(
      platform: platform,
      targetPlatform: IconShiftPlatform.macos,
      assetBundle: FakeAssetBundle({'assets/default.png'}),
    );
    await e.initialize(schoolConfig);
    final r = await e.changeLauncherName('ABC School');
    expect(r.scope, LauncherNameScope.windowTitle);
    expect(platform.displayName, 'ABC School');
  });

  test('invalid names are refused before anything runs', () async {
    final (_, e) = await android();
    expect(
      () => e.changeLauncherName(''),
      throwsA(isA<InvalidArgumentException>()),
    );
  });
}
