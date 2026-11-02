import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'backup.dart';

enum Level { info, warning, error }

class Message {
  Message(this.level, this.text);
  final Level level;
  final String text;
  @override
  String toString() => '${level.name.toUpperCase()}: $text';
}

/// File changes the CLI intends to make. Nothing touches the disk until
/// [apply], so a run with errors or `--dry-run` changes nothing.
class Plan {
  Plan(this.projectDir);

  final String projectDir;
  final messages = <Message>[];
  final writes = <String, List<int>>{};
  final deletes = <String>{};

  /// Steps the user must take after applying (rebuild, provisioning, …).
  final nextSteps = <String>[];

  bool get hasErrors => messages.any((m) => m.level == Level.error);
  bool get isEmpty => writes.isEmpty && deletes.isEmpty;

  void info(String text) => messages.add(Message(Level.info, text));
  void warn(String text) => messages.add(Message(Level.warning, text));
  void error(String text) => messages.add(Message(Level.error, text));
  void step(String text) {
    if (!nextSteps.contains(text)) nextSteps.add(text);
  }

  /// Schedules writing [relativePath] unless its content is already equal.
  void write(String relativePath, List<int> bytes) {
    deletes.remove(relativePath);
    final file = File(p.join(projectDir, relativePath));
    if (file.existsSync() && _equal(file.readAsBytesSync(), bytes)) {
      writes.remove(relativePath);
      return;
    }
    writes[relativePath] = bytes;
  }

  void writeString(String relativePath, String content) =>
      write(relativePath, utf8.encode(content));

  void delete(String relativePath) {
    writes.remove(relativePath);
    deletes.add(relativePath);
  }

  /// Content scheduled for [relativePath] by an earlier step, so several
  /// steps can edit the same file.
  String? pendingContent(String relativePath) {
    final bytes = writes[relativePath];
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  /// Every path this plan would touch.
  List<String> get touchedPaths => [...writes.keys, ...deletes]..sort();

  /// Human-readable changes; text files include a line diff.
  String describe({bool diffs = true}) {
    final b = StringBuffer();
    for (final path in touchedPaths) {
      final file = File(p.join(projectDir, path));
      if (deletes.contains(path)) {
        b.writeln('  delete $path');
        continue;
      }
      b.writeln('  ${file.existsSync() ? 'modify' : 'create'} $path');
      if (!diffs || !file.existsSync() || !_isText(path)) continue;
      final before = file.readAsStringSync();
      final after = utf8.decode(writes[path]!, allowMalformed: true);
      for (final line in lineDiff(before, after)) {
        b.writeln('      $line');
      }
    }
    return b.toString();
  }

  /// Writes the changes, backing up everything it replaces or deletes first.
  /// Returns the backup (or `null` when nothing changed).
  Backup? apply({required String label}) {
    if (isEmpty) return null;
    final backup = Backup.create(projectDir, label, writes.keys, deletes);
    for (final MapEntry(:key, :value) in writes.entries) {
      final file = File(p.join(projectDir, key));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(value);
    }
    for (final path in deletes) {
      final full = p.join(projectDir, path);
      switch (FileSystemEntity.typeSync(full)) {
        case FileSystemEntityType.directory:
          Directory(full).deleteSync(recursive: true);
        case FileSystemEntityType.file:
          File(full).deleteSync();
        default:
          break;
      }
    }
    backup.recordAfterState();
    return backup;
  }

  static bool _isText(String path) => const {
    '.xml',
    '.kts',
    '.gradle',
    '.kt',
    '.java',
    '.pbxproj',
    '.plist',
    '.xcconfig',
    '.txt',
    '.rc',
    '.cpp',
    '.cc',
    '.h',
    '.json',
    '.html',
    '.yaml',
    '.dart',
    '.desktop',
    '.strings',
  }.contains(p.extension(path).toLowerCase());

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A minimal line diff (`- old` / `+ new`), limited to changed lines.
List<String> lineDiff(String before, String after, {int maxLines = 40}) {
  final a = const LineSplitter().convert(before);
  final b = const LineSplitter().convert(after);
  // Trim the common prefix/suffix, then LCS on the middle.
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var endA = a.length, endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  final x = a.sublist(start, endA), y = b.sublist(start, endB);
  if (x.length * y.length > 4000000) {
    return ['(${x.length} lines replaced by ${y.length} lines)'];
  }
  final lcs = List.generate(x.length + 1, (_) => List.filled(y.length + 1, 0));
  for (var i = x.length - 1; i >= 0; i--) {
    for (var j = y.length - 1; j >= 0; j--) {
      lcs[i][j] = x[i] == y[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] > lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <String>[];
  var i = 0, j = 0;
  while (i < x.length || j < y.length) {
    if (i < x.length && j < y.length && x[i] == y[j]) {
      i++;
      j++;
    } else if (j < y.length &&
        (i == x.length || lcs[i][j + 1] >= lcs[i + 1][j])) {
      out.add('+ ${y[j++].trim()}');
    } else {
      out.add('- ${x[i++].trim()}');
    }
  }
  if (out.length > maxLines) {
    return [
      ...out.take(maxLines),
      '… ${out.length - maxLines} more changed lines',
    ];
  }
  return out;
}
