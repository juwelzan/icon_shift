@TestOn('browser')
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/icon_shift_platform_interface.dart';
import 'package:icon_shift/icon_shift_web.dart';
import 'package:web/web.dart' as web;

List<web.HTMLLinkElement> iconLinks() {
  final nodes = web.document.querySelectorAll('link[rel~="icon"]');
  return [
    for (var i = 0; i < nodes.length; i++) nodes.item(i)! as web.HTMLLinkElement,
  ];
}

void addFavicon(String href) {
  web.document.head!.append(
    (web.document.createElement('link') as web.HTMLLinkElement)
      ..rel = 'icon'
      ..href = href,
  );
}

void main() {
  late IconShiftWeb platform;

  setUp(() {
    for (final link in iconLinks()) {
      link.remove();
    }
    web.window.localStorage.removeItem(IconShiftWeb.storageKey);
    web.document.title = 'Original';
    platform = IconShiftWeb();
  });

  test('capabilities are browser-tab scoped and arbitrary', () async {
    final caps = await platform.getCapabilities();
    expect(caps.platform, IconShiftPlatform.web);
    expect(caps.icon.scope, IdentityScope.browserTab);
    expect(caps.displayName.acceptsArbitraryValues, isTrue);
    expect(caps.icon.persistsNatively, isFalse);
    expect(caps.icon.limitation, contains('PWA'));
  });

  test('replaces existing favicons and restores them', () async {
    addFavicon('/favicon.png');
    addFavicon('/favicon-32.png');

    final result = await platform.setIcon(
      const NativeIconRequest(key: 'dark', assetKey: 'assets/icons/dark.png'),
    );
    expect(result.status, 'applied');
    final links = iconLinks();
    expect(links, hasLength(1));
    expect(links.single.href, contains('assets/icons/dark.png'));
    expect(links.single.type, 'image/png');
    expect((await platform.getNativeState()).iconKey, 'dark');

    // A second variant replaces ours, not the originals.
    await platform.setIcon(
      const NativeIconRequest(key: 'blue', assetKey: 'assets/icons/blue.png'),
    );
    expect(iconLinks().single.href, contains('blue.png'));

    final restored = await platform.setIcon(
      const NativeIconRequest(key: defaultIconKey),
    );
    expect(restored.status, 'applied');
    expect(iconLinks().map((l) => Uri.parse(l.href).path), [
      '/favicon.png',
      '/favicon-32.png',
    ]);
    expect((await platform.getNativeState()).iconKey, defaultIconKey);
  });

  test('works without any favicon link in the page', () async {
    await platform.setIcon(
      const NativeIconRequest(key: 'dark', assetKey: 'assets/icons/dark.svg'),
    );
    expect(iconLinks().single.type, 'image/svg+xml');
    await platform.setIcon(const NativeIconRequest(key: defaultIconKey));
    expect(iconLinks(), isEmpty);
  });

  test('same icon twice is unchanged; missing asset is an error', () async {
    const request = NativeIconRequest(key: 'dark', assetKey: 'a.png');
    await platform.setIcon(request);
    expect((await platform.setIcon(request)).status, 'unchanged');
    await expectLater(
      platform.setIcon(const NativeIconRequest(key: 'blue')),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', NativeErrorCodes.invalidArgument)),
    );
  });

  test('sets and restores document.title', () async {
    expect((await platform.setDisplayName('Renamed')).status, 'applied');
    expect(web.document.title, 'Renamed');
    expect((await platform.getNativeState()).displayName, 'Renamed');
    expect((await platform.setDisplayName('Renamed')).status, 'unchanged');
    await platform.setDisplayName(null);
    expect(web.document.title, 'Original');
  });

  test('persists the selection in localStorage', () async {
    expect(await platform.loadSelection(), isEmpty);
    await platform.saveSelection({'icon': 'dark', 'name': 'N'});
    expect(await IconShiftWeb().loadSelection(), {'icon': 'dark', 'name': 'N'});
    await platform.saveSelection({});
    expect(web.window.localStorage.getItem(IconShiftWeb.storageKey), isNull);

    web.window.localStorage.setItem(IconShiftWeb.storageKey, 'not json');
    expect(await platform.loadSelection(), isEmpty);
  });

  test('inspect reports display mode and favicon count', () async {
    addFavicon('/favicon.png');
    final inspection = await platform.inspect(const []);
    expect(inspection.info['faviconLinks'], 1);
    expect(inspection.info['displayModeStandalone'], isFalse);
  });

  test('end to end through the engine', () async {
    final engine = IconShiftEngine(
      platform: platform,
      targetPlatform: IconShiftPlatform.web,
    );
    await engine.initialize(
      const IconShiftConfig(
        defaultIdentity: AppIdentity(name: 'App'),
        variants: {
          'dark': AppIdentity(
            name: 'Dark',
            icon: AppIcon.asset('assets/dark.png'),
          ),
        },
      ),
      restoreSelection: false,
    );
    final result = await engine.setIdentity('dark');
    expect(result.isComplete, isTrue, reason: '$result');
    expect(web.document.title, 'Dark');
    expect(iconLinks().single.href, contains('assets/dark.png'));
    expect((await engine.restoreDefault()).isComplete, isTrue);
    expect(web.document.title, 'Original');
  });
}
