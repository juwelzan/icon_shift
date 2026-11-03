import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/src/engine.dart';

import 'fakes.dart';

const appearanceConfig = IconShiftConfig(
  defaultIdentity: AppIdentity(
    name: 'Notes',
    icon: AppIcon.asset('assets/default.png'),
    appearances: IconAppearances(
      dark: AppIcon.asset('assets/default_dark.png'),
    ),
  ),
  variants: {
    'night': AppIdentity(
      name: 'Notes Night',
      icon: AppIcon.asset('assets/night.png'),
      appearances: IconAppearances(
        dark: AppIcon.asset('assets/night_dark.png'),
        tinted: AppIcon.asset('assets/night_tinted.png'),
        clear: AppIcon.asset('assets/night_clear.png'),
      ),
    ),
    'plain': AppIdentity(icon: AppIcon.asset('assets/plain.png')),
    'pro': AppIdentity(name: 'Notes Pro'),
  },
);

const appearanceAssets = {
  'assets/default.png',
  'assets/default_dark.png',
  'assets/night.png',
  'assets/night_dark.png',
  'assets/night_tinted.png',
  'assets/night_clear.png',
  'assets/plain.png',
};

/// Android as the plugin reports it: arbitrary names go to the task label.
const androidTaskLabel = IconShiftCapabilities(
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

final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IconAppearances', () {
    test('travel with the icon they belong to', () {
      final night = appearanceConfig.resolve('night', IconShiftPlatform.ios);
      expect(
        night.iconFor(IconAppearanceMode.tinted)?.path,
        'assets/night_tinted.png',
      );
      expect(night.iconFor(IconAppearanceMode.light)?.path, 'assets/night.png');

      final pro = appearanceConfig.resolve('pro', IconShiftPlatform.macos);
      expect(
        pro.appearances.dark?.path,
        'assets/default_dark.png',
        reason: 'uses the default icon, so its dark artwork too',
      );

      final plain = appearanceConfig.resolve('plain', IconShiftPlatform.macos);
      expect(
        plain.appearances.isEmpty,
        isTrue,
        reason: 'own icon without own artwork',
      );
      expect(plain.iconFor(IconAppearanceMode.dark)?.path, 'assets/plain.png');
    });

    test('a platform icon replaces the shared artwork', () {
      const config = IconShiftConfig(
        defaultIdentity: AppIdentity(
          icon: AppIcon.asset('a.png'),
          appearances: IconAppearances(dark: AppIcon.asset('a_dark.png')),
          platforms: {
            IconShiftPlatform.web: IdentityOverride(
              icon: AppIcon.asset('favicon.png'),
            ),
            IconShiftPlatform.linux: IdentityOverride(
              appearances: IconAppearances(dark: AppIcon.asset('l.png')),
            ),
          },
        ),
      );
      expect(
        config.resolve('default', IconShiftPlatform.web).appearances.dark,
        isNull,
      );
      expect(
        config.resolve('default', IconShiftPlatform.linux).appearances.dark,
        const AppIcon.asset('l.png'),
      );
    });
  });

  group('system appearance on desktop', () {
    late FakePlatform platform;
    var mode = IconAppearanceMode.dark;

    Future<IconShiftEngine> engine({Map<String, String>? selection}) async {
      platform = FakePlatform(desktopLike, selection: selection);
      final e = IconShiftEngine(
        platform: platform,
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle(appearanceAssets),
        systemAppearance: () => mode,
      );
      await e.initialize(appearanceConfig);
      return e;
    }

    setUp(() => mode = IconAppearanceMode.dark);

    test('dark mode shows the dark artwork, including the default', () async {
      final e = await engine();
      expect(
        platform.calls,
        contains('setIcon:default@dark'),
        reason: 'initialize applies the default dark artwork',
      );

      final result = await e.setIdentity('night');
      expect(result.icon.status, OperationStatus.applied);
      final request = platform.iconRequests.last;
      expect(request.key, 'night@dark');
      expect(request.assetKey, 'assets/night_dark.png');
      expect((await e.getCurrentIdentity()).nativeIconVariant, 'night');
      expect(
        platform.savedSelection['icon'],
        'night',
        reason: 'the selection stores the variant, not the artwork',
      );
    });

    test('refreshAppearance follows a system change', () async {
      final e = await engine();
      (await e.setIdentity('night')).throwIfFailed();
      mode = IconAppearanceMode.light;
      final changed = await e.refreshAppearance();
      expect(changed?.icon.status, OperationStatus.applied);
      expect(platform.iconRequests.last.key, 'night');
      expect(platform.iconRequests.last.assetKey, 'assets/night.png');
      expect(await e.refreshAppearance(), isNull, reason: 'nothing changed');
    });

    test('light mode leaves the shipped icon alone at launch', () async {
      mode = IconAppearanceMode.light;
      await engine();
      expect(platform.calls.where((c) => c.startsWith('setIcon')), isEmpty);
    });

    test('iOS is left to the OS', () async {
      final ios = FakePlatform(iosLike);
      final e = IconShiftEngine(
        platform: ios,
        targetPlatform: IconShiftPlatform.ios,
        assetBundle: FakeAssetBundle(appearanceAssets),
        systemAppearance: () => IconAppearanceMode.dark,
      );
      await e.initialize(appearanceConfig);
      await e.setIdentity('night');
      expect(ios.iconRequests.single.key, 'night');
      expect(await e.refreshAppearance(), isNull);
    });
  });

  group('remote icons', () {
    final fetched = <Uri>[];
    Uint8List body = _png;

    Future<Uint8List> fetch(Uri url, {required int maxBytes}) async {
      fetched.add(url);
      if (url.path.endsWith('.json')) {
        return utf8.encode(
          jsonEncode({
            'id': 'xmas',
            'variant': 'night',
            'icon': 'xmas.png',
            'appearances': {'dark': '/dark/xmas.png'},
          }),
        );
      }
      if (url.path.contains('missing')) throw Exception('HTTP 404');
      return body;
    }

    IconShiftEngine engineFor(
      FakePlatform platform,
      IconShiftPlatform target, {
      IconAppearanceMode mode = IconAppearanceMode.light,
    }) => IconShiftEngine(
      platform: platform,
      targetPlatform: target,
      assetBundle: FakeAssetBundle(appearanceAssets),
      systemAppearance: () => mode,
      fetch: fetch,
    );

    setUp(() {
      fetched.clear();
      body = _png;
    });

    test('parses JSON with relative URLs and rejects insecure ones', () async {
      final e = engineFor(FakePlatform(desktopLike), IconShiftPlatform.macos);
      await e.initialize(appearanceConfig);
      final icon = await e.fetchRemoteIcon(
        Uri.parse('https://cdn.example.com/icons/today.json'),
      );
      expect(icon.url, Uri.parse('https://cdn.example.com/icons/xmas.png'));
      expect(icon.dark, Uri.parse('https://cdn.example.com/dark/xmas.png'));
      expect(icon.variant, 'night');
      expect(icon.key, 'xmas');

      expect(
        () => RemoteIcon.fromJson({'icon': 'http://evil.example.com/a.png'}),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(
        () => RemoteIcon.fromJson({'name': 'x'}),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(RemoteIcon.decode(jsonEncode(icon.toJson())), icon);
    });

    test('desktop downloads, applies, saves and restores', () async {
      final platform = FakePlatform(desktopLike);
      var e = engineFor(
        platform,
        IconShiftPlatform.macos,
        mode: IconAppearanceMode.dark,
      );
      await e.initialize(appearanceConfig);
      final remote = RemoteIcon(
        id: 'xmas',
        url: Uri.parse('https://cdn.example.com/xmas.png'),
        dark: Uri.parse('https://cdn.example.com/xmas_dark.png'),
        name: 'Xmas Notes',
      );
      final result = await e.setRemoteIcon(remote);
      expect(result.isComplete, isTrue, reason: '$result');
      expect(platform.iconRequests.last.key, 'remote:xmas@dark');
      expect(platform.iconRequests.last.bytes, _png);
      expect(fetched.last.path, '/xmas_dark.png');
      expect(platform.displayName, 'Xmas Notes');
      expect(e.displayName.value, 'Xmas Notes');

      // Next launch: downloaded again and re-applied.
      final relaunched = FakePlatform(
        desktopLike,
        selection: platform.savedSelection,
      );
      e = engineFor(relaunched, IconShiftPlatform.macos);
      await e.initialize(appearanceConfig);
      expect(relaunched.iconRequests.single.key, 'remote:xmas');

      // A variant replaces the remote icon.
      await e.setIdentity('plain');
      expect(relaunched.savedSelection.containsKey('remote'), isFalse);
    });

    test('download failures and non-images are reported', () async {
      final platform = FakePlatform(desktopLike);
      final e = engineFor(platform, IconShiftPlatform.macos);
      await e.initialize(appearanceConfig);

      var result = await e.setRemoteIcon(
        RemoteIcon(url: Uri.parse('https://cdn.example.com/missing.png')),
      );
      expect(result.icon.errorCode, IconShiftErrorCode.downloadFailed);

      body = Uint8List.fromList(utf8.encode('<html>'));
      result = await e.setRemoteIcon(
        RemoteIcon(
          url: Uri.parse('https://cdn.example.com/page.png'),
          name: 'Never',
        ),
      );
      expect(result.icon.errorCode, IconShiftErrorCode.downloadFailed);
      expect(result.displayName.status, OperationStatus.skipped);
      expect(platform.iconRequests, isEmpty);
      expect(platform.savedSelection, isEmpty);
    });

    test('web uses the URL as favicon without downloading', () async {
      final platform = FakePlatform(desktopLike);
      final e = engineFor(platform, IconShiftPlatform.web);
      await e.initialize(appearanceConfig);
      await e.setRemoteIcon(
        RemoteIcon(url: Uri.parse('https://cdn.example.com/fav.png')),
      );
      expect(fetched, isEmpty);
      expect(
        platform.iconRequests.last.url,
        Uri.parse('https://cdn.example.com/fav.png'),
      );
    });

    test('iOS/Android switch to the bundled variant or explain', () async {
      final platform = FakePlatform(iosLike);
      final e = engineFor(platform, IconShiftPlatform.ios);
      await e.initialize(appearanceConfig);

      final fallback = await e.setRemoteIcon(
        RemoteIcon(
          url: Uri.parse('https://cdn.example.com/x.png'),
          variant: 'night',
        ),
      );
      expect(fallback.operation, IconShiftOperation.setRemoteIcon);
      expect(platform.iconKey, 'night');
      expect(fetched, isEmpty);

      final unsupported = await e.setRemoteIcon(
        RemoteIcon(url: Uri.parse('https://cdn.example.com/x.png')),
      );
      expect(unsupported.icon.status, OperationStatus.unsupported);
      expect(unsupported.icon.errorCode, IconShiftErrorCode.buildRequired);
    });
  });

  group('Android names', () {
    test('custom names go to the task label; variants reset it', () async {
      final platform = FakePlatform(androidTaskLabel)
        ..aliasLabels = {'default': 'Notes', 'pro': 'Notes Pro'};
      final e = IconShiftEngine(
        platform: platform,
        targetPlatform: IconShiftPlatform.android,
        assetBundle: FakeAssetBundle(appearanceAssets),
      );
      await e.initialize(appearanceConfig);
      expect(e.displayName.value, 'Notes');

      final named = await e.setDisplayName('Work Notes');
      expect(named.displayName.status, OperationStatus.applied);
      expect(platform.savedSelection['name'], 'Work Notes');
      expect(e.displayName.value, 'Work Notes');

      final pro = await e.setIdentity('pro');
      expect(pro.isComplete, isTrue, reason: '$pro');
      expect(
        platform.savedSelection.containsKey('name'),
        isFalse,
        reason: 'the alias label replaces the custom name',
      );
      expect(e.displayName.value, 'Notes Pro');
    });
  });
}
