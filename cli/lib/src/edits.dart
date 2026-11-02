import 'dart:io';

import 'package:path/path.dart' as p;

import 'plan.dart';

/// One replacement inside a file. [count] is how many matches are expected:
/// an exact number, or `null` for "one or more". Anything else is refused,
/// so a project that does not look like the Flutter template is never
/// edited by guesswork.
class Replacement {
  Replacement(this.what, this.pattern, this.replace, {this.count = 1});

  final String what;
  final RegExp pattern;
  final String Function(Match match) replace;
  final int? count;
}

/// Applies [replacements] to the file at [relativePath] and schedules the
/// result in [plan]. Returns `false` (with an error in [plan]) if the file
/// is missing or a pattern does not match as expected.
bool editFile(
  Plan plan,
  String relativePath,
  List<Replacement> replacements, {
  String? currentContent,
}) {
  final file = File(p.join(plan.projectDir, relativePath));
  final original =
      currentContent ??
      plan.pendingContent(relativePath) ??
      (file.existsSync() ? file.readAsStringSync() : null);
  if (original == null) {
    plan.error(
      '$relativePath not found; cannot change ${replacements.first.what}.',
    );
    return false;
  }
  var content = original;
  for (final r in replacements) {
    final matches = r.pattern.allMatches(content).length;
    final ok = r.count == null ? matches > 0 : matches == r.count;
    if (!ok) {
      plan.error(
        '$relativePath: expected ${r.count ?? 'at least one'} occurrence(s) '
        'of ${r.what}, found $matches. The file differs from the Flutter '
        'template; change ${r.what} by hand.',
      );
      return false;
    }
    content = content.replaceAllMapped(r.pattern, r.replace);
  }
  if (content != original) plan.writeString(relativePath, content);
  return true;
}

/// Escapes text for XML element content and attribute values.
String xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Escapes text for a C / C++ / RC string literal.
String cEscape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
