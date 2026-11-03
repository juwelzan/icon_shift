import 'package:flutter/services.dart';
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

  /// Accept switches without performing them, like a PackageManager that
  /// silently ignored the request.
  bool ignoreSwitches = false;

  @override
  Future<NativeOperationResult> setIcon(NativeIconRequest request) async {
    if (ignoreSwitches) return const NativeOperationResult('applied');
    final result = await super.setIcon(request);
    final label = aliasLabels[request.key];
    if (label != null) appEntryLabel = label;
    return result;
  }

  @override
  Future<ApplicationInfo> getApplicationInfo() async =>
      ApplicationInfo(platform: null, displayName: appEntryLabel);

  /// Extra enabled entries, to simulate a broken manifest.
  Set<String> alsoEnabled = {};

  @override
  Future<List<NativeLauncherIdentity>> getLauncherIdentities() async => [
    for (final MapEntry(key: id, value: label) in aliasLabels.entries)
      NativeLauncherIdentity(
        id: id,
        label: id == iconKey ? (appEntryLabel ?? label) : label,
        enabled: id == iconKey || alsoEnabled.contains(id),
      ),
  ];
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
      expect(r.status, LauncherNameStatus.success);
      expect(r.changed, isTrue);
      expect(r.appliedName, 'ABC School', reason: 'read back from the OS');
      expect(r.isSuccess, isTrue);
      expect(platform.iconKey, 'abc');

      // The server later sends another compiled-in name.
      final next = await e.changeLauncherName('XYZ College');
      expect(next.appliedName, 'XYZ College');
      expect(platform.iconKey, 'xyz');

      // Asking for the same name again changes nothing.
      final again = await e.changeLauncherName('XYZ College');
      expect(again.status, LauncherNameStatus.success);
      expect(again.changed, isFalse, reason: 'already showed it');
    });

    test('a variant with its own icon says the icon changed too', () async {
      final (_, e) = await android();
      final r = await e.changeLauncherName('Night School');
      expect(r.isSuccess, isTrue);
      expect(r.message, contains('icon changed too'));
    });

    test('a name that is not compiled in changes nothing', () async {
      final (platform, e) = await android();
      final r = await e.changeLauncherName('Sunrise Academy');
      expect(r.status, LauncherNameStatus.requiresPreconfiguredLauncher);
      expect(r.isSuccess, isFalse);
      expect(r.appliedName, 'Schoolmate', reason: 'the app entry is untouched');
      expect(r.availableNames, containsAll(['Schoolmate', 'ABC School']));
      expect(r.message, contains('"ABC School"'));
      expect(platform.iconKey, 'default');
      expect(
        platform.calls.where((c) => !c.startsWith('inspect')),
        isEmpty,
        reason: 'no native call at all: nothing else is created',
      );
    });

    test('a native refusal is a platform error, not success', () async {
      final (platform, e) = await android();
      platform.iconError = PlatformException(
        code: NativeErrorCodes.permissionDenied,
        message: 'denied',
      );
      final r = await e.changeLauncherName('ABC School');
      expect(r.status, LauncherNameStatus.platformError);
      expect(r.appliedName, 'Schoolmate');
    });

    test('switching institutions keeps exactly one active entry', () async {
      final (platform, e) = await android();
      for (final name in ['ABC School', 'XYZ College', 'Schoolmate']) {
        final r = await e.changeLauncherName(name);
        expect(r.isSuccess, isTrue, reason: name);
        expect(platform.iconKey, isNot(contains(',')));
      }
      expect(platform.iconKey, 'default');
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
      expect(refreshed!.appliedName, 'ABC School');
      info = await e.getLauncherName();
      expect(info.appEntryName, 'ABC School');
    });

    test('statuses and fields use the documented names', () async {
      final (_, e) = await android();
      final ok = await e.changeLauncherName('ABC School');
      expect(ok.toJson(), {
        'status': 'success',
        'requestedName': 'ABC School',
        'appliedName': 'ABC School',
        'platform': 'android',
        'changed': true,
        'enabledEntries': 1,
        'availableNames': [
          'Schoolmate',
          'ABC School',
          'XYZ College',
          'Night School',
        ],
        'launcherRefresh': 'expected',
      });
      final unknown = await e.changeLauncherName('Sunrise Academy');
      expect(unknown.statusCode, 'requires_preconfigured_launcher');
      expect(unknown.launcherRefresh, LauncherRefresh.notApplicable);
    });

    test('an unknown name is never mapped to another identity', () async {
      final (platform, e) = await android();
      for (final near in ['abc school', 'ABC School ', 'ABC', 'XYZ']) {
        final r = await e.changeLauncherName(near.trim().isEmpty ? 'x' : near);
        expect(
          r.status,
          LauncherNameStatus.requiresPreconfiguredLauncher,
          reason: '"$near" must not match "ABC School"',
        );
      }
      expect(platform.iconKey, 'default');
    });

    test('two enabled entries are a failure, not success', () async {
      final (platform, e) = await android();
      platform.alsoEnabled = {'xyz'};
      final r = await e.changeLauncherName('ABC School');
      expect(r.status, LauncherNameStatus.failed);
      expect(r.enabledEntries, 2);
    });

    test('a switch the OS did not perform is a failure', () async {
      final (platform, e) = await android();
      platform.ignoreSwitches = true;
      final r = await e.changeLauncherName('ABC School');
      expect(r.status, LauncherNameStatus.failed);
      expect(r.appliedName, 'Schoolmate', reason: 'read back from the OS');
      expect(r.isSuccess, isFalse, reason: 'never success without the OS');
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
    expect(r.status, LauncherNameStatus.requiresNewBuild);
    expect(r.appliedName, 'Schoolmate');
    expect(r.message, contains('no public API'));
    expect(r.result.displayName.errorCode, IconShiftErrorCode.buildRequired);
    expect(platform.iconRequests, isEmpty);
    final info = await e.getLauncherName();
    expect(info.canSwitchAppEntry, isFalse);
  });

  test('desktop has no launcher name and touches nothing', () async {
    final platform = LauncherFake(desktopLike);
    final e = IconShiftEngine(
      platform: platform,
      targetPlatform: IconShiftPlatform.macos,
      assetBundle: FakeAssetBundle({'assets/default.png'}),
    );
    await e.initialize(schoolConfig);
    final r = await e.changeLauncherName('ABC School');
    expect(r.status, LauncherNameStatus.unsupported);
    expect(platform.displayName, 'Shipped', reason: 'window title untouched');
  });

  test('invalid names are refused before anything runs', () async {
    final (_, e) = await android();
    expect(
      () => e.changeLauncherName(''),
      throwsA(isA<InvalidArgumentException>()),
    );
  });
}
