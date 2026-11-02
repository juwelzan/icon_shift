import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

enum Level { info, warning, error }

class Message {
  Message(this.level, this.text);
  final Level level;
  final String text;
  @override
  String toString() => '${level.name.toUpperCase()}: $text';
}

/// File changes the generator intends to make. Nothing touches the disk
/// until [apply], so a run with errors or `--dry-run` changes nothing.
class Plan {
  Plan(this.projectDir);

  final String projectDir;
  final messages = <Message>[];
  final writes = <String, List<int>>{};
  final deletes = <String>{};

  bool get hasErrors => messages.any((m) => m.level == Level.error);

  void info(String text) => messages.add(Message(Level.info, text));
  void warn(String text) => messages.add(Message(Level.warning, text));
  void error(String text) => messages.add(Message(Level.error, text));

  /// Schedules writing [relativePath] unless its content is already equal.
  void write(String relativePath, List<int> bytes) {
    final file = File(p.join(projectDir, relativePath));
    if (file.existsSync() && _equal(file.readAsBytesSync(), bytes)) return;
    writes[relativePath] = bytes;
  }

  void writeString(String relativePath, String content) =>
      write(relativePath, utf8.encode(content));

  void delete(String relativePath) => deletes.add(relativePath);

  /// Performs the changes and returns the touched paths.
  List<String> apply() {
    for (final MapEntry(:key, :value) in writes.entries) {
      final file = File(p.join(projectDir, key));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(value);
    }
    for (final path in deletes) {
      final entity = FileSystemEntity.typeSync(p.join(projectDir, path));
      if (entity == FileSystemEntityType.directory) {
        Directory(p.join(projectDir, path)).deleteSync(recursive: true);
      } else if (entity == FileSystemEntityType.file) {
        File(p.join(projectDir, path)).deleteSync();
      }
    }
    return [...writes.keys, ...deletes];
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
