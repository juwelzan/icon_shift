import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'ownership.dart';
import 'plan.dart';

/// Writes a `const iconShiftConfig` matching the YAML so the runtime and the
/// generated native resources cannot drift apart.
void planDart(GeneratorConfig config, Plan plan) {
  final output = config.dartOutput;
  if (output == null) return;
  final existing = File(p.join(plan.projectDir, output));
  if (existing.existsSync() && !hasDartHeader(existing.readAsStringSync())) {
    plan.error(
      'Dart output "$output" exists and was not generated; refusing to '
      'overwrite it.',
    );
    return;
  }

  final b = StringBuffer()
    ..writeln(dartHeader)
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln("import 'package:icon_shift/icon_shift.dart';")
    ..writeln()
    ..writeln('const iconShiftConfig = IconShiftConfig(')
    ..writeln('  defaultIdentity: ${_identity(config.defaultIdentity, '  ')},');
  if (config.variants.isNotEmpty) {
    b.writeln('  variants: {');
    config.variants.forEach((id, spec) {
      b.writeln("    '$id': ${_identity(spec, '    ')},");
    });
    b.writeln('  },');
  }
  if (config.renamed.isNotEmpty) {
    b.writeln('  renamedVariants: {');
    config.renamed.forEach((from, to) => b.writeln("    '$from': '$to',"));
    b.writeln('  },');
  }
  b.writeln(');');
  // `dart format` may re-wrap the file and add or drop trailing commas;
  // that is not a change.
  String squash(String v) => v
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r',(?=[)\]}])'), '');
  if (existing.existsSync() &&
      squash(existing.readAsStringSync()) == squash(b.toString())) {
    return;
  }
  plan.writeString(output, b.toString());
}

String _identity(IdentitySpec spec, String indent) {
  final fields = <String>[
    if (spec.name != null) 'name: ${_str(spec.name!)}',
    if (spec.icon != null) 'icon: AppIcon.asset(${_str(spec.icon!)})',
    if (spec.names.isNotEmpty) 'localizedNames: ${_names(spec.names)}',
    if (spec.appearance != null)
      'appearance: IdentityAppearance.${spec.appearance}',
    if (spec.themeColor != null)
      'themeColor: 0xFF${spec.themeColor!.substring(1).toUpperCase()}',
    if (spec.platforms.values.any(_hasRuntimeFields))
      'platforms: {\n${spec.platforms.entries.where((e) => _hasRuntimeFields(e.value)).map((e) {
        final o = [if (e.value.name != null) 'name: ${_str(e.value.name!)}', if (e.value.icon != null) 'icon: AppIcon.asset(${_str(e.value.icon!)})', if (e.value.names.isNotEmpty) 'localizedNames: ${_names(e.value.names)}'];
        return '$indent    IconShiftPlatform.${e.key}: IdentityOverride(${o.join(', ')}),';
      }).join('\n')}\n$indent  }',
  ];
  if (fields.isEmpty) return 'AppIdentity()';
  return 'AppIdentity(\n${fields.map((f) => '$indent  $f,').join('\n')}\n$indent)';
}

/// Native-only layers (monochrome, dark, …) have no runtime equivalent.
bool _hasRuntimeFields(OverrideSpec o) =>
    o.name != null || o.icon != null || o.names.isNotEmpty;

String _names(Map<String, String> names) =>
    '{${names.entries.map((e) => "'${e.key}': ${_str(e.value)}").join(', ')}}';

String _str(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}
