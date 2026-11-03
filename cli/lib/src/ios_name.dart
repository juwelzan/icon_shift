import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'edits.dart';
import 'ownership.dart';
import 'plan.dart';
import 'remote.dart' show fnv1a64;

/// Every object icon_shift_cli adds to project.pbxproj has an id with this
/// prefix, so later runs can find, replace and remove exactly those.
const _idPrefix = 'A1C05F17';

/// Writes the home-screen name of the iOS app: `CFBundleDisplayName` in
/// Info.plist from the default identity's iOS name, and one
/// `<locale>.lproj/InfoPlist.strings` per localized name, registered in the
/// Xcode project (files on disk that the project does not reference are not
/// copied into the app).
///
/// iOS reads the name from the signed bundle, so it changes with the next
/// build and install, never at runtime.
void planIosDisplayName(GeneratorConfig config, Plan plan) {
  final options = config.ios;
  if (!options.setDisplayName) return;
  final r = config.resolve(defaultVariantId, 'ios');
  final name = r.name;
  if (name == null) return;

  final runner = '${options.projectDir}/Runner';
  final plist = '$runner/Info.plist';
  final content = plan.pendingContent(plist) ?? _read(plan, plist);
  if (content == null) {
    plan.warn(
      'iOS: $plist not found, so the display name "$name" was not set. Set '
      'ios.project_dir, or ios.set_display_name: false.',
    );
    return;
  }
  _setPlistString(plan, plist, content, 'CFBundleDisplayName', name);

  final buildName = config.application?.effectiveIosName;
  if (buildName != null && buildName != name) {
    plan.warn(
      'iOS: application.display_name "$buildName" differs from the default '
      'name "$name" in icon_shift.yaml; `generate` writes "$name" and '
      '`identity --apply` writes "$buildName". Make them equal.',
    );
  }

  final locales = {
    for (final MapEntry(:key, :value) in r.names.entries) _lproj(key): value,
  };
  _planStrings(plan, runner, locales);
  _planProject(plan, options.projectDir, locales.keys.toList()..sort());
}

/// `de` → `de`, `pt_BR` → `pt-BR`, `zh_Hant` → `zh-Hant`.
String _lproj(String locale) => locale.replaceAll('_', '-');

void _planStrings(Plan plan, String runner, Map<String, String> locales) {
  final dir = Directory(p.join(plan.projectDir, runner));
  for (final MapEntry(key: lproj, value: name) in locales.entries) {
    final path = '$runner/$lproj.lproj/InfoPlist.strings';
    final existing = _read(plan, path);
    if (existing != null && !hasGeneratedMarker(existing)) {
      plan.error(
        'iOS: "$path" exists and was not created by $toolName; add '
        '"CFBundleDisplayName" = "$name"; to it by hand, or remove the '
        '"$lproj" name from icon_shift.yaml.',
      );
      continue;
    }
    final content =
        '/* $generatedMarker. Do not edit. */\n'
        '"CFBundleDisplayName" = "${_stringsEscape(name)}";\n';
    if (existing != content) plan.writeString(path, content);
  }
  if (!dir.existsSync()) return;
  for (final lproj in dir.listSync().whereType<Directory>()) {
    final base = p.basenameWithoutExtension(lproj.path);
    final file = File(p.join(lproj.path, 'InfoPlist.strings'));
    if (!lproj.path.endsWith('.lproj') ||
        locales.containsKey(base) ||
        !file.existsSync() ||
        !hasGeneratedMarker(file.readAsStringSync())) {
      continue;
    }
    plan.delete('$runner/$base.lproj/InfoPlist.strings');
  }
}

/// Registers the InfoPlist.strings variant group with the Runner target, or
/// removes it when no locale is left.
void _planProject(Plan plan, String projectDir, List<String> lprojs) {
  final pbxproj = '$projectDir/Runner.xcodeproj/project.pbxproj';
  final original = plan.pendingContent(pbxproj) ?? _read(plan, pbxproj);
  if (original == null) {
    if (lprojs.isNotEmpty) {
      plan.warn(
        'iOS: $pbxproj not found; add the InfoPlist.strings files to the '
        'Runner target in Xcode so the localized names are bundled.',
      );
    }
    return;
  }

  // Drop everything added by an earlier run.
  final ours = RegExp('$_idPrefix[0-9A-F]{16}');
  var text = original
      .replaceAll(
        RegExp(
          '\\t\\t$_idPrefix[0-9A-F]{16} /\\* InfoPlist.strings \\*/ = \\{\\n'
          '\\t\\t\\tisa = PBXVariantGroup;[\\s\\S]*?\\n\\t\\t\\};\\n',
        ),
        '',
      )
      .split('\n')
      .where((line) => !ours.hasMatch(line))
      .join('\n');
  if (lprojs.isEmpty) {
    if (text != original) plan.writeString(pbxproj, text);
    return;
  }

  if (RegExp(r'/\* InfoPlist.strings \*/ = \{').hasMatch(text)) {
    plan.warn(
      'iOS: the Xcode project already has its own InfoPlist.strings; add '
      '"CFBundleDisplayName" for ${lprojs.join(', ')} there. The project was '
      'not changed.',
    );
    return;
  }

  String id(String what) =>
      '$_idPrefix${fnv1a64('icon_shift:$what').toUpperCase()}';
  final group = id('InfoPlist.strings');
  final buildFile = id('InfoPlist.strings in Resources');

  final runnerGroup = RegExp(
    r'\t\t[0-9A-F]{24} /\* Runner \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n',
  ).firstMatch(text);
  final target = RegExp(
    r'/\* Runner \*/ = \{\n\t\t\tisa = PBXNativeTarget;[\s\S]*?buildPhases = \(([\s\S]*?)\);',
  ).firstMatch(text);
  final phaseIds = RegExp(
    '([0-9A-F]{24}) /\\* Resources \\*/',
  ).allMatches(target?.group(1) ?? '').map((m) => m[1]!);
  final resources = phaseIds.isEmpty
      ? null
      : RegExp(
          '\\t\\t${phaseIds.first} /\\* Resources \\*/ = \\{\\n'
          '\\t\\t\\tisa = PBXResourcesBuildPhase;\\n'
          '[\\s\\S]*?files = \\(\\n',
        ).firstMatch(text);
  const anchors = [
    '/* End PBXBuildFile section */',
    '/* End PBXFileReference section */',
  ];
  if (runnerGroup == null ||
      resources == null ||
      anchors.any((a) => !text.contains(a)) ||
      !text.contains('knownRegions = (')) {
    plan.warn(
      'iOS: $pbxproj does not look like the Flutter template; add '
      'InfoPlist.strings (${lprojs.join(', ')}) to the Runner target in Xcode '
      'by hand so the localized names are bundled.',
    );
    return;
  }

  // Insert from the end of the file backwards so earlier offsets stay valid.
  final inserts = <(int, String)>[
    (runnerGroup.end, '\t\t\t\t$group /* InfoPlist.strings */,\n'),
    (
      resources.end,
      '\t\t\t\t$buildFile /* InfoPlist.strings in Resources */,\n',
    ),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  for (final (offset, snippet) in inserts) {
    text = text.replaceRange(offset, offset, snippet);
  }

  text = text.replaceFirst(
    anchors[0],
    '\t\t$buildFile /* InfoPlist.strings in Resources */ = {isa = PBXBuildFile; '
    'fileRef = $group /* InfoPlist.strings */; };\n${anchors[0]}',
  );
  text = text.replaceFirst(
    anchors[1],
    [
      for (final lproj in lprojs)
        '\t\t${id('InfoPlist.strings:$lproj')} /* $lproj */ = {isa = '
            'PBXFileReference; lastKnownFileType = text.plist.strings; name = '
            '${_quote(lproj)}; path = ${_quote('$lproj.lproj/InfoPlist.strings')}; '
            'sourceTree = "<group>"; };\n',
      anchors[1],
    ].join(),
  );

  final variantGroup = [
    '\t\t$group /* InfoPlist.strings */ = {\n',
    '\t\t\tisa = PBXVariantGroup;\n',
    '\t\t\tchildren = (\n',
    for (final lproj in lprojs)
      '\t\t\t\t${id('InfoPlist.strings:$lproj')} /* $lproj */,\n',
    '\t\t\t);\n',
    '\t\t\tname = InfoPlist.strings;\n',
    '\t\t\tsourceTree = "<group>";\n',
    '\t\t};\n',
  ].join();
  const endVariants = '/* End PBXVariantGroup section */';
  text = text.contains(endVariants)
      ? text.replaceFirst(endVariants, '$variantGroup$endVariants')
      : text.replaceFirst(
          '/* Begin XCBuildConfiguration section */',
          '/* Begin PBXVariantGroup section */\n$variantGroup$endVariants\n\n'
              '/* Begin XCBuildConfiguration section */',
        );

  // Xcode lists the project's localizations in knownRegions.
  final regions = RegExp(r'knownRegions = \(([\s\S]*?)\);').firstMatch(text)!;
  final known = RegExp(
    r'"?([A-Za-z0-9-]+)"?,',
  ).allMatches(regions[1]!).map((m) => m[1]!).toSet();
  final missing = lprojs.where((l) => !known.contains(l)).toList();
  if (missing.isNotEmpty) {
    text = text.replaceRange(
      regions.start,
      regions.end,
      'knownRegions = (${regions[1]}${missing.map((l) => '\t${_quote(l)},\n\t\t\t').join()});',
    );
  }

  if (text != original) plan.writeString(pbxproj, text);
}

void _setPlistString(
  Plan plan,
  String plist,
  String content,
  String key,
  String value,
) {
  final existing = RegExp('(<key>$key</key>\\s*<string>)[^<]*(</string>)');
  if (existing.hasMatch(content)) {
    editFile(plan, plist, [
      Replacement(key, existing, (m) => '${m[1]}${xmlEscape(value)}${m[2]}'),
    ], currentContent: content);
  } else if (content.contains('<dict>')) {
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

String? _read(Plan plan, String path) {
  final file = File(p.join(plan.projectDir, path));
  return file.existsSync() ? file.readAsStringSync() : null;
}

String _stringsEscape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// pbxproj values need quotes unless they are plain identifiers.
String _quote(String value) =>
    RegExp(r'^[A-Za-z0-9_./]+$').hasMatch(value) ? value : '"$value"';
