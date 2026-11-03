import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:icon_shift_cli/icon_shift_cli.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final fixture = p.join(
  p.dirname(Platform.script.toFilePath()).endsWith('test')
      ? p.dirname(Platform.script.toFilePath())
      : 'test',
  'fixtures',
  'app',
);

late Directory project;
String path(String relative) => p.join(project.path, relative);
String read(String relative) => File(path(relative)).readAsStringSync();
bool exists(String relative) =>
    FileSystemEntity.typeSync(path(relative)) != FileSystemEntityType.notFound;

void copyDir(Directory from, Directory to) {
  for (final entity in from.listSync(recursive: true)) {
    final relative = p.relative(entity.path, from: from.path);
    if (entity is Directory) {
      Directory(p.join(to.path, relative)).createSync(recursive: true);
    } else if (entity is File) {
      final target = File(p.join(to.path, relative))
        ..parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
  }
}

void writeIcon(String relative, {int size = 1024}) {
  final image = img.Image(width: size, height: size, numChannels: 4)
    ..clear(img.ColorRgba8(30, 140, 90, 255));
  File(path(relative))
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

/// The live DigiEdu / Schoolmate bootstrap response, verbatim.
const digiEdu = '''
{"data":{"app_name":"Amena Baki Residential Model School and College",
"logo_url":null,"favicon_url":null,"primary_color":"#1e40af",
"secondary_color":"#3b82f6","app_code":"588846"},
"message":"Branding retrieved successfully."}
''';

/// A school whose server also publishes a logo.
String brandingWith(String name, {String? logo, String primary = '#D97706'}) =>
    jsonEncode({
      'data': {
        'app_name': name,
        'logo_url': logo,
        'favicon_url': null,
        'primary_color': primary,
        'secondary_color': '#F59E0B',
        'app_code': '777001',
      },
      'message': 'Branding retrieved successfully.',
    });

const _shared = '''
default:
  name: Schoolmate
  names: { de: Schoolmate DE }
  icon: assets/icon.png
  platforms:
    android:
      name: Schoolmate Android
      names: { de: Schoolmate Android DE }
variants:
  dark: { name: Schoolmate Dark, icon: assets/icon.png }
application:
  display_name: Schoolmate
''';

void main() {
  setUp(() {
    project = Directory.systemTemp.createTempSync('icon_shift_brand_');
    copyDir(Directory(fixture), project);
    writeIcon('assets/icon.png');
    File(path('icon_shift.yaml')).writeAsStringSync(_shared);
  });
  tearDown(() => project.deleteSync(recursive: true));

  GeneratorConfig config() => loadConfig(project.path);

  /// Serves [body] for the branding document and a PNG for anything else.
  Future<Uint8List> Function(Uri, {required int maxBytes}) server(
    String body, {
    List<Uri>? seen,
  }) => (url, {required maxBytes}) async {
    seen?.add(url);
    if (url.path.endsWith('.png')) {
      return Uint8List.fromList(
        img.encodePng(img.Image(width: 1024, height: 1024)),
      );
    }
    return Uint8List.fromList(utf8.encode(body));
  };

  group('InstitutionBranding', () {
    test('parses the real DigiEdu response', () {
      final b = InstitutionBranding.parse(
        jsonDecode(digiEdu),
        tenantId: 'amena-baki.digiedu.online',
      );
      expect(b.appName, 'Amena Baki Residential Model School and College');
      expect(b.primaryColor, '#1E40AF');
      expect(b.secondaryColor, '#3B82F6');
      expect(b.appCode, '588846');
      expect(b.iconSource, isNull, reason: 'this school sends no logo');
    });

    test('a favicon stands in for a missing launcher icon', () {
      final b = InstitutionBranding.parse({
        'app_name': 'X',
        'favicon_url': 'https://cdn.example.com/fav.png',
      }, tenantId: 't');
      expect(b.iconSource, 'https://cdn.example.com/fav.png');
    });

    test('slugs suit each platform', () {
      InstitutionBranding at(String host) =>
          InstitutionBranding(tenantId: host, appName: 'X');
      expect(at('abc-school.digiedu.online').slug, 'abc_school');
      expect(at('abc-school.digiedu.online').appleSlug, 'abc-school');
      expect(at('123school.example.com').slug, 's_123school');
      expect(at('---.example.com').slug, 'school');
    });

    test('unusable branding is refused, not built in', () {
      void bad(Map<String, Object?> json) => expect(
        () => InstitutionBranding.parse(json, tenantId: 't'),
        throwsA(isA<ConfigException>()),
      );
      bad({'app_name': 'X', 'logo_url': 'http://insecure.example.com/a.png'});
      bad({'app_name': 'X', 'primary_color': 'red'});
      bad({'app_name': 'Bad\u0000Name'});
      bad({'app_name': 'x' * 256});
      expect(
        () => InstitutionBranding.parse('nope', tenantId: 't'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('fetch refuses a non-https school host', () {
      expect(
        () => InstitutionBranding.fetch(Uri.parse('http://abc.example.com')),
        throwsA(isA<ConfigException>()),
      );
    });

    test('fetch reads the school host and reports failures', () async {
      final seen = <Uri>[];
      final b = await InstitutionBranding.fetch(
        Uri.parse('https://abc.digiedu.online'),
        fetch: server(brandingWith('ABC School'), seen: seen),
      );
      expect(
        seen.single,
        Uri.parse('https://abc.digiedu.online/api/v1/branding'),
      );
      expect(b.appName, 'ABC School');
      expect(b.tenantId, 'abc.digiedu.online');

      await expectLater(
        InstitutionBranding.fetch(
          Uri.parse('https://abc.digiedu.online'),
          fetch: (url, {required maxBytes}) async => throw Exception('down'),
        ),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('planBranding', () {
    Future<BrandPlan> brand({
      String branding = '',
      String? applicationId,
      String? bundleId,
      String? slug,
    }) => planBranding(
      projectDir: project.path,
      base: config(),
      branding: InstitutionBranding.parse(
        jsonDecode(branding.isEmpty ? brandingWith('ABC School') : branding),
        tenantId: 'abc.digiedu.online',
      ),
      applicationIdTemplate: applicationId,
      bundleIdTemplate: bundleId,
      slug: slug,
      fetch: server(branding.isEmpty ? brandingWith('ABC School') : branding),
    );

    test('the institution name replaces every shared name', () async {
      final result = await brand();
      expect(result.plan.hasErrors, isFalse, reason: '${result.plan.messages}');
      result.plan.apply(label: 'brand');

      const values = 'android/app/src/main/res/values/icon_shift.xml';
      expect(
        read(values),
        contains('<string name="icon_shift_app_name">ABC School</string>'),
      );
      expect(
        read(values),
        contains('<string name="icon_shift_label_default">ABC School</string>'),
        reason: 'the shared per-platform Android name must not win',
      );
      expect(
        exists('android/app/src/main/res/values-de/icon_shift.xml'),
        isFalse,
        reason: 'the shared German name would show the old app there',
      );
      expect(
        read('android/app/src/main/AndroidManifest.xml'),
        contains('android:label="@string/icon_shift_app_name"'),
      );
      expect(
        read('ios/Runner/Info.plist'),
        contains('<string>ABC School</string>'),
      );
      expect(
        result.messages,
        contains(contains('dropped the shared per-platform names')),
      );
    });

    test('a school logo becomes the launcher icon on both platforms', () async {
      final body = brandingWith(
        'ABC School',
        logo: 'https://cdn.example.com/abc.png',
      );
      final result = await brand(branding: body);
      result.plan.apply(label: 'brand');

      expect(result.messages, contains(contains('primary iOS app icon')));
      // Downloaded once, then used for every generated resource.
      expect(result.config.defaultIdentity.icon, startsWith('assets/'));
      expect(
        exists(
          'android/app/src/main/res/mipmap-xxhdpi/ic_icon_shift_default.png',
        ),
        isTrue,
      );
      expect(
        exists('ios/Runner/Assets.xcassets/AppIcon.appiconset/icon_1024.png'),
        isTrue,
        reason: 'the home-screen icon itself, not just an alternate set',
      );
      // The school colour drives the adaptive icon background.
      expect(
        read('android/app/src/main/res/values/icon_shift.xml'),
        contains('icon_shift_adaptive_background'),
      );
    });

    test('without a school logo the shared icon is kept', () async {
      final result = await brand(branding: digiEdu);
      expect(
        result.messages,
        contains(contains('keeping the shared app icon')),
      );
      expect(result.config.defaultIdentity.icon, 'assets/icon.png');
    });

    test('{slug} expands to what each platform accepts', () async {
      final result = await brand(
        applicationId: 'com.digiedu.{slug}',
        bundleId: 'com.digiedu.{slug}',
        slug: 'abc_school',
      );
      expect(result.slug, 'abc_school');
      expect(result.identity.androidApplicationId, 'com.digiedu.abc_school');
      expect(
        result.identity.iosBundleId,
        'com.digiedu.abc-school',
        reason: 'Apple bundle ids reject "_"',
      );
      expect(result.identity.macosBundleId, 'com.digiedu.abc-school');

      result.plan.apply(label: 'brand');
      expect(
        read('android/app/build.gradle.kts'),
        contains('applicationId = "com.digiedu.abc_school"'),
      );
    });

    test('ids that the platforms would reject fail the build', () async {
      await expectLater(
        brand(applicationId: 'digiedu_{slug}'),
        throwsA(isA<ConfigException>()),
      );
      await expectLater(
        brand(slug: 'ABC School'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('branding without a name cannot brand a build', () async {
      await expectLater(
        planBranding(
          projectDir: project.path,
          base: config(),
          branding: InstitutionBranding(tenantId: 'abc.digiedu.online'),
        ),
        throwsA(isA<ConfigException>()),
      );
    });

    test('the build record names the institution and its files', () async {
      final result = await brand(
        applicationId: 'com.digiedu.{slug}',
        slug: 'abc_school',
      );
      final json = result.toJson();
      expect(json['slug'], 'abc_school');
      expect(json['display_name'], 'ABC School');
      expect(json['application_id'], 'com.digiedu.abc_school');
      expect(
        (json['files']! as List).join(' '),
        contains('AndroidManifest.xml'),
      );
    });
  });

  group('artifact verification', () {
    test('a missing artifact is a problem, not a pass', () {
      final apk = inspectApk(path('nope.apk'), aapt2: '/bin/echo');
      expect(apk.problem, isNotNull);
      expect(apk.matches('ABC School'), isFalse);

      final app = inspectAppBundle(path('nope.app'));
      expect(app.problem, 'Info.plist not found');
      expect(app.matches('ABC School'), isFalse);
    });

    test('matches() checks the name and, when given, the id', () {
      final check = ArtifactCheck(
        artifact: 'a.apk',
        displayName: 'ABC School',
        applicationId: 'com.digiedu.abc_school',
      );
      expect(check.matches('ABC School'), isTrue);
      expect(
        check.matches('ABC School', expectedId: 'com.digiedu.abc_school'),
        isTrue,
      );
      expect(check.matches('Other School'), isFalse);
      expect(check.matches('ABC School', expectedId: 'com.other'), isFalse);
    });

    test('the build record lists the artifacts that were checked', () async {
      final result = await planBranding(
        projectDir: project.path,
        base: config(),
        branding: InstitutionBranding(
          tenantId: 'abc.digiedu.online',
          appName: 'ABC School',
        ),
        fetch: server(brandingWith('ABC School')),
      );
      final record = path('out/build.json');
      writeBuildRecord(record, result, [
        ArtifactCheck(
          artifact: 'app-release.apk',
          displayName: 'ABC School',
          applicationId: 'com.digiedu.abc_school',
        ),
      ]);
      final json = jsonDecode(File(record).readAsStringSync()) as Map;
      expect((json['artifacts']! as List).single, {
        'path': 'app-release.apk',
        'display_name': 'ABC School',
        'application_id': 'com.digiedu.abc_school',
      });
      expect(json['built_at'], isA<String>());
    });
  });
}
