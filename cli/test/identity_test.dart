import 'dart:convert';
import 'dart:io';

import 'package:icon_shift_cli/icon_shift_cli.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Native files copied from a real `flutter create` app.
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
    final target = p.join(to.path, p.relative(entity.path, from: from.path));
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
}

void writeIcon(String relative, {int size = 1024, bool alpha = false}) {
  final image = img.Image(width: size, height: size, numChannels: 4)
    ..clear(
      alpha ? img.ColorRgba8(0, 0, 255, 0) : img.ColorRgba8(30, 140, 90, 255),
    );
  File(path(relative))
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

const identityYaml = '''
default:
  name: Demo
  icon: assets/icon.png
application:
  display_name: Acme Notes
  version: 2.1.0+7
  android:
    application_id: com.acme.notes
    namespace: com.acme.notes
  ios:
    bundle_id: com.acme.notes
  macos:
    bundle_id: com.acme.notes.mac
  windows:
    binary_name: acme_notes
    company_name: Acme Inc.
    copyright: (c) Acme
  linux:
    application_id: com.acme.Notes
    binary_name: acme_notes
  web:
    short_name: Notes
    description: Take notes
    theme_color: "#112233"
build_profiles:
  staging:
    display_name: Acme Notes β
    android:
      application_id: com.acme.notes.staging
''';

Plan applyIdentity([String yaml = identityYaml, String? profile]) {
  File(path('icon_shift.yaml')).writeAsStringSync(yaml);
  final config = loadConfig(project.path);
  final result = Plan(project.path);
  planBuildIdentity(project.path, config.buildIdentity(profile)!, result);
  return result;
}

void main() {
  setUp(() {
    project = Directory.systemTemp.createTempSync('icon_shift_identity_');
    copyDir(Directory(fixture), project);
    writeIcon('assets/icon.png');
  });
  tearDown(() => project.deleteSync(recursive: true));

  group('identifier rules', () {
    test('Android', () {
      expect(androidApplicationIdProblem('com.acme.app'), isNull);
      expect(androidApplicationIdProblem('app'), contains('two segments'));
      expect(
        androidApplicationIdProblem('com.1acme'),
        contains('start with a letter'),
      );
      expect(androidApplicationIdProblem('com.ac-me'), isNotNull);
      expect(
        androidNamespaceProblem('com.class.app'),
        contains('Java keyword'),
      );
    });
    test('Apple', () {
      expect(appleBundleIdProblem('com.acme.app-ios'), isNull);
      expect(appleBundleIdProblem('com.acme_app'), contains('no "_"'));
      expect(appleBundleIdProblem('acme'), isNotNull);
    });
    test('Linux, binaries, versions', () {
      expect(linuxApplicationIdProblem('com.acme.Notes'), isNull);
      expect(linuxApplicationIdProblem('com.9acme'), isNotNull);
      expect(binaryNameProblem('acme_notes'), isNull);
      expect(binaryNameProblem('con'), contains('reserved'));
      expect(binaryNameProblem('my app'), isNotNull);
      expect(versionProblem('1.2.3+4'), isNull);
      expect(versionProblem('1.2'), isNotNull);
    });
  });

  test('reads the identity from the native project', () {
    final id = readProjectIdentity(project.path);
    expect(
      id.get('android', 'applicationId'),
      'com.example.icon_shift_example',
    );
    expect(id.get('ios', 'bundleId'), 'com.example.iconShiftExample');
    expect(id.get('macos', 'bundleId'), 'com.example.iconShiftExample');
    expect(id.get('windows', 'binaryName'), 'icon_shift_example');
    expect(id.get('linux', 'applicationId'), 'com.example.icon_shift');
    expect(id.get('web', 'name'), 'icon_shift_example');
  });

  test('applies a build identity to every platform', () {
    final result = applyIdentity();
    expect(result.hasErrors, isFalse, reason: '${result.messages}');
    result.apply(label: 'identity');

    final gradle = read('android/app/build.gradle.kts');
    expect(gradle, contains('applicationId = "com.acme.notes"'));
    expect(gradle, contains('namespace = "com.acme.notes"'));
    expect(
      exists('android/app/src/main/kotlin/com/acme/notes/MainActivity.kt'),
      isTrue,
    );
    expect(
      exists(
        'android/app/src/main/kotlin/com/example/icon_shift_example/MainActivity.kt',
      ),
      isFalse,
    );
    expect(
      read('android/app/src/main/kotlin/com/acme/notes/MainActivity.kt'),
      startsWith('package com.acme.notes'),
    );
    expect(
      read('android/app/src/main/AndroidManifest.xml'),
      contains('android:label="Acme Notes"'),
    );

    final ios = read('ios/Runner.xcodeproj/project.pbxproj');
    expect(
      RegExp('PRODUCT_BUNDLE_IDENTIFIER = com.acme.notes;').allMatches(ios),
      hasLength(3),
    );
    expect(
      RegExp(
        'PRODUCT_BUNDLE_IDENTIFIER = com.acme.notes.RunnerTests;',
      ).allMatches(ios),
      hasLength(3),
    );
    expect(
      read('ios/Runner/Info.plist'),
      contains('<key>CFBundleDisplayName</key>\n\t<string>Acme Notes</string>'),
    );

    expect(
      read('macos/Runner/Configs/AppInfo.xcconfig'),
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.acme.notes.mac'),
    );
    expect(
      read('macos/Runner.xcodeproj/project.pbxproj'),
      contains('com.acme.notes.mac.RunnerTests;'),
    );
    final macPlist = read('macos/Runner/Info.plist');
    expect(
      macPlist,
      contains('<key>CFBundleName</key>\n\t<string>Acme Notes</string>'),
    );
    expect(macPlist, contains('<key>CFBundleDisplayName</key>'));

    expect(
      read('windows/CMakeLists.txt'),
      contains('set(BINARY_NAME "acme_notes")'),
    );
    final rc = read('windows/runner/Runner.rc');
    expect(rc, contains('VALUE "CompanyName", "Acme Inc." "\\0"'));
    expect(rc, contains('VALUE "OriginalFilename", "acme_notes.exe"'));
    expect(rc, contains('VALUE "ProductName", "Acme Notes"'));
    expect(
      read('windows/runner/main.cpp'),
      contains('window.Create(L"Acme Notes"'),
    );

    final linux = read('linux/CMakeLists.txt');
    expect(linux, contains('set(APPLICATION_ID "com.acme.Notes")'));
    expect(
      read('linux/runner/my_application.cc'),
      contains('gtk_window_set_title(window, "Acme Notes")'),
    );

    final manifest = jsonDecode(read('web/manifest.json')) as Map;
    expect(manifest['name'], 'Acme Notes');
    expect(manifest['short_name'], 'Notes');
    expect(manifest['theme_color'], '#112233');
    expect(read('web/index.html'), contains('<title>Acme Notes</title>'));
    expect(read('pubspec.yaml'), contains('version: 2.1.0+7'));

    expect(
      result.messages.map((m) => m.text).join(),
      contains('creates a different app'),
    );
    expect(result.nextSteps.join(), contains('provisioning profile'));

    // Applying again changes nothing.
    expect(applyIdentity().isEmpty, isTrue);
  });

  test('profiles merge over application', () {
    final result = applyIdentity(identityYaml, 'staging')
      ..apply(label: 'identity');
    expect(result.hasErrors, isFalse);
    expect(
      read('android/app/build.gradle.kts'),
      contains('applicationId = "com.acme.notes.staging"'),
    );
    expect(
      read('android/app/src/main/AndroidManifest.xml'),
      contains('android:label="Acme Notes β"'),
    );
    expect(read('ios/Runner/Info.plist'), contains('Acme Notes β'));
    expect(
      () => loadConfig(project.path).buildIdentity('prod'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('invalid identifiers are errors and nothing is planned', () {
    final result = applyIdentity('''
default: {name: X}
application:
  android: {application_id: app}
  ios: {bundle_id: com.bad_id}
''');
    expect(result.hasErrors, isTrue);
    expect(result.isEmpty, isTrue);
    final errors = result.messages
        .where((m) => m.level == Level.error)
        .map((m) => m.text)
        .join('\n');
    expect(errors, contains('android.application_id "app"'));
    expect(errors, contains('ios.bundle_id "com.bad_id"'));
  });

  test('a file that differs from the template is refused, not guessed', () {
    File(
      path('windows/runner/main.cpp'),
    ).writeAsStringSync('// custom runner\n');
    final result = applyIdentity();
    expect(
      result.messages.where((m) => m.level == Level.error).single.text,
      contains('window.Create'),
    );
  });

  group('backups', () {
    test('rollback restores every file, including moved sources', () {
      final before = {
        for (final f in [
          'android/app/build.gradle.kts',
          'ios/Runner.xcodeproj/project.pbxproj',
          'web/manifest.json',
        ])
          f: read(f),
      };
      final backup = applyIdentity().apply(label: 'identity')!;
      expect(Backup.list(project.path).single.id, backup.id);
      final (:restored, :conflicts) = Backup.list(
        project.path,
      ).single.restore();
      expect(conflicts, isEmpty);
      expect(restored, isNotEmpty);
      before.forEach((f, content) => expect(read(f), content, reason: f));
      expect(
        exists(
          'android/app/src/main/kotlin/com/example/icon_shift_example/MainActivity.kt',
        ),
        isTrue,
      );
      expect(
        exists('android/app/src/main/kotlin/com/acme/notes/MainActivity.kt'),
        isFalse,
      );
      expect(Backup.list(project.path), isEmpty);
    });

    test('files edited after apply are not overwritten without force', () {
      applyIdentity().apply(label: 'identity');
      File(path('web/manifest.json')).writeAsStringSync('{"edited": true}');
      final (:restored, :conflicts) = Backup.list(
        project.path,
      ).single.restore();
      expect(conflicts, ['web/manifest.json']);
      expect(read('web/manifest.json'), '{"edited": true}');
      expect(restored, isNotEmpty, reason: 'other files still restored');
      expect(
        Backup.list(project.path),
        hasLength(1),
        reason: 'kept for --force',
      );
      final forced = Backup.list(project.path).single.restore(force: true);
      expect(forced.conflicts, isEmpty);
      expect(read('web/manifest.json'), contains('icon_shift_example'));
    });
  });

  group('config safety', () {
    test('paths outside the project are rejected', () {
      for (final bad in [
        '../secret.png',
        '/etc/passwd',
        'a/../../b.png',
        r'C:\x.png',
      ]) {
        expect(
          () => GeneratorConfig.parse("default: {icon: '$bad'}"),
          throwsA(
            isA<ConfigException>().having(
              (e) => e.message,
              'm',
              contains('inside the project'),
            ),
          ),
          reason: bad,
        );
      }
      expect(checkProjectPath('assets/./x.png', 'x'), 'assets/x.png');
    });

    test('unknown keys and bad values are reported', () {
      expect(
        () => GeneratorConfig.parse('default: {}\napplication: {androd: {}}'),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => GeneratorConfig.parse('default: {names: {"english!": X}}'),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => GeneratorConfig.parse('default: {appearance: purple}'),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => GeneratorConfig.parse(
          'default: {}\nvariants: {a: {}}\nrenamed: {a: default}',
        ),
        throwsA(isA<ConfigException>()),
      );
      expect(
        () => GeneratorConfig.parse('default: {}\nrenamed: {old: missing}'),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  group('resources', () {
    const resYaml = '''
default:
  name: Demo
  names: {de: Demo DE, pt_BR: Demo BR}
  icon: assets/icon.png
  platforms:
    android:
      monochrome: assets/mono.png
variants:
  dark:
    name: Dark
    appearance: dark
    theme_color: "#000000"
    icon: assets/icon.png
    platforms:
      ios: {dark: assets/icon.png, tinted: assets/icon.png}
renamed:
  old_blue: dark
android:
  adaptive_background: "#FFFFFF"
macos: {app_icon: true}
windows: {app_icon: true}
linux: {icons: true}
web: {icons: true}
dart:
  output: lib/icon_shift_config.g.dart
''';

    Plan generate() {
      File(path('icon_shift.yaml')).writeAsStringSync(resYaml);
      File(path('pubspec.yaml')).writeAsStringSync(
        '${read('pubspec.yaml')}\n  assets:\n    - assets/\n',
      );
      writeIcon('assets/mono.png', size: 432, alpha: true);
      return plan(project.path, loadConfig(project.path));
    }

    test('themed, localized, retired and platform icons', () {
      // The manifest needs markers and the tooling filter to be quiet.
      final manifest = read('android/app/src/main/AndroidManifest.xml')
          .replaceFirst(
            '    </application>',
            '        <!-- icon_shift:aliases:start -->\n        <!-- icon_shift:aliases:end -->\n    </application>',
          );
      File(
        path('android/app/src/main/AndroidManifest.xml'),
      ).writeAsStringSync(manifest);
      final result = generate();
      expect(result.hasErrors, isFalse, reason: '${result.messages}');
      result.apply(label: 'generate');

      const res = 'android/app/src/main/res';
      expect(
        read('$res/mipmap-anydpi-v26/ic_icon_shift_default.xml'),
        contains(
          '<monochrome android:drawable="@mipmap/ic_icon_shift_default_monochrome" />',
        ),
      );
      expect(
        exists('$res/mipmap-xxxhdpi/ic_icon_shift_default_monochrome.png'),
        isTrue,
      );
      expect(
        read('$res/values-de/icon_shift.xml'),
        contains('<string name="icon_shift_label_default">Demo DE</string>'),
      );
      expect(read('$res/values-pt-rBR/icon_shift.xml'), contains('Demo BR'));
      expect(
        read('$res/values-de/icon_shift.xml'),
        contains('<string name="icon_shift_label_dark">Dark</string>'),
        reason: 'own name beats an inherited translation (as in the plugin)',
      );
      final aliases = read('android/app/src/main/AndroidManifest.xml');
      expect(aliases, contains('android:name=".IconShiftAlias_old_blue"'));
      expect(
        aliases,
        contains(
          '<meta-data android:name="icon_shift.retired_to" android:value="dark" />',
        ),
      );
      expect(aliases, contains('Retired variant "old_blue"'));

      final iosSet =
          jsonDecode(
                read(
                  'ios/Runner/Assets.xcassets/dark.appiconset/Contents.json',
                ),
              )
              as Map;
      final appearances = [
        for (final i in iosSet['images'] as List)
          (i as Map)['appearances']?.first?['value'],
      ];
      expect(appearances, [null, 'dark', 'tinted']);

      final mac = img.decodePng(
        File(
          path(
            'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
          ),
        ).readAsBytesSync(),
      )!;
      expect(mac.width, 1024);
      final ico = img.decodeIco(
        File(path('windows/runner/resources/app_icon.ico')).readAsBytesSync(),
      );
      expect(ico, isNotNull);
      expect(
        read('linux/packaging/com.example.icon_shift.desktop'),
        contains('Name[de]=Demo DE'),
      );
      expect(
        exists(
          'linux/packaging/icons/hicolor/256x256/apps/com.example.icon_shift.png',
        ),
        isTrue,
      );
      final web = jsonDecode(read('web/manifest.json')) as Map;
      expect(
        (web['icons'] as List).where(
          (i) => (i as Map)['purpose'] == 'maskable',
        ),
        hasLength(2),
      );

      final dart = read('lib/icon_shift_config.g.dart');
      expect(
        dart,
        contains("localizedNames: {'de': 'Demo DE', 'pt_BR': 'Demo BR'}"),
      );
      expect(dart, contains('appearance: IdentityAppearance.dark'));
      expect(dart, contains('themeColor: 0xFF000000'));
      expect(dart, contains("renamedVariants: {\n    'old_blue': 'dark',"));
      expect(dart, isNot(contains('monochrome')), reason: 'native-only layer');

      // Removing a variant without `renamed:` keeps its alias, retired to default.
      File(path('icon_shift.yaml')).writeAsStringSync(
        resYaml
            .replaceFirst(RegExp(r'renamed:\n  old_blue: dark\n'), '')
            .replaceFirst(RegExp(r'  dark:\n(    .*\n|      .*\n)+'), '')
            .replaceAll('variants:\n', ''),
      );
      final removal = plan(project.path, loadConfig(project.path));
      expect(
        removal.messages.map((m) => m.text).join(),
        contains('variant "dark" was removed'),
      );
      final next = removal.pendingContent(
        'android/app/src/main/AndroidManifest.xml',
      )!;
      expect(next, contains('android:name=".IconShiftAlias_dark"'));
      expect(
        next,
        contains(
          '<meta-data android:name="icon_shift.retired_to" android:value="default" />',
        ),
      );
    });

    test('monochrome without adaptive background is an error', () {
      File(path('icon_shift.yaml')).writeAsStringSync('''
default:
  icon: assets/icon.png
  platforms:
    android: {monochrome: assets/icon.png}
''');
      final result = plan(
        project.path,
        loadConfig(project.path),
        only: {'android'},
      );
      expect(
        result.messages
            .where((m) => m.level == Level.error)
            .map((m) => m.text)
            .join(),
        contains('adaptive_background'),
      );
    });
  });

  group('reports', () {
    test('capabilities and preview text', () {
      expect(capabilitiesReport(platform: 'ios'), contains('applicationId'));
      expect(capabilitiesReport(platform: 'ios'), contains('data NOT kept'));
      File(path('icon_shift.yaml')).writeAsStringSync(identityYaml);
      final text = preview(loadConfig(project.path));
      expect(text, contains('ios      name: Demo → — (build-time only)'));
    });

    test('doctor flags missing pieces', () {
      File(path('icon_shift.yaml')).writeAsStringSync(identityYaml);
      final result = doctor(project.path);
      final text = result.messages.map((m) => m.text).join('\n');
      expect(
        text,
        contains(
          'Platforms in this project: android, ios, macos, windows, linux, web',
        ),
      );
      expect(text, contains('icon_shift is not a dependency'));
      expect(text, contains('.icon_shift/'));
    });
  });

  group('command line', () {
    final cli = p.join(
      p.dirname(fixture),
      '..',
      '..',
      'bin',
      'icon_shift_cli.dart',
    );
    ProcessResult run(List<String> args) => Process.runSync(
      Platform.resolvedExecutable,
      ['run', cli, '--project', project.path, ...args],
    );

    test('exit codes', () {
      expect(run(['validate']).exitCode, 66, reason: 'no config');
      File(path('icon_shift.yaml')).writeAsStringSync(identityYaml);
      final dry = run(['identity', '--apply', '--dry-run']);
      expect(dry.exitCode, 0, reason: '${dry.stderr}');
      expect(dry.stdout, contains('+ applicationId = "com.acme.notes"'));
      expect(
        read('android/app/build.gradle.kts'),
        isNot(contains('com.acme.notes')),
        reason: 'dry run',
      );

      expect(run(['identity', '--apply']).exitCode, 0);
      expect(read('android/app/build.gradle.kts'), contains('com.acme.notes'));
      File(path('web/manifest.json')).writeAsStringSync('{}');
      expect(run(['identity', '--reset']).exitCode, 2, reason: 'conflict');
      expect(run(['identity', '--reset', '--force']).exitCode, 0);
      expect(
        read('android/app/build.gradle.kts'),
        isNot(contains('com.acme.notes')),
      );

      expect(run(['bogus']).exitCode, 64);
      File(
        path('icon_shift.yaml'),
      ).writeAsStringSync('default: {icon: missing.png}');
      expect(run(['validate']).exitCode, 1);
    });
  });
}
