import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:icon_shift_cli/icon_shift_cli.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory project;

String path(String relative) => p.join(project.path, relative);
String read(String relative) => File(path(relative)).readAsStringSync();

Uint8List png([int size = 1024]) => img.encodePng(
  img.Image(width: size, height: size)..clear(img.ColorRgb8(10, 120, 200)),
);

void writeIcon(String relative) => File(path(relative))
  ..parent.createSync(recursive: true)
  ..writeAsBytesSync(png());

GeneratorConfig config(String yaml) {
  File(path('icon_shift.yaml')).writeAsStringSync(yaml);
  return loadConfig(project.path);
}

void main() {
  setUp(() {
    project = Directory.systemTemp.createTempSync('icon_shift_remote_');
    File(path('pubspec.yaml')).writeAsStringSync('''
name: demo
flutter:
  assets:
    - assets/
    - assets/icon_shift/remote/
''');
    Directory(
      path('ios/Runner/Assets.xcassets/AppIcon.appiconset'),
    ).createSync(recursive: true);
    File(path('ios/Flutter/Debug.xcconfig'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES\n',
      );
    writeIcon('assets/default.png');
    writeIcon('assets/night.png');
    writeIcon('assets/night_dark.png');
    writeIcon('assets/night_tinted.png');
    writeIcon('assets/night_clear.png');
  });
  tearDown(() => project.deleteSync(recursive: true));

  group('appearances', () {
    const yaml = '''
default:
  name: Demo
  icon: assets/default.png
variants:
  night:
    icon: assets/night.png
    appearances:
      dark: assets/night_dark.png
      tinted: assets/night_tinted.png
      clear: assets/night_clear.png
android:
  enabled: false
dart:
  output: lib/icon_shift_config.g.dart
''';

    test('iOS icon sets get dark and tinted; clear is reported', () {
      final result = plan(project.path, config(yaml));
      expect(result.hasErrors, isFalse, reason: '${result.messages}');
      expect(
        result.messages.map((m) => m.text),
        contains(contains('no slot for clear artwork (night)')),
      );
      result.apply(label: 'test');

      final contents =
          jsonDecode(
                read(
                  'ios/Runner/Assets.xcassets/night.appiconset/Contents.json',
                ),
              )
              as Map;
      final appearances = [
        for (final image in contents['images'] as List)
          ((image as Map)['appearances'] as List?)?.single['value'],
      ];
      expect(appearances, [null, 'dark', 'tinted']);
    });

    test('the Dart config carries every appearance', () {
      final result = plan(project.path, config(yaml));
      result.apply(label: 'test');
      final dart = read('lib/icon_shift_config.g.dart');
      expect(
        dart,
        contains(
          "appearances: IconAppearances(dark: AppIcon.asset('assets/night_dark.png'), "
          "tinted: AppIcon.asset('assets/night_tinted.png'), "
          "clear: AppIcon.asset('assets/night_clear.png'))",
        ),
      );
    });

    test('appearances follow the icon they belong to', () {
      final c = GeneratorConfig.parse('''
default:
  icon: assets/default.png
  appearances: { dark: assets/default_dark.png }
variants:
  plain: { name: Plain }
  own: { icon: assets/own.png }
  ios_only:
    icon: assets/x.png
    appearances: { dark: assets/x_dark.png }
    platforms:
      ios: { icon: assets/x_ios.png, tinted: assets/x_ios_tinted.png }
''');
      expect(
        c.resolve('plain', 'macos').appearances.dark,
        'assets/default_dark.png',
      );
      expect(c.resolve('own', 'macos').appearances.dark, isNull);
      final ios = c.resolve('ios_only', 'ios').appearances;
      expect(ios.dark, isNull, reason: 'the iOS icon replaced the artwork');
      expect(ios.tinted, 'assets/x_ios_tinted.png');
      expect(
        c.resolve('ios_only', 'web').appearances.dark,
        'assets/x_dark.png',
      );
    });

    test('Android overrides reject dark artwork', () {
      expect(
        () => GeneratorConfig.parse('''
default:
  icon: a.png
  platforms:
    android: { dark: b.png }
'''),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('remote', () {
    final requests = <Uri>[];
    Future<Uint8List> fakeFetch(Uri url, {required int maxBytes}) async {
      requests.add(url);
      return switch (url.toString()) {
        'https://cdn.example.com/icons/manifest.json' => utf8.encode(
          jsonEncode({
            'variants': {
              'halloween': {
                'name': 'Spooky',
                'icon': 'halloween.png',
                'appearances': {
                  'dark': 'halloween_dark.png',
                  'tinted': 'https://other.example.com/tinted.png',
                },
              },
              'night': {'icon': 'ignored.png'},
            },
          }),
        ),
        'https://cdn.example.com/icons/bad.png' => utf8.encode('<svg/>'),
        _ when url.path.endsWith('.png') => png(),
        _ => throw HttpException('404', uri: url),
      };
    }

    setUp(requests.clear);

    const yaml = '''
default:
  name: Demo
  icon: https://cdn.example.com/icons/default.png
variants:
  night:
    icon: assets/night.png
remote:
  manifest: https://cdn.example.com/icons/manifest.json
android:
  enabled: false
dart:
  output: lib/icon_shift_config.g.dart
''';

    test('merges manifest variants and downloads every image', () async {
      final resolution = await resolveRemote(
        project.path,
        config(yaml),
        fetch: fakeFetch,
      );
      final c = resolution.config;
      expect(c.variants.keys, ['night', 'halloween']);
      expect(c.variants['night']!.icon, 'assets/night.png');
      expect(
        resolution.messages,
        contains(contains('"night" is also defined in icon_shift.yaml')),
      );

      final halloween = c.resolve('halloween', 'ios');
      for (final local in [
        c.defaultIdentity.icon!,
        halloween.icon!,
        halloween.appearances.dark!,
        halloween.appearances.tinted!,
      ]) {
        expect(local, startsWith('assets/icon_shift/remote/r_'));
        expect(File(path(local)).existsSync(), isTrue, reason: local);
      }
      expect(requests, hasLength(5));

      final result = plan(project.path, c);
      expect(result.hasErrors, isFalse, reason: '${result.messages}');
      result.apply(label: 'test');
      expect(
        read('ios/Runner/Assets.xcassets/halloween.appiconset/Contents.json'),
        contains('"tinted"'),
      );
      expect(
        read('lib/icon_shift_config.g.dart'),
        contains("'halloween': AppIdentity("),
      );

      // Second run: everything comes from remote.assets_dir.
      requests.clear();
      await resolveRemote(project.path, config(yaml), fetch: fakeFetch);
      expect(requests, [
        Uri.parse('https://cdn.example.com/icons/manifest.json'),
      ]);
      await resolveRemote(
        project.path,
        config(yaml),
        fetch: fakeFetch,
        refresh: true,
      );
      expect(requests, hasLength(6));
    });

    test('rejects non-images, failed downloads and plain http', () async {
      Future<void> expectFails(String yaml, String message) => expectLater(
        resolveRemote(project.path, config(yaml), fetch: fakeFetch),
        throwsA(
          isA<RemoteException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
      await expectFails(
        'default: { icon: "https://cdn.example.com/icons/bad.png" }',
        'not a PNG or JPEG',
      );
      await expectFails(
        'default: { icon: "https://cdn.example.com/icons/missing.svg" }',
        'Could not download',
      );
      expect(
        () => config('default: { icon: "http://cdn.example.com/a.png" }'),
        throwsA(isA<ConfigException>()),
      );
    });
  });
}
