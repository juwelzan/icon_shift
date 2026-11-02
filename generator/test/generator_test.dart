import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:icon_shift_generator/icon_shift_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="demo" android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" android:exported="true">
        </activity>
        <!-- icon_shift:aliases:start -->
        <!-- icon_shift:aliases:end -->
    </application>
</manifest>
''';

const _yaml = '''
default:
  name: Demo
  icon: assets/default.png
  platforms:
    android:
      icon: assets/android.png
variants:
  dark:
    name: "Demo's Dark"
    icon: assets/dark.png
  pro:
    name: Demo Pro
dart:
  output: lib/icon_shift_config.g.dart
''';

late Directory project;

String path(String relative) => p.join(project.path, relative);
bool exists(String relative) =>
    FileSystemEntity.typeSync(path(relative)) != FileSystemEntityType.notFound;
String read(String relative) => File(path(relative)).readAsStringSync();

void writeIcon(
  String relative, {
  int size = 1024,
  int height = 0,
  bool alpha = false,
}) {
  final image =
      img.Image(
        width: size,
        height: height == 0 ? size : height,
        numChannels: 4,
      )..clear(
        alpha ? img.ColorRgba8(0, 0, 255, 0) : img.ColorRgba8(200, 30, 30, 255),
      );
  File(path(relative))
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

Plan run([String yaml = _yaml]) {
  File(path('icon_shift.yaml')).writeAsStringSync(yaml);
  return plan(project.path, loadConfig(project.path));
}

void main() {
  setUp(() {
    project = Directory.systemTemp.createTempSync('icon_shift_gen_');
    File(path('pubspec.yaml')).writeAsStringSync('''
name: demo
flutter:
  assets:
    - assets/
''');
    File(path('android/app/src/main/AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_manifest);
    Directory(
      path('android/app/src/main/res/mipmap-mdpi'),
    ).createSync(recursive: true);
    File(
      path('android/app/src/main/res/mipmap-mdpi/ic_launcher.png'),
    ).writeAsStringSync('app');
    Directory(
      path('ios/Runner/Assets.xcassets/AppIcon.appiconset'),
    ).createSync(recursive: true);
    File(path('ios/Flutter/Debug.xcconfig'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        'ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES\n',
      );
    writeIcon('assets/default.png');
    writeIcon('assets/android.png', size: 512);
    writeIcon('assets/dark.png', alpha: true);
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('generates Android, iOS and Dart output', () {
    final result = run();
    expect(result.hasErrors, isFalse, reason: '${result.messages}');
    result.apply();

    const res = 'android/app/src/main/res';
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(exists('$res/mipmap-$d/ic_icon_shift_default.png'), isTrue);
      expect(exists('$res/mipmap-$d/ic_icon_shift_dark.png'), isTrue);
      expect(
        exists('$res/mipmap-$d/ic_icon_shift_pro.png'),
        isFalse,
        reason: 'name-only variant reuses the default icon',
      );
    }
    final xxxhdpi = img.decodePng(
      File(
        path('$res/mipmap-xxxhdpi/ic_icon_shift_dark.png'),
      ).readAsBytesSync(),
    )!;
    expect(xxxhdpi.width, 192);
    expect(
      read('$res/mipmap-mdpi/ic_launcher.png'),
      'app',
      reason: 'untouched',
    );

    final values = read('$res/values/icon_shift.xml');
    expect(
      values,
      contains(
        r'''<string name="icon_shift_label_dark">Demo\'s Dark</string>''',
      ),
    );
    expect(
      values,
      contains('<string name="icon_shift_label_pro">Demo Pro</string>'),
    );

    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:name=".IconShiftAlias_default"'));
    expect(manifest, contains('android:enabled="true"'));
    expect(
      RegExp('android:enabled="false"').allMatches(manifest),
      hasLength(2),
    );
    expect(
      manifest,
      contains(
        '<meta-data android:name="icon_shift.variant" android:value="pro" />',
      ),
    );
    expect(
      manifest,
      contains(
        'android:icon="@mipmap/ic_icon_shift_default"\n            android:label="@string/icon_shift_label_pro"',
      ),
    );
    expect(
      manifest,
      contains('<activity android:name=".MainActivity"'),
      reason: 'activity kept',
    );

    const set = 'ios/Runner/Assets.xcassets/dark.appiconset';
    expect(
      jsonDecode(read('$set/Contents.json'))['info']['author'],
      'icon_shift_generator',
    );
    final ios = img.decodePng(
      File(path('$set/icon_1024.png')).readAsBytesSync(),
    )!;
    expect(ios.width, 1024);
    expect(ios.numChannels, 3, reason: 'alpha flattened for the App Store');
    expect(exists('ios/Runner/Assets.xcassets/pro.appiconset'), isFalse);
    expect(result.messages.map((m) => m.text).join(), contains('flattened'));

    final dart = read('lib/icon_shift_config.g.dart');
    expect(dart, startsWith('// GENERATED by icon_shift_generator'));
    expect(dart, contains(r"name: 'Demo\'s Dark'"));
    expect(
      dart,
      contains(
        "IconShiftPlatform.android: IdentityOverride(icon: AppIcon.asset('assets/android.png'))",
      ),
    );
  });

  test('second run changes nothing', () {
    run().apply();
    final again = run();
    expect(again.writes, isEmpty);
    expect(again.deletes, isEmpty);
  });

  test('removed variants are cleaned up, foreign files kept', () {
    run().apply();
    final result = run(_yaml.replaceAll(RegExp(r'  dark:\n(    .*\n)+'), ''));
    expect(result.hasErrors, isFalse, reason: '${result.messages}');
    expect(
      result.deletes,
      containsAll([
        'android/app/src/main/res/mipmap-mdpi/ic_icon_shift_dark.png',
        'ios/Runner/Assets.xcassets/dark.appiconset',
      ]),
    );
    expect(result.deletes.any((d) => d.contains('ic_launcher')), isFalse);
    expect(result.deletes.any((d) => d.contains('AppIcon')), isFalse);
    result.apply();
    expect(exists('ios/Runner/Assets.xcassets/dark.appiconset'), isFalse);
  });

  test('invalid icons are errors and nothing would be written', () {
    writeIcon('assets/dark.png', size: 512); // too small for iOS
    writeIcon('assets/android.png', size: 100); // too small for Android
    final result = run(
      _yaml.replaceFirst('  pro:', '''
  wide:
    icon: assets/wide.png
  vector:
    icon: assets/vector.svg
  missing:
    icon: assets/nope.png
  pro:'''),
    );
    writeIcon('assets/wide.png', size: 300, height: 200);
    final rerun = run(File(path('icon_shift.yaml')).readAsStringSync());
    final errors = rerun.messages
        .where((m) => m.level == Level.error)
        .map((m) => m.text)
        .join('\n');
    expect(rerun.hasErrors, isTrue);
    expect(errors, contains('must be square'));
    expect(errors, contains('is SVG'));
    expect(errors, contains('does not exist'));
    expect(errors, contains('Refusing to upscale'));
    expect(errors, contains('iOS needs 1024'));
    expect(result.hasErrors, isTrue);
  });

  test('refuses to overwrite files it does not own', () {
    File(path('ios/Runner/Assets.xcassets/dark.appiconset/Contents.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"info": {"author": "xcode"}}');
    File(path('android/app/src/main/res/values/icon_shift.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<resources/>');
    final result = run();
    final errors = result.messages
        .where((m) => m.level == Level.error)
        .map((m) => m.text)
        .join('\n');
    expect(errors, contains('dark.appiconset" exists and was not created'));
    expect(errors, contains('icon_shift.xml" exists and was not created'));
  });

  test(
    'without markers the manifest is untouched and a snippet is written',
    () {
      File(path('android/app/src/main/AndroidManifest.xml')).writeAsStringSync(
        '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''',
      );
      final result = run();
      expect(
        result.writes.keys,
        isNot(contains('android/app/src/main/AndroidManifest.xml')),
      );
      expect(
        result.writes.keys,
        contains('build/icon_shift/AndroidManifest.snippet.xml'),
      );
      final warnings = result.messages
          .where((m) => m.level == Level.warning)
          .map((m) => m.text)
          .join('\n');
      expect(warnings, contains('no IconShift markers'));
      expect(warnings, contains('launcher shows a second entry'));
    },
  );

  test('launcher filter classification', () {
    // The base manifest has no LAUNCHER filter: flutter run would fail.
    var warnings = run().messages.map((m) => m.text).join();
    expect(warnings, contains('has no MAIN/LAUNCHER intent-filter'));

    final manifest = path('android/app/src/main/AndroidManifest.xml');
    File(manifest).writeAsStringSync(
      read('android/app/src/main/AndroidManifest.xml').replaceFirst(
        '        </activity>',
        '''            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
                <data android:scheme="icon-shift-tooling"/>
            </intent-filter>
        </activity>''',
      ),
    );
    warnings = run().messages
        .where((m) => m.level == Level.warning)
        .map((m) => m.text)
        .join();
    expect(warnings, isNot(contains('LAUNCHER')));
  });

  test('warns when the iOS build setting is missing', () {
    File(path('ios/Flutter/Debug.xcconfig')).writeAsStringSync('');
    final warnings = run().messages
        .where((m) => m.level == Level.warning)
        .map((m) => m.text);
    expect(
      warnings.join(),
      contains('ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS'),
    );
  });

  test('adaptive icons when a background color is set', () {
    final result = run('$_yaml\nandroid:\n  adaptive_background: "#102030"\n');
    result.apply();
    const res = 'android/app/src/main/res';
    expect(
      read('$res/mipmap-anydpi-v26/ic_icon_shift_dark.xml'),
      contains('@mipmap/ic_icon_shift_dark_foreground'),
    );
    final fg = img.decodePng(
      File(
        path('$res/mipmap-xxxhdpi/ic_icon_shift_dark_foreground.png'),
      ).readAsBytesSync(),
    )!;
    expect(fg.width, 432);
    expect(read('$res/values/icon_shift.xml'), contains('#102030'));
  });

  group('config parsing', () {
    test('reads the pubspec section when there is no icon_shift.yaml', () {
      File(
        path('pubspec.yaml'),
      ).writeAsStringSync('name: x\nicon_shift:\n  default:\n    name: X\n');
      expect(loadConfig(project.path).defaultIdentity.name, 'X');
    });

    test('rejects bad input with clear messages', () {
      Matcher fails(String text) => throwsA(
        isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains(text),
        ),
      );
      expect(
        () => GeneratorConfig.parse('variants: {}'),
        fails('Missing "default:"'),
      );
      expect(
        () => GeneratorConfig.parse('default: {name: A}\nvariants: {Bad: {}}'),
        fails('must match'),
      );
      expect(
        () => GeneratorConfig.parse(
          'default: {name: A}\nvariants: {default: {}}',
        ),
        fails('reserved'),
      );
      expect(
        () => GeneratorConfig.parse(
          'default: {name: A, platforms: {tv: {name: B}}}',
        ),
        fails('Unknown platform'),
      );
      expect(
        () => GeneratorConfig.parse('default: {nmae: A}'),
        fails('Unknown key "default.nmae"'),
      );
      expect(
        () => GeneratorConfig.parse(
          'default: {name: A}\nios: {background_color: red}',
        ),
        fails('color'),
      );
    });

    test('resolution matches the plugin rules', () {
      final config = GeneratorConfig.parse(_yaml);
      expect(config.resolve('default', 'android').icon, 'assets/android.png');
      expect(config.resolve('default', 'ios').icon, 'assets/default.png');
      final pro = config.resolve('pro', 'android');
      expect(pro.icon, 'assets/android.png');
      expect(pro.usesDefaultIcon, isTrue);
      expect(config.resolve('dark', 'web').name, "Demo's Dark");
    });
  });
}
