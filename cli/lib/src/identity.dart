import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'edits.dart';
import 'plan.dart';

/// Build-time application identity (`application:` in icon_shift.yaml).
///
/// Every field is optional; unset fields are left as they are in the
/// project. Changing identifiers produces a *different app* for the OS —
/// see [identityWarnings].
class BuildIdentity {
  BuildIdentity({
    this.displayName,
    this.version,
    this.androidApplicationId,
    this.androidNamespace,
    this.iosBundleId,
    this.iosDisplayName,
    this.macosBundleId,
    this.macosDisplayName,
    this.windowsBinaryName,
    this.windowsCompanyName,
    this.windowsProductName,
    this.windowsCopyright,
    this.linuxApplicationId,
    this.linuxBinaryName,
    this.webName,
    this.webShortName,
    this.webDescription,
    this.webThemeColor,
    this.webBackgroundColor,
  });

  final String? displayName;
  final String? version;
  final String? androidApplicationId;
  final String? androidNamespace;
  final String? iosBundleId;
  final String? iosDisplayName;
  final String? macosBundleId;
  final String? macosDisplayName;
  final String? windowsBinaryName;
  final String? windowsCompanyName;
  final String? windowsProductName;
  final String? windowsCopyright;
  final String? linuxApplicationId;
  final String? linuxBinaryName;
  final String? webName;
  final String? webShortName;
  final String? webDescription;
  final String? webThemeColor;
  final String? webBackgroundColor;

  String? get effectiveIosName => iosDisplayName ?? displayName;
  String? get effectiveMacosName => macosDisplayName ?? displayName;
  String? get effectiveWindowsName => windowsProductName ?? displayName;
  String? get effectiveWebName => webName ?? displayName;

  /// [overlay] wins field by field.
  BuildIdentity merge(BuildIdentity overlay) => BuildIdentity(
    displayName: overlay.displayName ?? displayName,
    version: overlay.version ?? version,
    androidApplicationId: overlay.androidApplicationId ?? androidApplicationId,
    androidNamespace: overlay.androidNamespace ?? androidNamespace,
    iosBundleId: overlay.iosBundleId ?? iosBundleId,
    iosDisplayName: overlay.iosDisplayName ?? iosDisplayName,
    macosBundleId: overlay.macosBundleId ?? macosBundleId,
    macosDisplayName: overlay.macosDisplayName ?? macosDisplayName,
    windowsBinaryName: overlay.windowsBinaryName ?? windowsBinaryName,
    windowsCompanyName: overlay.windowsCompanyName ?? windowsCompanyName,
    windowsProductName: overlay.windowsProductName ?? windowsProductName,
    windowsCopyright: overlay.windowsCopyright ?? windowsCopyright,
    linuxApplicationId: overlay.linuxApplicationId ?? linuxApplicationId,
    linuxBinaryName: overlay.linuxBinaryName ?? linuxBinaryName,
    webName: overlay.webName ?? webName,
    webShortName: overlay.webShortName ?? webShortName,
    webDescription: overlay.webDescription ?? webDescription,
    webThemeColor: overlay.webThemeColor ?? webThemeColor,
    webBackgroundColor: overlay.webBackgroundColor ?? webBackgroundColor,
  );

  static BuildIdentity parse(Map<Object?, Object?> map, String where) {
    YamlFields.allowKeys(map, where, const {
      'display_name',
      'version',
      'android',
      'ios',
      'macos',
      'windows',
      'linux',
      'web',
    });
    Map<Object?, Object?> section(String name, Set<String> keys) {
      final m = YamlFields.optionalMap(map[name], '$where.$name');
      YamlFields.allowKeys(m, '$where.$name', keys);
      return m;
    }

    String? s(Map<Object?, Object?> m, String key, String at) =>
        YamlFields.string(m[key], '$where.$at');

    final android = section('android', const {'application_id', 'namespace'});
    final ios = section('ios', const {'bundle_id', 'display_name'});
    final macos = section('macos', const {'bundle_id', 'display_name'});
    final windows = section('windows', const {
      'binary_name',
      'company_name',
      'product_name',
      'copyright',
    });
    final linux = section('linux', const {'application_id', 'binary_name'});
    final web = section('web', const {
      'name',
      'short_name',
      'description',
      'theme_color',
      'background_color',
    });
    return BuildIdentity(
      displayName: s(map, 'display_name', 'display_name'),
      version: s(map, 'version', 'version'),
      androidApplicationId: s(
        android,
        'application_id',
        'android.application_id',
      ),
      androidNamespace: s(android, 'namespace', 'android.namespace'),
      iosBundleId: s(ios, 'bundle_id', 'ios.bundle_id'),
      iosDisplayName: s(ios, 'display_name', 'ios.display_name'),
      macosBundleId: s(macos, 'bundle_id', 'macos.bundle_id'),
      macosDisplayName: s(macos, 'display_name', 'macos.display_name'),
      windowsBinaryName: s(windows, 'binary_name', 'windows.binary_name'),
      windowsCompanyName: s(windows, 'company_name', 'windows.company_name'),
      windowsProductName: s(windows, 'product_name', 'windows.product_name'),
      windowsCopyright: s(windows, 'copyright', 'windows.copyright'),
      linuxApplicationId: s(linux, 'application_id', 'linux.application_id'),
      linuxBinaryName: s(linux, 'binary_name', 'linux.binary_name'),
      webName: s(web, 'name', 'web.name'),
      webShortName: s(web, 'short_name', 'web.short_name'),
      webDescription: s(web, 'description', 'web.description'),
      webThemeColor: YamlFields.color(
        web['theme_color'],
        '$where.web.theme_color',
      ),
      webBackgroundColor: YamlFields.color(
        web['background_color'],
        '$where.web.background_color',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Identifier rules

const _javaKeywords = {
  'abstract',
  'assert',
  'boolean',
  'break',
  'byte',
  'case',
  'catch',
  'char',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'double',
  'else',
  'enum',
  'extends',
  'final',
  'finally',
  'float',
  'for',
  'goto',
  'if',
  'implements',
  'import',
  'instanceof',
  'int',
  'interface',
  'long',
  'native',
  'new',
  'package',
  'private',
  'protected',
  'public',
  'return',
  'short',
  'static',
  'strictfp',
  'super',
  'switch',
  'synchronized',
  'this',
  'throw',
  'throws',
  'transient',
  'try',
  'void',
  'volatile',
  'while',
  'true',
  'false',
  'null',
};
const _windowsReserved = {
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

/// Android applicationId: two or more segments, each starting with a letter.
String? androidApplicationIdProblem(String id) {
  final segments = id.split('.');
  if (segments.length < 2) {
    return 'needs at least two segments, like "com.example.app"';
  }
  for (final s in segments) {
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(s)) {
      return 'segment "$s" must start with a letter and contain only '
          'letters, digits and "_"';
    }
  }
  return null;
}

/// Gradle namespace: a valid Java package name.
String? androidNamespaceProblem(String id) {
  final base = androidApplicationIdProblem(id);
  if (base != null) return base;
  for (final s in id.split('.')) {
    if (_javaKeywords.contains(s)) return 'segment "$s" is a Java keyword';
  }
  return null;
}

/// Apple bundle identifier: letters, digits, "-" and ".", reverse-DNS.
String? appleBundleIdProblem(String id) {
  if (id.length > 155) return 'is longer than 155 characters';
  if (!RegExp(r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$').hasMatch(id)) {
    return 'must be reverse-DNS with only letters, digits, "-" and "." '
        '(no "_"), like "com.example.app"';
  }
  return null;
}

/// Linux application ID (D-Bus well-known name rules, used by GTK and
/// Flatpak).
String? linuxApplicationIdProblem(String id) {
  if (id.length > 255) return 'is longer than 255 characters';
  final segments = id.split('.');
  if (segments.length < 2) {
    return 'needs at least two segments, like "com.example.App"';
  }
  for (final s in segments) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(s)) {
      return 'segment "$s" must start with a letter or "_" and contain '
          'only letters, digits, "_" and "-"';
    }
  }
  return null;
}

/// Executable / CMake target names.
String? binaryNameProblem(String name) {
  if (name.length > 64) return 'is longer than 64 characters';
  if (!RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]*$').hasMatch(name)) {
    return 'may only contain letters, digits, "_", "-" and "."';
  }
  if (_windowsReserved.contains(name.toLowerCase())) {
    return 'is a reserved Windows device name';
  }
  return null;
}

/// pubspec version: `x.y.z` with optional pre-release and `+build`.
String? versionProblem(String version) =>
    RegExp(r'^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+\d+)?$').hasMatch(version)
    ? null
    : 'must look like "1.2.3" or "1.2.3+4"';

/// Validates [identity] into [plan] messages.
void validateBuildIdentity(BuildIdentity identity, Plan plan) {
  void check(String? value, String field, String? Function(String) rule) {
    if (value == null) return;
    final problem = rule(value);
    if (problem != null) plan.error('application.$field "$value" $problem.');
  }

  check(
    identity.androidApplicationId,
    'android.application_id',
    androidApplicationIdProblem,
  );
  check(
    identity.androidNamespace,
    'android.namespace',
    androidNamespaceProblem,
  );
  check(identity.iosBundleId, 'ios.bundle_id', appleBundleIdProblem);
  check(identity.macosBundleId, 'macos.bundle_id', appleBundleIdProblem);
  check(
    identity.linuxApplicationId,
    'linux.application_id',
    linuxApplicationIdProblem,
  );
  check(identity.windowsBinaryName, 'windows.binary_name', binaryNameProblem);
  check(identity.linuxBinaryName, 'linux.binary_name', binaryNameProblem);
  check(identity.version, 'version', versionProblem);

  final linuxId = identity.linuxApplicationId;
  if (linuxId != null && linuxId.split('.').length < 3) {
    plan.warn(
      'application.linux.application_id "$linuxId": Flatpak expects at '
      'least three segments (e.g. "com.example.App").',
    );
  }
  if (linuxId != null && linuxId.contains('-')) {
    plan.warn(
      'application.linux.application_id "$linuxId": "-" is allowed but '
      'discouraged in D-Bus names; prefer "_".',
    );
  }
  final shortName = identity.webShortName ?? identity.effectiveWebName;
  if (shortName != null && shortName.length > 12) {
    plan.warn(
      'Web short name "$shortName" is longer than 12 characters and may be '
      'truncated on home screens; set application.web.short_name.',
    );
  }
  final iosName = identity.effectiveIosName;
  if (iosName != null && iosName.length > 12) {
    plan.info('iOS display name "$iosName" may be truncated under the icon.');
  }
  final macName = identity.effectiveMacosName;
  if (macName != null && macName.length > 15) {
    plan.warn(
      'macOS display name "$macName" is longer than 15 characters; Apple '
      'recommends a shorter CFBundleName for the menu bar.',
    );
  }
}

// ---------------------------------------------------------------------------
// Reading the current identity

/// The identity values currently in the native project, `null` when a
/// platform folder or value is absent.
class ProjectIdentity {
  final values = <String, Map<String, String?>>{};

  void set(String platform, String key, String? value) =>
      (values[platform] ??= {})[key] = value;

  String? get(String platform, String key) => values[platform]?[key];
}

String? _read(String projectDir, String path) {
  final file = File(p.join(projectDir, path));
  return file.existsSync() ? file.readAsStringSync() : null;
}

String? _first(String? content, RegExp pattern, [int group = 1]) =>
    content == null ? null : pattern.firstMatch(content)?.group(group);

/// Locates `android/app/build.gradle(.kts)`.
String? androidBuildFile(String projectDir) {
  for (final name in [
    'android/app/build.gradle.kts',
    'android/app/build.gradle',
  ]) {
    if (File(p.join(projectDir, name)).existsSync()) return name;
  }
  return null;
}

final _gradleAppId = RegExp(r'''applicationId\s*=?\s*["']([^"']+)["']''');
final _gradleNamespace = RegExp(r'''namespace\s*=?\s*["']([^"']+)["']''');
final _bundleIdSetting = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;\n]+);');

ProjectIdentity readProjectIdentity(String projectDir) {
  final id = ProjectIdentity();
  final pubspec = _read(projectDir, 'pubspec.yaml');
  id.set(
    'app',
    'version',
    _first(pubspec, RegExp(r'^version:\s*(\S+)', multiLine: true)),
  );

  final gradle = androidBuildFile(projectDir);
  if (gradle != null) {
    final content = _read(projectDir, gradle);
    id.set('android', 'applicationId', _first(content, _gradleAppId));
    id.set('android', 'namespace', _first(content, _gradleNamespace));
    final manifest = _read(
      projectDir,
      'android/app/src/main/AndroidManifest.xml',
    );
    id.set(
      'android',
      'label',
      _first(manifest, RegExp(r'<application\b[^>]*android:label="([^"]*)"')),
    );
  }

  final iosProject = _read(projectDir, 'ios/Runner.xcodeproj/project.pbxproj');
  if (iosProject != null) {
    id.set('ios', 'bundleId', _mainBundleId(iosProject));
    final plist = _read(projectDir, 'ios/Runner/Info.plist');
    id.set('ios', 'displayName', _plistString(plist, 'CFBundleDisplayName'));
  }

  final appInfo = _read(projectDir, 'macos/Runner/Configs/AppInfo.xcconfig');
  if (appInfo != null) {
    id.set(
      'macos',
      'bundleId',
      _first(
        appInfo,
        RegExp(r'^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(.+)$', multiLine: true),
      )?.trim(),
    );
    id.set(
      'macos',
      'productName',
      _first(
        appInfo,
        RegExp(r'^PRODUCT_NAME\s*=\s*(.+)$', multiLine: true),
      )?.trim(),
    );
    final plist = _read(projectDir, 'macos/Runner/Info.plist');
    id.set(
      'macos',
      'displayName',
      _plistString(plist, 'CFBundleDisplayName') ??
          _plistString(plist, 'CFBundleName'),
    );
  }

  final winCmake = _read(projectDir, 'windows/CMakeLists.txt');
  if (winCmake != null) {
    id.set(
      'windows',
      'binaryName',
      _first(winCmake, RegExp(r'set\(BINARY_NAME "([^"]*)"\)')),
    );
    final rc = _read(projectDir, 'windows/runner/Runner.rc');
    for (final key in [
      'CompanyName',
      'ProductName',
      'FileDescription',
      'LegalCopyright',
    ]) {
      id.set('windows', key, _first(rc, RegExp('VALUE "$key", "([^"]*)"')));
    }
    id.set(
      'windows',
      'windowTitle',
      _first(
        _read(projectDir, 'windows/runner/main.cpp'),
        RegExp(r'window\.Create\(L"([^"]*)"'),
      ),
    );
  }

  final linuxCmake = _read(projectDir, 'linux/CMakeLists.txt');
  if (linuxCmake != null) {
    id.set(
      'linux',
      'binaryName',
      _first(linuxCmake, RegExp(r'set\(BINARY_NAME "([^"]*)"\)')),
    );
    id.set(
      'linux',
      'applicationId',
      _first(linuxCmake, RegExp(r'set\(APPLICATION_ID "([^"]*)"\)')),
    );
    id.set(
      'linux',
      'windowTitle',
      _first(
        _read(projectDir, _linuxAppSource(projectDir)),
        RegExp(r'gtk_window_set_title\(window, "([^"]*)"\)'),
      ),
    );
  }

  final manifest = _read(projectDir, 'web/manifest.json');
  if (manifest != null) {
    try {
      final json = jsonDecode(manifest) as Map<String, Object?>;
      for (final key in [
        'name',
        'short_name',
        'description',
        'theme_color',
        'background_color',
        'id',
      ]) {
        id.set('web', key, json[key]?.toString());
      }
    } on FormatException {
      id.set('web', 'name', null);
    }
    id.set(
      'web',
      'title',
      _first(
        _read(projectDir, 'web/index.html'),
        RegExp(r'<title>([^<]*)</title>'),
      ),
    );
  }
  return id;
}

String _linuxAppSource(String projectDir) {
  for (final name in [
    'linux/runner/my_application.cc',
    'linux/my_application.cc',
  ]) {
    if (File(p.join(projectDir, name)).existsSync()) return name;
  }
  return 'linux/runner/my_application.cc';
}

/// The Runner bundle id: the most common PRODUCT_BUNDLE_IDENTIFIER value that
/// is not a test or extension target.
String? _mainBundleId(String pbxproj) {
  final counts = <String, int>{};
  for (final m in _bundleIdSetting.allMatches(pbxproj)) {
    final value = m.group(1)!.trim().replaceAll('"', '');
    counts[value] = (counts[value] ?? 0) + 1;
  }
  final candidates =
      counts.keys.where((k) => !k.endsWith('.RunnerTests')).toList()
        ..sort((a, b) {
          final byCount = counts[b]!.compareTo(counts[a]!);
          return byCount != 0 ? byCount : a.length.compareTo(b.length);
        });
  return candidates.isEmpty ? null : candidates.first;
}

String? _plistString(String? plist, String key) =>
    _first(plist, RegExp('<key>$key</key>\\s*<string>([^<]*)</string>'));

// ---------------------------------------------------------------------------
// Applying

/// Plans every change needed to give the project [identity].
void planBuildIdentity(String projectDir, BuildIdentity identity, Plan plan) {
  validateBuildIdentity(identity, plan);
  if (plan.hasErrors) return;
  final current = readProjectIdentity(projectDir);

  if (identity.version case final version?) {
    editFile(plan, 'pubspec.yaml', [
      Replacement(
        'the pubspec "version:"',
        RegExp(r'^version:.*$', multiLine: true),
        (_) => 'version: $version',
      ),
    ]);
  }
  _planAndroid(projectDir, identity, current, plan);
  _planIos(projectDir, identity, current, plan);
  _planMacos(projectDir, identity, current, plan);
  _planWindows(projectDir, identity, current, plan);
  _planLinux(projectDir, identity, current, plan);
  _planWeb(projectDir, identity, plan);
  identityWarnings(identity, current, plan);
}

bool _hasDir(String projectDir, String dir) =>
    Directory(p.join(projectDir, dir)).existsSync();

void _skipped(Plan plan, String platform, String what) =>
    plan.info('$platform: no $platform/ folder; $what not applied.');

void _planAndroid(
  String projectDir,
  BuildIdentity id,
  ProjectIdentity current,
  Plan plan,
) {
  final wants =
      id.androidApplicationId != null ||
      id.androidNamespace != null ||
      id.displayName != null;
  if (!wants) return;
  final gradle = androidBuildFile(projectDir);
  if (gradle == null) {
    if (id.androidApplicationId != null || id.androidNamespace != null) {
      _skipped(plan, 'android', 'application_id/namespace');
    }
    return;
  }
  final kts = gradle.endsWith('.kts');
  String quoted(String v) => kts ? '"$v"' : "'$v'";
  final edits = <Replacement>[
    if (id.androidApplicationId case final appId?)
      Replacement(
        'applicationId',
        _gradleAppId,
        (_) =>
            kts ? 'applicationId = "$appId"' : 'applicationId ${quoted(appId)}',
      ),
    if (id.androidNamespace case final ns?)
      Replacement(
        'namespace',
        _gradleNamespace,
        (_) => kts ? 'namespace = "$ns"' : 'namespace ${quoted(ns)}',
      ),
  ];
  if (edits.isNotEmpty && !editFile(plan, gradle, edits)) return;

  const manifest = 'android/app/src/main/AndroidManifest.xml';
  final oldNamespace = current.get('android', 'namespace');
  if (id.androidNamespace case final ns?
      when oldNamespace != null && ns != oldNamespace) {
    _planNamespaceMove(projectDir, oldNamespace, ns, manifest, plan);
  }
  if (id.displayName case final name?) {
    _planAndroidLabel(projectDir, manifest, name, plan);
  }
  if (id.androidApplicationId != null &&
      id.androidApplicationId != current.get('android', 'applicationId')) {
    plan.step(
      'Android: the new applicationId installs as a separate app; uninstall the old build or keep both. Run `flutter clean` before building.',
    );
  }
}

void _planAndroidLabel(
  String projectDir,
  String manifest,
  String name,
  Plan plan,
) {
  final content = plan.pendingContent(manifest) ?? _read(projectDir, manifest);
  final label = _first(
    content,
    RegExp(r'<application\b[^>]*android:label="([^"]*)"'),
  );
  if (label == null) {
    plan.error('$manifest: <application> has no android:label; add one first.');
    return;
  }
  if (label.startsWith('@string/')) {
    final key = label.substring('@string/'.length);
    editFile(plan, 'android/app/src/main/res/values/strings.xml', [
      Replacement(
        '<string name="$key">',
        RegExp('<string name="${RegExp.escape(key)}">[^<]*</string>'),
        (_) =>
            '<string name="$key">${xmlEscape(name).replaceAll("'", r"\'")}</string>',
      ),
    ]);
  } else {
    editFile(plan, manifest, [
      Replacement(
        '<application android:label>',
        RegExp(r'(<application\b[^>]*android:label=")[^"]*(")'),
        (m) => '${m[1]}${xmlEscape(name)}${m[2]}',
      ),
    ]);
  }
}

/// Moves Kotlin/Java sources from [from] to [to] and updates package lines.
void _planNamespaceMove(
  String projectDir,
  String from,
  String to,
  String manifest,
  Plan plan,
) {
  final fromPath = from.replaceAll('.', '/');
  final toPath = to.replaceAll('.', '/');
  var moved = 0;
  for (final lang in ['kotlin', 'java']) {
    final dir = Directory(
      p.join(projectDir, 'android/app/src/main', lang, fromPath),
    );
    if (!dir.existsSync()) continue;
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      final rel = p.relative(file.path, from: dir.path);
      final source = p.posix.joinAll(
        p.split(p.relative(file.path, from: projectDir)),
      );
      final target = p.posix.join(
        'android/app/src/main',
        lang,
        toPath,
        p.posix.joinAll(p.split(rel)),
      );
      final text = file
          .readAsStringSync()
          .replaceAllMapped(
            RegExp(
              '^(package\\s+)${RegExp.escape(from)}(?=[.;\\s]|\$)',
              multiLine: true,
            ),
            (m) => '${m[1]}$to',
          )
          .replaceAllMapped(
            RegExp(
              '^(import\\s+)${RegExp.escape(from)}(?=\\.)',
              multiLine: true,
            ),
            (m) => '${m[1]}$to',
          );
      if (File(p.join(projectDir, target)).existsSync()) {
        plan.error(
          'android: $target already exists; cannot move $source there.',
        );
        return;
      }
      plan.writeString(target, text);
      plan.delete(source);
      moved++;
    }
  }
  if (moved == 0) {
    plan.warn(
      'android: no sources found under the old namespace folder $fromPath; only the Gradle namespace changed.',
    );
  }
  final content = plan.pendingContent(manifest) ?? _read(projectDir, manifest);
  if (content != null &&
      (content.contains('"$from.') || content.contains('package="$from"'))) {
    editFile(plan, manifest, [
      Replacement(
        'fully-qualified class names',
        RegExp('"${RegExp.escape(from)}(\\.|")'),
        (m) => '"$to${m[1]}',
        count: null,
      ),
    ]);
  }
}

void _planIos(
  String projectDir,
  BuildIdentity id,
  ProjectIdentity current,
  Plan plan,
) {
  if (id.iosBundleId == null && id.effectiveIosName == null) return;
  if (!_hasDir(projectDir, 'ios')) {
    if (id.iosBundleId != null) _skipped(plan, 'ios', 'bundle_id');
    return;
  }
  if (id.iosBundleId case final bundleId?) {
    final old = current.get('ios', 'bundleId');
    if (old == null) {
      plan.error(
        'ios: no PRODUCT_BUNDLE_IDENTIFIER found in ios/Runner.xcodeproj/project.pbxproj.',
      );
    } else if (old != bundleId) {
      editFile(plan, 'ios/Runner.xcodeproj/project.pbxproj', [
        Replacement(
          'PRODUCT_BUNDLE_IDENTIFIER = $old',
          RegExp(
            'PRODUCT_BUNDLE_IDENTIFIER = ${RegExp.escape(old)}((?:\\.[A-Za-z0-9.-]+)?);',
          ),
          (m) => 'PRODUCT_BUNDLE_IDENTIFIER = $bundleId${m[1]};',
          count: null,
        ),
      ]);
      plan.step(
        'iOS: register the App ID "$bundleId" and use a matching provisioning profile (Xcode → Signing & Capabilities). It installs as a separate app.',
      );
    }
  }
  if (id.effectiveIosName case final name?) {
    _planPlistString(
      projectDir,
      'ios/Runner/Info.plist',
      'CFBundleDisplayName',
      name,
      plan,
    );
  }
}

void _planMacos(
  String projectDir,
  BuildIdentity id,
  ProjectIdentity current,
  Plan plan,
) {
  if (id.macosBundleId == null && id.effectiveMacosName == null) return;
  if (!_hasDir(projectDir, 'macos')) {
    if (id.macosBundleId != null) _skipped(plan, 'macos', 'bundle_id');
    return;
  }
  if (id.macosBundleId case final bundleId?) {
    final old = current.get('macos', 'bundleId');
    if (old != null && old != bundleId) {
      editFile(plan, 'macos/Runner/Configs/AppInfo.xcconfig', [
        Replacement(
          'PRODUCT_BUNDLE_IDENTIFIER',
          RegExp(r'^PRODUCT_BUNDLE_IDENTIFIER\s*=.*$', multiLine: true),
          (_) => 'PRODUCT_BUNDLE_IDENTIFIER = $bundleId',
        ),
      ]);
      const pbx = 'macos/Runner.xcodeproj/project.pbxproj';
      final content = _read(projectDir, pbx);
      if (content != null &&
          content.contains('PRODUCT_BUNDLE_IDENTIFIER = $old.')) {
        editFile(plan, pbx, [
          Replacement(
            'test target bundle ids',
            RegExp(
              'PRODUCT_BUNDLE_IDENTIFIER = ${RegExp.escape(old)}(\\.[A-Za-z0-9.-]+);',
            ),
            (m) => 'PRODUCT_BUNDLE_IDENTIFIER = $bundleId${m[1]};',
            count: null,
          ),
        ]);
      }
      plan.step(
        'macOS: the new bundle id gets new UserDefaults, a new sandbox container and new privacy permissions; re-sign (and notarize) the build.',
      );
    } else if (old == null) {
      plan.error(
        'macos: PRODUCT_BUNDLE_IDENTIFIER not found in macos/Runner/Configs/AppInfo.xcconfig.',
      );
    }
  }
  if (id.effectiveMacosName case final name?) {
    _planPlistString(
      projectDir,
      'macos/Runner/Info.plist',
      'CFBundleName',
      name,
      plan,
    );
    _planPlistString(
      projectDir,
      'macos/Runner/Info.plist',
      'CFBundleDisplayName',
      name,
      plan,
    );
  }
}

/// Sets `<key>` to a `<string>` in a plist, inserting it if missing.
void _planPlistString(
  String projectDir,
  String plist,
  String key,
  String value,
  Plan plan,
) {
  final content = plan.pendingContent(plist) ?? _read(projectDir, plist);
  if (content == null) {
    plan.error('$plist not found.');
    return;
  }
  final existing = RegExp('(<key>$key</key>\\s*<string>)[^<]*(</string>)');
  if (existing.hasMatch(content)) {
    editFile(plan, plist, [
      Replacement(key, existing, (m) => '${m[1]}${xmlEscape(value)}${m[2]}'),
    ], currentContent: content);
  } else if (content.contains('<dict>')) {
    // The first <dict> is the plist's top-level dictionary.
    plan.writeString(
      plist,
      content.replaceFirst(
        '<dict>',
        '<dict>\n\t<key>$key</key>\n\t<string>${xmlEscape(value)}</string>',
      ),
    );
  } else {
    plan.error('$plist has no <dict>; cannot add $key.');
  }
}

void _planWindows(
  String projectDir,
  BuildIdentity id,
  ProjectIdentity current,
  Plan plan,
) {
  final name = id.effectiveWindowsName;
  final wants =
      id.windowsBinaryName != null ||
      name != null ||
      id.windowsCompanyName != null ||
      id.windowsCopyright != null;
  if (!wants) return;
  if (!_hasDir(projectDir, 'windows')) {
    if (id.windowsBinaryName != null) _skipped(plan, 'windows', 'binary_name');
    return;
  }
  final binary = id.windowsBinaryName;
  if (binary != null && binary != current.get('windows', 'binaryName')) {
    editFile(plan, 'windows/CMakeLists.txt', [
      Replacement(
        'set(BINARY_NAME ...)',
        RegExp(r'set\(BINARY_NAME "[^"]*"\)'),
        (_) => 'set(BINARY_NAME "$binary")',
      ),
    ]);
  }
  Replacement rcValue(String key, String value) => Replacement(
    'VALUE "$key"',
    RegExp('(VALUE "$key", )"[^"]*"'),
    (m) => '${m[1]}"${cEscape(value)}"',
  );
  editFile(plan, 'windows/runner/Runner.rc', [
    if (id.windowsCompanyName case final c?) rcValue('CompanyName', c),
    if (name != null) rcValue('FileDescription', name),
    if (name != null) rcValue('ProductName', name),
    if (id.windowsCopyright case final c?) rcValue('LegalCopyright', c),
    if (binary != null) rcValue('InternalName', binary),
    if (binary != null) rcValue('OriginalFilename', '$binary.exe'),
  ]);
  if (name != null) {
    editFile(plan, 'windows/runner/main.cpp', [
      Replacement(
        'window.Create(L"...")',
        RegExp(r'window\.Create\(L"[^"]*"'),
        (_) => 'window.Create(L"${cEscape(name)}"',
      ),
    ]);
  }
  if (id.windowsCompanyName != null || name != null) {
    plan.warn(
      'windows: path_provider derives %APPDATA% folders from CompanyName/ProductName, so data saved by builds with the old names will not be found. Migrate it explicitly if needed.',
    );
  }
}

void _planLinux(
  String projectDir,
  BuildIdentity id,
  ProjectIdentity current,
  Plan plan,
) {
  final wants =
      id.linuxApplicationId != null ||
      id.linuxBinaryName != null ||
      id.displayName != null;
  if (!wants) return;
  if (!_hasDir(projectDir, 'linux')) {
    if (id.linuxApplicationId != null) {
      _skipped(plan, 'linux', 'application_id');
    }
    return;
  }
  editFile(plan, 'linux/CMakeLists.txt', [
    if (id.linuxBinaryName case final b?)
      Replacement(
        'set(BINARY_NAME ...)',
        RegExp(r'set\(BINARY_NAME "[^"]*"\)'),
        (_) => 'set(BINARY_NAME "$b")',
      ),
    if (id.linuxApplicationId case final a?)
      Replacement(
        'set(APPLICATION_ID ...)',
        RegExp(r'set\(APPLICATION_ID "[^"]*"\)'),
        (_) => 'set(APPLICATION_ID "$a")',
      ),
  ]);
  if (id.displayName case final name?) {
    editFile(plan, _linuxAppSource(projectDir), [
      Replacement(
        'gtk_header_bar_set_title(...)',
        RegExp(r'gtk_header_bar_set_title\(header_bar, "[^"]*"\)'),
        (_) => 'gtk_header_bar_set_title(header_bar, "${cEscape(name)}")',
      ),
      Replacement(
        'gtk_window_set_title(...)',
        RegExp(r'gtk_window_set_title\(window, "[^"]*"\)'),
        (_) => 'gtk_window_set_title(window, "${cEscape(name)}")',
      ),
    ]);
  }
  if (id.linuxApplicationId != null &&
      id.linuxApplicationId != current.get('linux', 'applicationId')) {
    plan.step(
      'Linux: rename your installed .desktop file and icons to "${id.linuxApplicationId}" so the desktop matches windows to the launcher (enable linux.icons to generate them).',
    );
  }
}

void _planWeb(String projectDir, BuildIdentity id, Plan plan) {
  final name = id.effectiveWebName;
  final wants =
      name != null ||
      id.webShortName != null ||
      id.webDescription != null ||
      id.webThemeColor != null ||
      id.webBackgroundColor != null;
  if (!wants) return;
  const manifestPath = 'web/manifest.json';
  final raw =
      plan.pendingContent(manifestPath) ?? _read(projectDir, manifestPath);
  if (raw == null) {
    _skipped(plan, 'web', 'PWA metadata');
    return;
  }
  final Map<String, Object?> json;
  try {
    json = jsonDecode(raw) as Map<String, Object?>;
  } on FormatException catch (e) {
    plan.error('$manifestPath is not valid JSON: ${e.message}');
    return;
  }
  if (name != null) json['name'] = name;
  if (id.webShortName ?? name case final s?) json['short_name'] = s;
  if (id.webDescription case final d?) json['description'] = d;
  if (id.webThemeColor case final c?) json['theme_color'] = c;
  if (id.webBackgroundColor case final c?) json['background_color'] = c;
  plan.writeString(
    manifestPath,
    '${const JsonEncoder.withIndent('    ').convert(json)}\n',
  );

  if (name != null) {
    const index = 'web/index.html';
    final html = _read(projectDir, index);
    if (html != null) {
      editFile(plan, index, [
        Replacement(
          '<title>',
          RegExp(r'<title>[^<]*</title>'),
          (_) => '<title>${xmlEscape(name)}</title>',
        ),
        if (html.contains('apple-mobile-web-app-title'))
          Replacement(
            'apple-mobile-web-app-title',
            RegExp(
              r'(<meta name="apple-mobile-web-app-title" content=")[^"]*(")',
            ),
            (m) => '${m[1]}${xmlEscape(name)}${m[2]}',
          ),
        if (id.webDescription != null &&
            html.contains('<meta name="description"'))
          Replacement(
            'meta description',
            RegExp(r'(<meta name="description" content=")[^"]*(")'),
            (m) => '${m[1]}${xmlEscape(id.webDescription!)}${m[2]}',
          ),
      ]);
    }
    plan.step(
      'Web: installed PWAs pick up the new name/icons only when the browser re-checks manifest.json (some browsers ask the user; iOS home-screen apps generally need re-adding).',
    );
  }
}

/// Explains consequences that are easy to miss.
void identityWarnings(BuildIdentity id, ProjectIdentity current, Plan plan) {
  final changes = [
    if (id.androidApplicationId != null &&
        id.androidApplicationId != current.get('android', 'applicationId'))
      'Android applicationId',
    if (id.iosBundleId != null &&
        id.iosBundleId != current.get('ios', 'bundleId'))
      'iOS bundle id',
    if (id.macosBundleId != null &&
        id.macosBundleId != current.get('macos', 'bundleId'))
      'macOS bundle id',
    if (id.linuxApplicationId != null &&
        id.linuxApplicationId != current.get('linux', 'applicationId'))
      'Linux application id',
  ];
  if (changes.isNotEmpty) {
    plan.warn(
      'Changing ${changes.join(', ')} creates a different app for the OS: '
      'it installs next to the old one and cannot read the old app\'s data. '
      'Existing users will not receive it as an update. This is a build-time '
      'change only; no installed app is modified.',
    );
  }
  plan.step(
    'Rebuild the app (`flutter clean`, then `flutter build <platform>`); identity changes never apply to an installed build.',
  );
}
