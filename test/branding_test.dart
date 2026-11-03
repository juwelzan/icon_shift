import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icon_shift/icon_shift.dart';
import 'package:icon_shift/src/engine.dart';

import 'fakes.dart';

/// A real response from a tenant server (DigiEdu/Schoolmate), verbatim.
const digiEduResponse = '''
{"data":{"app_name":"Amena Baki Residential Model School and College",
"logo_url":null,"favicon_url":null,"primary_color":"#1e40af",
"secondary_color":"#3b82f6","app_code":"588846"},
"message":"Branding retrieved successfully."}
''';

String responseFor(
  String name, {
  String? logo,
  String? favicon,
  String primary = '#1e40af',
  String code = '000',
}) => jsonEncode({
  'data': {
    'app_name': name,
    'logo_url': logo,
    'favicon_url': favicon,
    'primary_color': primary,
    'secondary_color': '#3b82f6',
    'app_code': code,
  },
  'message': 'Branding retrieved successfully.',
});

/// A provider for one tenant, backed by [body].
BrandingProvider providerFor(
  String host, {
  String? body,
  List<String>? seen,
  Object? error,
}) => CallbackBrandingProvider(
  tenantId: '$host.digiedu.online',
  fetch: () async {
    seen?.add(host);
    if (error != null) throw error;
    return BrandingProfile.decode(
      body ?? responseFor('School $host.digiedu.online', code: host),
      tenantId: '$host.digiedu.online',
    );
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrandingProfile', () {
    test('parses the real DigiEdu response', () {
      final profile = BrandingProfile.decode(
        digiEduResponse,
        tenantId: 'amena-baki.digiedu.online',
      );
      expect(
        profile.appName,
        'Amena Baki Residential Model School and College',
      );
      expect(profile.displayName, profile.appName);
      expect(profile.primaryColor, 0xFF1E40AF);
      expect(profile.secondaryColor, 0xFF3B82F6);
      expect(profile.appCode, '588846');
      expect(profile.logoUrl, isNull, reason: 'null in the response');
      expect(profile.launcherIconUrl, isNull);
      // The endpoint sends no version and no ETag, so one is derived.
      expect(profile.version, startsWith('c_'));
    });

    test('the derived version follows the content, not the request', () {
      final a = BrandingProfile.decode(digiEduResponse, tenantId: 't');
      final b = BrandingProfile.decode(digiEduResponse, tenantId: 't');
      expect(a.version, b.version);
      final changed = BrandingProfile.decode(
        responseFor('Other School'),
        tenantId: 't',
      );
      expect(changed.version, isNot(a.version));
    });

    test('accepts the illustrative schema and a flat body', () {
      final profile = BrandingProfile.parse({
        'institution_id': 'school_123',
        'branding_version': 'v12',
        'app_name': 'ABC School',
        'institution_name': 'ABC School Trust',
        'logo_url': 'https://example.com/abc/logo.png',
        'launcher_icon_url': 'https://example.com/abc/app-icon.png',
        'primary_color': '#2563EB',
        'secondary_color': '#4F46E5',
      }, tenantId: 'school_123');
      expect(profile.version, 'v12', reason: 'the server version wins');
      expect(profile.appCode, 'school_123');
      expect(profile.institutionName, 'ABC School Trust');
      expect(
        profile.launcherIconUrl,
        Uri.parse('https://example.com/abc/app-icon.png'),
      );
    });

    test('a favicon stands in for a missing launcher icon', () {
      final profile = BrandingProfile.parse({
        'app_name': 'X',
        'favicon_url': 'https://example.com/fav.png',
      }, tenantId: 't');
      expect(profile.launcherIconUrl, Uri.parse('https://example.com/fav.png'));
    });

    test('hostile or malformed fields are dropped, the rest survives', () {
      final profile = BrandingProfile.parse({
        'app_name': 'Good Name',
        'logo_url': 'http://insecure.example.com/logo.png',
        'launcher_icon_url': 'javascript:alert(1)',
        'primary_color': 'red',
        'secondary_color': '#3b82f6',
        'extra_flag': true,
      }, tenantId: 't');
      expect(profile.appName, 'Good Name');
      expect(profile.logoUrl, isNull, reason: 'plain http is refused');
      expect(profile.launcherIconUrl, isNull);
      expect(profile.primaryColor, isNull);
      expect(profile.secondaryColor, 0xFF3B82F6);
      expect(profile.extras['extra_flag'], isTrue);
    });

    test('strict parsing reports the bad field instead', () {
      expect(
        () => BrandingProfile.parse(
          {'app_name': 'X', 'logo_url': 'http://insecure.example.com/a.png'},
          tenantId: 't',
          strict: true,
        ),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(
        () => BrandingProfile.parse('nope', tenantId: 't'),
        throwsA(isA<InvalidArgumentException>()),
      );
      expect(
        () => BrandingProfile.decode('{oops', tenantId: 't'),
        throwsA(isA<InvalidArgumentException>()),
      );
    });

    test('a name with control characters is refused', () {
      final profile = BrandingProfile.parse({
        'app_name': 'Bad\u0000Name',
        'institution_name': 'ঢাকা আদর্শ বিদ্যালয়',
      }, tenantId: 't');
      expect(profile.appName, isNull);
      expect(profile.displayName, 'ঢাকা আদর্শ বিদ্যালয়');
    });

    test('colours round-trip through the cache form', () {
      final profile = BrandingProfile.parse({
        'app_name': 'X',
        'primary_color': '#abc',
      }, tenantId: 't');
      expect(profile.primaryColor, 0xFFAABBCC);
      expect(hexColor(profile.primaryColor!), '#AABBCC');
      final cached = BrandingProfile.decode(
        jsonEncode(profile.toJson()),
        tenantId: 't',
      );
      expect(cached, profile);
    });

    test('parseHexColor rejects what is not a colour', () {
      expect(parseHexColor('#1e40af'), 0xFF1E40AF);
      expect(parseHexColor('#801e40af'), 0x801E40AF);
      expect(parseHexColor('1e40af'), isNull);
      expect(parseHexColor('#12345'), isNull);
      expect(parseHexColor(''), isNull);
    });
  });

  group('BrandingController', () {
    late FakePlatform platform;
    late IconShiftEngine engine;
    final requests = <Uri>[];

    Future<BrandingController> controller({
      BrandingProfile? defaultBranding,
      Map<String, String>? selection,
    }) async {
      platform = FakePlatform(desktopLike, selection: selection);
      engine = IconShiftEngine(
        platform: platform,
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle(demoAssets),
      );
      await engine.initialize(demoConfig);
      return BrandingController(
        engine: engine,
        defaultBranding: defaultBranding,
      );
    }

    setUp(requests.clear);

    test('loads, caches and reports live branding', () async {
      final c = await controller();
      expect(c.value.status, BrandingStatus.idle);
      expect(c.profile.isEmpty, isTrue);

      final state = await c.load(providerFor('abc'));
      expect(state.status, BrandingStatus.live);
      expect(state.profile.appName, 'School abc.digiedu.online');
      // Cached under the tenant, so the next launch starts branded.
      expect(platform.savedSelection['branding_tenant'], 'abc.digiedu.online');
      expect(platform.savedSelection['branding'], contains('School abc'));
    });

    test('a cached school shows before the network answers', () async {
      var c = await controller();
      await c.load(providerFor('abc'));
      final saved = platform.savedSelection;

      final seen = <BrandingStatus>[];
      c = await controller(selection: saved);
      c.addListener(() => seen.add(c.value.status));
      final state = await c.load(
        CallbackBrandingProvider(
          tenantId: 'abc.digiedu.online',
          fetch: () async {
            // The cached branding must already be on screen by now.
            expect(seen, contains(BrandingStatus.cached));
            return BrandingProfile.decode(
              responseFor('School abc renamed'),
              tenantId: 'abc.digiedu.online',
            );
          },
        ),
      );
      expect(seen.first, BrandingStatus.cached);
      expect(state.status, BrandingStatus.live);
      expect(state.profile.appName, 'School abc renamed');
    });

    test('offline keeps the cached branding and never throws', () async {
      var c = await controller();
      await c.load(providerFor('abc'));
      final saved = platform.savedSelection;

      c = await controller(selection: saved);
      final state = await c.load(
        providerFor('abc', error: Exception('SocketException')),
      );
      expect(state.status, BrandingStatus.offline);
      expect(state.profile.appName, 'School abc.digiedu.online');
      expect(state.error, contains('SocketException'));
    });

    test('offline with no cache falls back to the app branding', () async {
      final c = await controller(
        defaultBranding: const BrandingProfile(
          tenantId: 'default',
          appName: 'My App',
        ),
      );
      final state = await c.load(
        providerFor('abc', error: Exception('no network')),
      );
      expect(state.status, BrandingStatus.offline);
      expect(state.profile.appName, 'My App');
    });

    test('a malformed answer keeps the previous branding', () async {
      final c = await controller();
      final state = await c.load(
        CallbackBrandingProvider(
          tenantId: 'abc.digiedu.online',
          fetch: () async => BrandingProfile.decode(
            '<html>503</html>',
            tenantId: 'abc.digiedu.online',
          ),
        ),
      );
      expect(state.status, BrandingStatus.invalid);
      expect(state.profile.isEmpty, isTrue);
      expect(platform.savedSelection.containsKey('branding'), isFalse);
    });

    test('switching schools never shows the previous one', () async {
      final seen = <String?>[];
      final c = await controller();
      c.addListener(() => seen.add(c.value.profile.appName));

      await c.load(providerFor('abc'));
      await c.load(providerFor('xyz'));

      expect(c.profile.appName, 'School xyz.digiedu.online');
      expect(platform.savedSelection['branding_tenant'], 'xyz.digiedu.online');
      expect(
        platform.savedSelection['branding'],
        isNot(contains('abc')),
        reason: 'the previous school must be gone from the cache',
      );
      // Between the two schools the app falls back, never to abc's name.
      final afterSwitch = seen.sublist(
        seen.indexOf('School abc.digiedu.online') + 1,
      );
      expect(afterSwitch, isNot(contains('School abc.digiedu.online')));
    });

    test('another school cannot read a cached profile', () async {
      final c = await controller();
      await c.load(providerFor('abc'));
      expect(engine.readBranding('abc.digiedu.online'), isNotNull);
      expect(
        engine.readBranding('xyz.digiedu.online'),
        isNull,
        reason: 'the cache is keyed by tenant',
      );
    });

    test('clear() forgets the school and its cache', () async {
      final c = await controller();
      await c.load(providerFor('abc'));
      await c.clear();
      expect(c.provider, isNull);
      expect(c.tenantId, isNull);
      expect(c.value.status, BrandingStatus.idle);
      expect(platform.savedSelection.containsKey('branding'), isFalse);
      expect(platform.savedSelection.containsKey('branding_tenant'), isFalse);
    });

    test('unchanged branding does not rewrite the cache', () async {
      final fetches = <String>[];
      final c = await controller();
      final provider = providerFor(
        'abc',
        body: responseFor('Same School'),
        seen: fetches,
      );
      await c.load(provider);
      final afterFirst = platform.savedSelection['branding'];
      await c.refresh();
      expect(fetches, hasLength(2), reason: 'refresh really asks again');
      expect(platform.savedSelection['branding'], afterFirst);
      expect(c.value.status, BrandingStatus.live);
    });

    test('concurrent loads make one request', () async {
      final c = await controller();
      final fetches = <String>[];
      final provider = providerFor('abc', seen: fetches);
      await Future.wait([c.load(provider), c.load(provider), c.load(provider)]);
      expect(fetches, hasLength(1));
    });

    test('a saved cache from another school is ignored', () async {
      final c = await controller(
        selection: {
          'branding_tenant': 'other.digiedu.online',
          'branding': responseFor('Other School'),
        },
      );
      final state = await c.load(
        providerFor('abc', error: Exception('offline')),
      );
      expect(state.profile.appName, isNot('Other School'));
      expect(state.profile.isEmpty, isTrue);
    });
  });

  group('providers', () {
    test('HttpBrandingProvider reads a JSON endpoint', () async {
      final seen = <Uri>[];
      final sentHeaders = <Map<String, String>>[];
      final provider = HttpBrandingProvider(
        url: Uri.parse('https://api.example.com/branding?tenant=school_123'),
        tenantId: 'school_123',
        headers: const {'Accept': 'application/json', 'X-Key': 'secret'},
        download: (url, {required maxBytes, headers = const {}}) async {
          seen.add(url);
          sentHeaders.add(headers);
          return Uint8List.fromList(utf8.encode(responseFor('ABC School')));
        },
      );
      final profile = await provider.fetch();
      expect(provider.tenantId, 'school_123');
      expect(seen.single.host, 'api.example.com');
      expect(sentHeaders.single['X-Key'], 'secret', reason: 'auth headers');
      expect(profile.appName, 'ABC School');
    });

    test('host() builds one endpoint per tenant and refuses plain http', () {
      final provider = HttpBrandingProvider.host(
        Uri.parse('https://abc.example.com'),
        path: '/api/v1/branding',
      );
      expect(provider.tenantId, 'abc.example.com');
      expect(
        provider.url,
        Uri.parse('https://abc.example.com/api/v1/branding'),
      );
      expect(
        () => HttpBrandingProvider.host(
          Uri.parse('http://abc.example.com'),
          path: '/b',
        ),
        throwsA(isA<InvalidArgumentException>()),
        reason: 'plain http would expose the tenant host',
      );
    });

    test('a field map adapts any response shape', () async {
      const fields = BrandingFieldMap(
        envelope: 'result',
        appName: ['title'],
        launcherIconUrl: ['icon'],
        primaryColor: ['brand_colour'],
        code: ['org'],
      );
      final profile = BrandingProfile.parse(
        {
          'result': {
            'title': 'Northside College',
            'icon': 'https://cdn.example.com/n.png',
            'brand_colour': '#0F766E',
            'org': 'north_1',
          },
        },
        tenantId: 'north',
        fields: fields,
      );
      expect(profile.appName, 'Northside College');
      expect(
        profile.launcherIconUrl,
        Uri.parse('https://cdn.example.com/n.png'),
      );
      expect(profile.primaryColor, 0xFF0F766E);
      expect(profile.appCode, 'north_1');
    });

    test('a response without an envelope is read directly', () {
      const fields = BrandingFieldMap(envelope: null);
      final profile = BrandingProfile.parse(
        {
          'app_name': 'Flat School',
          'data': {'app_name': 'Should be ignored'},
        },
        tenantId: 't',
        fields: fields,
      );
      expect(profile.appName, 'Flat School');
      expect(profile.extras['data'], isA<Map>());
    });

    test('StaticBrandingProvider serves app-local branding', () async {
      const profile = BrandingProfile(tenantId: 'local', appName: 'My App');
      const provider = StaticBrandingProvider(profile);
      expect(provider.tenantId, 'local');
      expect(await provider.fetch(), profile);
    });
  });

  group('applyBranding', () {
    test('shows and caches a profile the app already has', () async {
      final platform = FakePlatform(desktopLike);
      final engine = IconShiftEngine(
        platform: platform,
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle(demoAssets),
      );
      await engine.initialize(demoConfig);
      final c = BrandingController(engine: engine);

      final state = await c.apply(
        const BrandingProfile(tenantId: 'pushed', appName: 'Pushed School'),
      );
      expect(state.status, BrandingStatus.live);
      expect(c.tenantId, 'pushed');
      expect(platform.savedSelection['branding_tenant'], 'pushed');

      // Another tenant replaces it rather than sitting beside it.
      await c.apply(
        const BrandingProfile(tenantId: 'other', appName: 'Other School'),
      );
      expect(engine.readBranding('pushed'), isNull);
      expect(engine.readBranding('other'), isNotNull);
    });
  });

  group('launcher branding', () {
    test('desktop applies the name and the downloaded icon', () async {
      final platform = FakePlatform(desktopLike);
      final engine = IconShiftEngine(
        platform: platform,
        targetPlatform: IconShiftPlatform.macos,
        assetBundle: FakeAssetBundle(demoAssets),
        fetch: (url, {required maxBytes, headers = const {}}) async =>
            Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      );
      await engine.initialize(demoConfig);
      final c = BrandingController(engine: engine);
      await c.load(
        providerFor(
          'abc',
          body: responseFor(
            'ABC School',
            favicon: 'https://cdn.example.com/abc.png',
          ),
        ),
      );

      final report = await c.applyLauncherBranding();
      expect(report.scope, NativeBrandingScope.applied);
      expect(report.isApplied, isTrue);
      expect(report.needsBuild, isFalse);
      expect(platform.displayName, 'ABC School');
      expect(platform.iconRequests.last.key, startsWith('remote:'));
    });

    test('iOS reports the name as build-time, not silently dropped', () async {
      final platform = FakePlatform(iosLike);
      final engine = IconShiftEngine(
        platform: platform,
        targetPlatform: IconShiftPlatform.ios,
        assetBundle: FakeAssetBundle(demoAssets),
      );
      await engine.initialize(demoConfig);
      final c = BrandingController(engine: engine);
      await c.load(providerFor('abc', body: responseFor('ABC School')));

      final report = await c.applyLauncherBranding(fallbackVariant: 'dark');
      expect(platform.iconKey, 'dark', reason: 'a bundled icon still applies');
      expect(
        report.scope,
        NativeBrandingScope.requiresBuild,
        reason: 'iOS cannot show a runtime name: $report',
      );
      expect(report.needsBuild, isTrue);
      expect(report.message, contains('icon_shift_cli'));
      expect(
        report.result.displayName.errorCode,
        IconShiftErrorCode.buildRequired,
      );
    });
  });
}
