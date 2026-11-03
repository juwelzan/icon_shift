import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/icon_shift_platform_interface.dart';

import 'fakes.dart';

/// Android: the app entry is compiled in, a shortcut takes any name/icon.
const androidWithShortcut = IconShiftCapabilities(
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
  shortcut: OperationCapability(
    isSupported: true,
    scope: IdentityScope.launcherShortcut,
    persistsNatively: true,
    acceptsArbitraryValues: true,
    limitation: 'Shows a shortcut next to the app entry, not instead of it.',
  ),
  iconAndNameLinked: true,
);

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fetched = <Uri>[];
  Future<Uint8List> fetch(
    Uri url, {
    required int maxBytes,
    Map<String, String> headers = const {},
  }) async {
    fetched.add(url);
    if (url.path.contains('missing')) throw Exception('HTTP 404');
    return _png;
  }

  setUp(fetched.clear);

  Future<(FakePlatform, IconShiftEngine)> engine(
    IconShiftCapabilities capabilities, {
    IconShiftPlatform target = IconShiftPlatform.android,
    IconAppearanceMode mode = IconAppearanceMode.light,
  }) async {
    final platform = FakePlatform(capabilities)
      ..aliasLabels = {'default': 'My App', 'dark': 'My App Dark'};
    final e = IconShiftEngine(
      platform: platform,
      targetPlatform: target,
      assetBundle: FakeAssetBundle(demoAssets),
      systemAppearance: () => mode,
      fetch: fetch,
    );
    await e.initialize(demoConfig);
    return (platform, e);
  }

  group('setShortcutIdentity', () {
    test('any name and asset icon; the user is asked once', () async {
      final (platform, e) = await engine(androidWithShortcut);

      final first = await e.setShortcutIdentity(
        name: 'Work Notes',
        icon: const AppIcon.asset('assets/blue.png'),
      );
      expect(first.icon.status, OperationStatus.pending);
      expect(first.displayName.status, OperationStatus.pending);
      final request = platform.shortcutRequests.single;
      expect(request.name, 'Work Notes');
      expect(request.iconKey, 'assets/blue.png');
      expect(request.bytes, isNotNull);

      // Already pinned: updated with no dialog.
      final second = await e.setShortcutIdentity(name: 'Home Notes');
      expect(second.displayName.status, OperationStatus.applied);
      expect(platform.shortcutRequests.last.name, 'Home Notes');
      expect(
        platform.shortcutRequests.last.bytes,
        isNull,
        reason: 'the icon is kept when only the name changes',
      );

      final state = await e.getShortcutIdentity();
      expect(state.isPinned, isTrue);
      expect(state.name, 'Home Notes');
      expect(state.iconKey, 'assets/blue.png');
    });

    test('a variant supplies both name and icon', () async {
      final (platform, e) = await engine(androidWithShortcut);
      await e.setShortcutIdentity(variant: 'dark');
      expect(platform.shortcutRequests.single.name, 'My App Dark');
      expect(platform.shortcutRequests.single.iconKey, 'assets/dark.png');
    });

    test('a server icon is downloaded, dark artwork in dark mode', () async {
      final (platform, e) = await engine(
        androidWithShortcut,
        mode: IconAppearanceMode.dark,
      );
      final remote = RemoteIcon(
        id: 'xmas',
        url: Uri.parse('https://cdn.example.com/xmas.png'),
        dark: Uri.parse('https://cdn.example.com/xmas_dark.png'),
        name: 'Xmas Notes',
      );
      final result = await e.setShortcutIdentity(remoteIcon: remote);
      expect(result.icon.status, OperationStatus.pending);
      expect(fetched.single.path, '/xmas_dark.png');
      expect(platform.shortcutRequests.single.name, 'Xmas Notes');
      expect(platform.shortcutRequests.single.iconKey, 'xmas');
    });

    test('download and asset failures skip the name', () async {
      final (platform, e) = await engine(androidWithShortcut);

      var result = await e.setShortcutIdentity(
        name: 'X',
        remoteIcon: RemoteIcon(
          url: Uri.parse('https://cdn.example.com/missing.png'),
        ),
      );
      expect(result.icon.errorCode, IconShiftErrorCode.downloadFailed);
      expect(result.displayName.status, OperationStatus.skipped);

      result = await e.setShortcutIdentity(
        name: 'X',
        icon: const AppIcon.asset('assets/nope.png'),
      );
      expect(result.icon.errorCode, IconShiftErrorCode.missingAsset);
      expect(platform.shortcutRequests, isEmpty);
    });

    test('an unsupported launcher is reported, not hidden', () async {
      final (platform, e) = await engine(
        iosLike,
        target: IconShiftPlatform.ios,
      );
      final result = await e.setShortcutIdentity(name: 'X');
      expect(result.displayName.status, OperationStatus.unsupported);
      expect(result.displayName.message, contains('home-screen shortcut'));
      expect(platform.shortcutRequests, isEmpty);
    });

    test('a native refusal becomes a failed outcome', () async {
      final (platform, e) = await engine(androidWithShortcut);
      platform.shortcutError = PlatformException(
        code: NativeErrorCodes.notActive,
        message: 'only in the foreground',
      );
      final result = await e.setShortcutIdentity(name: 'X');
      expect(result.displayName.errorCode, IconShiftErrorCode.appNotActive);
      expect(result.displayName.suggestion, contains('foreground'));
    });

    test('removeShortcutIdentity disables it', () async {
      final (platform, e) = await engine(androidWithShortcut);
      await e.setShortcutIdentity(name: 'X', variant: 'dark');
      final result = await e.removeShortcutIdentity('Gone');
      expect(result.icon.status, OperationStatus.applied);
      expect(platform.calls, contains('disableShortcut:Gone'));
      expect((await e.getShortcutIdentity()).isPinned, isFalse);
    });

    test('needs at least one of name, icon, remoteIcon, variant', () async {
      final (_, e) = await engine(androidWithShortcut);
      expect(
        () => e.setShortcutIdentity(),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(
        () => e.setShortcutIdentity(name: 'bad\u0000name'),
        throwsA(isA<InvalidArgumentException>()),
      );
    });
  });

  group('setArbitraryIdentity', () {
    test('Android uses the shortcut, not the app entry', () async {
      final (platform, e) = await engine(androidWithShortcut);
      final result = await e.setArbitraryIdentity(
        name: 'Anything',
        icon: const AppIcon.asset('assets/blue.png'),
      );
      expect(result.operation, IconShiftOperation.setShortcutIdentity);
      expect(platform.shortcutRequests.single.name, 'Anything');
      expect(platform.iconKey, 'default', reason: 'the app entry is untouched');
    });

    test('desktop renames the app itself', () async {
      final (platform, e) = await engine(
        desktopLike,
        target: IconShiftPlatform.macos,
      );
      final result = await e.setArbitraryIdentity(
        name: 'Anything',
        variant: 'dark',
      );
      expect(result.isComplete, isTrue, reason: '$result');
      expect(platform.displayName, 'Anything');
      expect(platform.iconKey, 'dark');
      expect(platform.shortcutRequests, isEmpty);
    });

    test('desktop applies a server icon with the name', () async {
      final (platform, e) = await engine(
        desktopLike,
        target: IconShiftPlatform.macos,
      );
      final result = await e.setArbitraryIdentity(
        name: 'From Server',
        remoteIcon: RemoteIcon(url: Uri.parse('https://cdn.example.com/a.png')),
      );
      expect(result.isComplete, isTrue, reason: '$result');
      expect(platform.displayName, 'From Server');
      expect(platform.iconRequests.last.key, startsWith('remote:'));
    });

    test('iOS applies the icon and reports the name as build-time', () async {
      final (platform, e) = await engine(
        iosLike,
        target: IconShiftPlatform.ios,
      );
      final result = await e.setArbitraryIdentity(
        name: 'Anything',
        variant: 'dark',
      );
      expect(platform.iconKey, 'dark');
      expect(result.displayName.status, OperationStatus.unsupported);
      expect(result.displayName.errorCode, IconShiftErrorCode.buildRequired);
      expect(
        result.displayName.suggestion,
        contains('icon_shift_cli generate'),
      );
    });
  });
}
