import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Backups live in `<project>/.icon_shift/backups/<id>/`:
///
///   `manifest.json`  label, time, and per file whether it existed before
///   `before/<path>`  the original content (files that existed)
///   `after/<path>`   the content icon_shift_cli wrote (to detect later edits)
///
/// Rollback restores a file only if it still matches `after/`, so changes
/// made by hand after the CLI ran are never silently discarded.
const backupRoot = '.icon_shift/backups';

class BackupEntry {
  BackupEntry(this.path, {required this.existedBefore, required this.deleted});
  final String path;
  final bool existedBefore;
  final bool deleted;

  Map<String, Object> toJson() => {
    'path': path,
    'existedBefore': existedBefore,
    'deleted': deleted,
  };
}

class Backup {
  Backup._(this.projectDir, this.id, this.label, this.created, this.entries);

  final String projectDir;
  final String id;
  final String label;
  final DateTime created;
  final List<BackupEntry> entries;

  String get dir => p.join(projectDir, backupRoot, id);

  /// Copies the current state of [writes] and [deletes] before they change.
  static Backup create(
    String projectDir,
    String label,
    Iterable<String> writes,
    Iterable<String> deletes,
  ) {
    final now = DateTime.now();
    var id = _stamp(now);
    var suffix = 1;
    while (Directory(p.join(projectDir, backupRoot, id)).existsSync()) {
      id = '${_stamp(now)}_${suffix++}';
    }
    final entries = <BackupEntry>[];
    final backup = Backup._(projectDir, id, label, now, entries);

    void save(String path, {required bool deleted}) {
      final source = p.join(projectDir, path);
      final type = FileSystemEntity.typeSync(source);
      if (type == FileSystemEntityType.directory) {
        for (final f in Directory(
          source,
        ).listSync(recursive: true).whereType<File>()) {
          save(p.relative(f.path, from: projectDir), deleted: deleted);
        }
        return;
      }
      final existed = type == FileSystemEntityType.file;
      if (existed) _copy(source, p.join(backup.dir, 'before', path));
      entries.add(BackupEntry(path, existedBefore: existed, deleted: deleted));
    }

    for (final path in writes) {
      save(path, deleted: false);
    }
    for (final path in deletes) {
      save(path, deleted: true);
    }
    backup._writeManifest();
    return backup;
  }

  /// Records what was written, after [Plan.apply] changed the files.
  void recordAfterState() {
    for (final e in entries.where((e) => !e.deleted)) {
      final file = File(p.join(projectDir, e.path));
      if (file.existsSync()) _copy(file.path, p.join(dir, 'after', e.path));
    }
  }

  void _writeManifest() {
    final file = File(p.join(dir, 'manifest.json'))
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'id': id,
        'label': label,
        'created': created.toIso8601String(),
        'files': [for (final e in entries) e.toJson()],
      }),
    );
  }

  static List<Backup> list(String projectDir) {
    final root = Directory(p.join(projectDir, backupRoot));
    if (!root.existsSync()) return [];
    final backups = <Backup>[];
    for (final dir in root.listSync().whereType<Directory>()) {
      final manifest = File(p.join(dir.path, 'manifest.json'));
      if (!manifest.existsSync()) continue;
      try {
        final json =
            jsonDecode(manifest.readAsStringSync()) as Map<String, Object?>;
        backups.add(
          Backup._(
            projectDir,
            json['id']! as String,
            json['label']! as String,
            DateTime.parse(json['created']! as String),
            [
              for (final f
                  in (json['files']! as List<Object?>)
                      .cast<Map<Object?, Object?>>())
                BackupEntry(
                  f['path']! as String,
                  existedBefore: f['existedBefore']! as bool,
                  deleted: f['deleted']! as bool,
                ),
            ],
          ),
        );
      } on Object {
        continue; // Unreadable backup: ignored, never deleted.
      }
    }
    backups.sort((a, b) => a.id.compareTo(b.id));
    return backups;
  }

  /// Restores this backup. Files changed since the CLI wrote them are left
  /// alone unless [force]; returns `(restored, conflicts)`.
  ({List<String> restored, List<String> conflicts}) restore({
    bool force = false,
  }) {
    final restored = <String>[], conflicts = <String>[];
    for (final e in entries) {
      final current = File(p.join(projectDir, e.path));
      final after = File(p.join(dir, 'after', e.path));
      final unchanged = e.deleted
          ? !current.existsSync()
          : (after.existsSync() &&
                current.existsSync() &&
                _sameBytes(after, current));
      if (!unchanged && !force) {
        conflicts.add(e.path);
        continue;
      }
      if (e.existedBefore) {
        _copy(p.join(dir, 'before', e.path), current.path);
      } else if (current.existsSync()) {
        current.deleteSync();
      }
      restored.add(e.path);
    }
    if (conflicts.isEmpty) Directory(dir).deleteSync(recursive: true);
    return (restored: restored, conflicts: conflicts);
  }

  static void _copy(String from, String to) {
    File(to).parent.createSync(recursive: true);
    File(from).copySync(to);
  }

  static bool _sameBytes(File a, File b) {
    final x = a.readAsBytesSync(), y = b.readAsBytesSync();
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
